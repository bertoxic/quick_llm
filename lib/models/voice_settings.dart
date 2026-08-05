/// Settings for an OpenAI-compatible local text-to-speech server.
///
/// Kokoro FastAPI is the default because it exposes `/v1/audio/speech`, but
/// any server that accepts the OpenAI speech request shape can be used.
class VoiceSettings {
  final bool enabled;
  final String endpoint;
  final String model;
  final String voice;
  final double speed;

  const VoiceSettings({
    required this.enabled,
    required this.endpoint,
    required this.model,
    required this.voice,
    required this.speed,
  });

  factory VoiceSettings.kokoro() => const VoiceSettings(
        enabled: false,
        endpoint: 'http://localhost:8880/v1',
        model: 'kokoro',
        voice: 'af_bella',
        speed: 1,
      );

  factory VoiceSettings.fromPreferences(Map<String, dynamic> preferences) {
    final defaults = VoiceSettings.kokoro();
    return VoiceSettings(
      enabled: preferences['voiceEnabled'] as bool? ?? defaults.enabled,
      endpoint: preferences['voiceEndpoint'] as String? ?? defaults.endpoint,
      model: preferences['voiceModel'] as String? ?? defaults.model,
      voice: preferences['voiceName'] as String? ?? defaults.voice,
      speed: (preferences['voiceSpeed'] as num?)?.toDouble() ?? defaults.speed,
    );
  }

  /// Accept either the server root (for example localhost:8880) or /v1.
  String get normalizedEndpoint {
    final value = endpoint.trim().replaceFirst(RegExp(r'/+$'), '');
    if (value.isEmpty) return VoiceSettings.kokoro().endpoint;
    return value.endsWith('/v1') ? value : '$value/v1';
  }

  Uri get speechUri => Uri.parse('$normalizedEndpoint/audio/speech');
  Uri get voicesUri => Uri.parse('$normalizedEndpoint/audio/voices');

  Map<String, dynamic> toPreferenceValues() => {
        'voiceEnabled': enabled,
        'voiceEndpoint': endpoint.trim(),
        'voiceModel': model.trim(),
        'voiceName': voice.trim(),
        'voiceSpeed': speed,
      };

  VoiceSettings copyWith({
    bool? enabled,
    String? endpoint,
    String? model,
    String? voice,
    double? speed,
  }) {
    return VoiceSettings(
      enabled: enabled ?? this.enabled,
      endpoint: endpoint ?? this.endpoint,
      model: model ?? this.model,
      voice: voice ?? this.voice,
      speed: speed ?? this.speed,
    );
  }
}
