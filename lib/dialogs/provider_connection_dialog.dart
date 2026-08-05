import 'package:flutter/material.dart';

import '../models/ai_provider.dart';
import '../theme/app_theme.dart';

class ProviderConnectionDialog extends StatefulWidget {
  final AiProviderConfig initialConfiguration;
  final Future<void> Function(AiProviderConfig configuration) onSave;

  const ProviderConnectionDialog({
    super.key,
    required this.initialConfiguration,
    required this.onSave,
  });

  @override
  State<ProviderConnectionDialog> createState() =>
      _ProviderConnectionDialogState();
}

class _ProviderConnectionDialogState extends State<ProviderConnectionDialog> {
  late AiProviderKind _kind;
  late final TextEditingController _nameController;
  late final TextEditingController _endpointController;
  late final TextEditingController _apiKeyController;
  bool _saving = false;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    _kind = widget.initialConfiguration.kind;
    _nameController =
        TextEditingController(text: widget.initialConfiguration.displayName);
    _endpointController = TextEditingController(
        text: widget.initialConfiguration.normalizedEndpoint);
    _apiKeyController =
        TextEditingController(text: widget.initialConfiguration.apiKey);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _endpointController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  void _changeKind(AiProviderKind? next) {
    if (next == null || next == _kind) return;
    final previousDefault = _kind == AiProviderKind.ollama
        ? AiProviderConfig.ollama()
        : AiProviderConfig.openAiCompatible();
    final nextDefault = next == AiProviderKind.ollama
        ? AiProviderConfig.ollama()
        : AiProviderConfig.openAiCompatible();
    setState(() {
      _kind = next;
      if (_endpointController.text.trim() ==
          previousDefault.normalizedEndpoint) {
        _endpointController.text = nextDefault.normalizedEndpoint;
      }
      if (_nameController.text.trim() == previousDefault.displayName) {
        _nameController.text = nextDefault.displayName;
      }
    });
  }

  Future<void> _save() async {
    final endpoint = _endpointController.text.trim();
    final parsed = Uri.tryParse(endpoint);
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
      _showError(
          'Enter a complete endpoint URL, including http:// or https://.');
      return;
    }

    final defaults = _kind == AiProviderKind.ollama
        ? AiProviderConfig.ollama()
        : AiProviderConfig.openAiCompatible();
    final configuration = AiProviderConfig(
      kind: _kind,
      name: _nameController.text.trim().isEmpty
          ? defaults.displayName
          : _nameController.text.trim(),
      endpoint: endpoint,
      apiKey: _apiKeyController.text.trim(),
    );

    setState(() => _saving = true);
    try {
      await widget.onSave(configuration);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      _showError('$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isOllama = _kind == AiProviderKind.ollama;
    return AlertDialog(
      title: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.teal.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.hub_rounded, color: AppColors.teal),
          ),
          const SizedBox(width: 10),
          const Expanded(child: Text('AI Connection')),
        ],
      ),
      content: SizedBox(
        width: 470,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Connect one model catalog at a time. Your existing chats and native tool suite stay available across providers.',
                style: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.68),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 18),
              DropdownButtonFormField<AiProviderKind>(
                initialValue: _kind,
                decoration: const InputDecoration(
                  labelText: 'Connection type',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: AiProviderKind.ollama,
                    child: Text('Ollama (local / self-hosted)'),
                  ),
                  DropdownMenuItem(
                    value: AiProviderKind.openAiCompatible,
                    child: Text('OpenAI-compatible API'),
                  ),
                ],
                onChanged: _saving ? null : _changeKind,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _nameController,
                enabled: !_saving,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Connection name',
                  hintText: 'e.g. Work vLLM or OpenAI',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _endpointController,
                enabled: !_saving,
                keyboardType: TextInputType.url,
                textInputAction:
                    isOllama ? TextInputAction.done : TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Endpoint',
                  hintText: isOllama
                      ? 'http://localhost:11434'
                      : 'https://api.openai.com/v1',
                  border: const OutlineInputBorder(),
                ),
              ),
              if (!isOllama) ...[
                const SizedBox(height: 14),
                TextField(
                  controller: _apiKeyController,
                  enabled: !_saving,
                  obscureText: _obscureKey,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'API key (optional for local servers)',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: _obscureKey ? 'Show API key' : 'Hide API key',
                      onPressed: () =>
                          setState(() => _obscureKey = !_obscureKey),
                      icon: Icon(
                        _obscureKey
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'For safety, API keys are kept only for this app session and are never saved to preferences.',
                  style: TextStyle(
                    color: colorScheme.onSurface.withValues(alpha: 0.62),
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _CompatibilityNote(isOllama: isOllama),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync_rounded),
          label: Text(_saving ? 'Connecting…' : 'Save & load models'),
        ),
      ],
    );
  }
}

class _CompatibilityNote extends StatelessWidget {
  final bool isOllama;

  const _CompatibilityNote({required this.isOllama});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.teal.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.teal.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 18, color: AppColors.teal),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              isOllama
                  ? 'Use this for Ollama on this computer or a reachable Ollama server. Models are loaded from /api/tags.'
                  : 'Works with services exposing /v1/models and /v1/chat/completions, including OpenAI, LM Studio, vLLM, LocalAI, OpenRouter, Groq, and Together.',
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.76),
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
