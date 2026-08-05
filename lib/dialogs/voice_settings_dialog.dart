import 'package:flutter/material.dart';

import '../models/voice_settings.dart';

class VoiceSettingsDialog extends StatefulWidget {
  final VoiceSettings initialSettings;
  final ValueChanged<VoiceSettings> onSave;
  final Future<List<String>> Function(VoiceSettings) onLoadVoices;
  final Future<void> Function(String, VoiceSettings) onTestSpeech;

  const VoiceSettingsDialog({
    super.key,
    required this.initialSettings,
    required this.onSave,
    required this.onLoadVoices,
    required this.onTestSpeech,
  });

  @override
  State<VoiceSettingsDialog> createState() => _VoiceSettingsDialogState();
}

class _VoiceSettingsDialogState extends State<VoiceSettingsDialog> {
  late final TextEditingController _endpointController;
  late final TextEditingController _modelController;
  late final TextEditingController _voiceController;
  late bool _enabled;
  late double _speed;
  bool _isLoadingVoices = false;
  bool _isTesting = false;
  List<String> _availableVoices = const [];

  @override
  void initState() {
    super.initState();
    final settings = widget.initialSettings;
    _endpointController = TextEditingController(text: settings.endpoint);
    _modelController = TextEditingController(text: settings.model);
    _voiceController = TextEditingController(text: settings.voice);
    _enabled = settings.enabled;
    _speed = settings.speed;
  }

  @override
  void dispose() {
    _endpointController.dispose();
    _modelController.dispose();
    _voiceController.dispose();
    super.dispose();
  }

  VoiceSettings get _settings => VoiceSettings(
        enabled: _enabled,
        endpoint: _endpointController.text,
        model: _modelController.text,
        voice: _voiceController.text,
        speed: _speed,
      );

  Future<void> _loadVoices() async {
    setState(() => _isLoadingVoices = true);
    try {
      final voices = await widget.onLoadVoices(_settings);
      if (!mounted) return;
      setState(() => _availableVoices = voices);
      if (voices.isEmpty) {
        _showMessage(
            'The server did not return a voice list. You can enter one manually.');
      }
    } catch (error) {
      _showMessage('Could not load voices: $error');
    } finally {
      if (mounted) setState(() => _isLoadingVoices = false);
    }
  }

  Future<void> _testSpeech() async {
    setState(() => _isTesting = true);
    try {
      await widget.onTestSpeech('Hello from Quick LLM.', _settings);
      if (mounted) _showMessage('Playing test speech.');
    } catch (error) {
      if (mounted) _showMessage('Could not generate speech: $error');
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.record_voice_over_rounded),
          SizedBox(width: 10),
          Text('Local Voice / TTS'),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Connect a local OpenAI-compatible voice server. Kokoro FastAPI defaults to localhost:8880.',
                style: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.68),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable voice playback'),
                subtitle: const Text(
                    'Generate audio only when you choose an assistant reply.'),
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _endpointController,
                decoration: const InputDecoration(
                  labelText: 'Voice server URL',
                  hintText: 'http://localhost:8880/v1',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _modelController,
                      decoration: const InputDecoration(
                        labelText: 'TTS model',
                        hintText: 'kokoro',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _voiceController,
                      decoration: const InputDecoration(
                        labelText: 'Voice',
                        hintText: 'af_bella',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _isLoadingVoices ? null : _loadVoices,
                  icon: _isLoadingVoices
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                  label: const Text('Load voices from server'),
                ),
              ),
              if (_availableVoices.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _availableVoices
                      .map(
                        (voice) => ChoiceChip(
                          label: Text(voice),
                          selected: _voiceController.text == voice,
                          onSelected: (_) => setState(
                            () => _voiceController.text = voice,
                          ),
                        ),
                      )
                      .toList(),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Speed'),
                  Expanded(
                    child: Slider(
                      value: _speed,
                      min: 0.5,
                      max: 2,
                      divisions: 15,
                      label: '${_speed.toStringAsFixed(1)}x',
                      onChanged: (value) => setState(() => _speed = value),
                    ),
                  ),
                  Text('${_speed.toStringAsFixed(1)}x'),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isTesting ? null : _testSpeech,
          child: _isTesting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Test voice'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            widget.onSave(_settings);
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
