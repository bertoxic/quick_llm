import 'dart:collection';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../models/voice_settings.dart';

/// Generates speech through a local OpenAI-compatible TTS server.
///
/// The ten most recently used generated files are kept in a small on-disk LRU
/// cache. Replaying or downloading the same reply therefore avoids another
/// network request to the voice server.
class VoiceService {
  VoiceService({http.Client? client, AudioPlayer? audioPlayer})
      : _client = client ?? http.Client(),
        _audioPlayer = audioPlayer ?? AudioPlayer();

  final http.Client _client;
  final AudioPlayer _audioPlayer;
  final LinkedHashMap<String, File> _audioCache = LinkedHashMap();
  final Map<String, Future<File>> _inFlightAudio = {};

  static const int _maximumCachedAudio = 10;

  bool get isPlaying => _audioPlayer.playing;
  Duration get position => _audioPlayer.position;
  Duration? get duration => _audioPlayer.duration;
  Stream<PlayerState> get playerStateStream => _audioPlayer.playerStateStream;
  Stream<Duration> get positionStream => _audioPlayer.positionStream;
  Stream<Duration?> get durationStream => _audioPlayer.durationStream;

  Future<List<String>> fetchVoices(VoiceSettings settings) async {
    final response = await _client
        .get(settings.voicesUri)
        .timeout(const Duration(seconds: 8));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw VoiceServiceException(_responseError(response));
    }

    final decoded = jsonDecode(response.body);
    final source = decoded is Map<String, dynamic>
        ? (decoded['voices'] ?? decoded['data'])
        : decoded;
    if (source is! List) return const [];

    final voices = source
        .map((entry) {
          if (entry is String) return entry;
          if (entry is Map) return entry['id'] ?? entry['name'];
          return null;
        })
        .whereType<String>()
        .map((voice) => voice.trim())
        .where((voice) => voice.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return voices;
  }

  Future<void> speak(String text, VoiceSettings settings) async {
    final audioFile = await _audioFor(text, settings);

    await _audioPlayer.stop();
    await _audioPlayer.setFilePath(audioFile.path);
    unawaited(_audioPlayer.play());
  }

  /// Saves audio in the user's Downloads directory. This reuses a cached
  /// response whenever the text and voice settings match.
  Future<File> download(String text, VoiceSettings settings) async {
    final audioFile = await _audioFor(text, settings);
    final directory = await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    final fileName = 'quick_llm_${DateTime.now().microsecondsSinceEpoch}.mp3';
    final downloadedAudio = File(
      '${directory.path}${Platform.pathSeparator}$fileName',
    );
    return audioFile.copy(downloadedAudio.path);
  }

  Future<File> _audioFor(String text, VoiceSettings settings) async {
    final input = text.trim();
    if (input.isEmpty) {
      throw const VoiceServiceException(
          'There is no text to convert to audio.');
    }
    if (settings.model.trim().isEmpty || settings.voice.trim().isEmpty) {
      throw const VoiceServiceException('Enter both a voice model and voice.');
    }

    final cacheKey = _cacheKey(input, settings);
    final cachedFile = _audioCache.remove(cacheKey);
    if (cachedFile != null) {
      if (await cachedFile.exists()) {
        _audioCache[cacheKey] = cachedFile;
        return cachedFile;
      }
    }

    return _inFlightAudio.putIfAbsent(
      cacheKey,
      () => _generateAudio(input, settings, cacheKey),
    );
  }

  Future<File> _generateAudio(
    String input,
    VoiceSettings settings,
    String cacheKey,
  ) async {
    try {
      final response = await _client
          .post(
            settings.speechUri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'model': settings.model.trim(),
              'input': input,
              'voice': settings.voice.trim(),
              'response_format': 'mp3',
              'speed': settings.speed,
            }),
          )
          .timeout(const Duration(seconds: 45));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw VoiceServiceException(_responseError(response));
      }
      if (response.bodyBytes.isEmpty) {
        throw const VoiceServiceException(
            'The voice server returned no audio.');
      }

      final directory = await getTemporaryDirectory();
      final voiceDirectory = Directory(
        '${directory.path}${Platform.pathSeparator}quick_llm_voice',
      );
      if (!await voiceDirectory.exists()) {
        await voiceDirectory.create(recursive: true);
      }
      final audioFile = File(
        '${voiceDirectory.path}${Platform.pathSeparator}$cacheKey-${DateTime.now().microsecondsSinceEpoch}.mp3',
      );
      await audioFile.writeAsBytes(response.bodyBytes, flush: true);
      _audioCache[cacheKey] = audioFile;
      await _trimAudioCache();
      return audioFile;
    } finally {
      _inFlightAudio.remove(cacheKey);
    }
  }

  String _cacheKey(String input, VoiceSettings settings) {
    final payload = jsonEncode({
      'endpoint': settings.normalizedEndpoint,
      'model': settings.model.trim(),
      'voice': settings.voice.trim(),
      'speed': settings.speed,
      'input': input,
    });
    return sha256.convert(utf8.encode(payload)).toString();
  }

  Future<void> _trimAudioCache() async {
    while (_audioCache.length > _maximumCachedAudio) {
      final oldestEntry = _audioCache.entries.first;
      _audioCache.remove(oldestEntry.key);
      try {
        if (await oldestEntry.value.exists()) {
          await oldestEntry.value.delete();
        }
      } catch (_) {
        // An audio file can be locked while playing on some desktop platforms.
      }
    }
  }

  /// Starts the current audio file again, preserving its position if paused.
  Future<void> resume() async {
    final duration = _audioPlayer.duration;
    final isAtEnd = duration == null || _audioPlayer.position >= duration;
    if (_audioPlayer.processingState == ProcessingState.completed && isAtEnd) {
      await _audioPlayer.seek(Duration.zero);
    }
    unawaited(_audioPlayer.play());
  }

  /// Stops playback and returns the current audio to the beginning.
  Future<void> stop() async {
    await _audioPlayer.pause();
    await _audioPlayer.seek(Duration.zero);
  }

  Future<void> seek(Duration position) => _audioPlayer.seek(position);

  Future<void> dispose() async {
    await _audioPlayer.dispose();
    _client.close();
    for (final file in _audioCache.values) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Temporary operating-system cleanup is sufficient if a file is busy.
      }
    }
  }

  static String _responseError(http.Response response) {
    final body = response.body.trim();
    final details = body.isEmpty
        ? ''
        : ': ${body.length > 260 ? '${body.substring(0, 260)}...' : body}';
    return 'Voice server returned HTTP ${response.statusCode}$details';
  }
}

class VoiceServiceException implements Exception {
  final String message;

  const VoiceServiceException(this.message);

  @override
  String toString() => message;
}
