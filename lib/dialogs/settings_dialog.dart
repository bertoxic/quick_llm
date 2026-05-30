import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class SettingsDialog extends StatefulWidget {
  final TextEditingController systemPromptController;
  final bool useSystemPrompt;
  final double temperature;
  final int maxTokens;
  final int numCtx;
  final bool isDarkMode;
  final Function(bool) onUseSystemPromptChanged;
  final Function(double) onTemperatureChanged;
  final Function(int) onMaxTokensChanged;
  final Function(int) onNumCtxChanged;
  final VoidCallback onSave;

  const SettingsDialog({
    super.key,
    required this.systemPromptController,
    required this.useSystemPrompt,
    required this.temperature,
    required this.maxTokens,
    required this.numCtx,
    required this.isDarkMode,
    required this.onUseSystemPromptChanged,
    required this.onTemperatureChanged,
    required this.onMaxTokensChanged,
    required this.onNumCtxChanged,
    required this.onSave,
  });

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late bool _useSystemPrompt;
  late double _temperature;
  late int _maxTokens;
  late int _numCtx;

  @override
  void initState() {
    super.initState();
    _useSystemPrompt = widget.useSystemPrompt;
    _temperature = widget.temperature;
    _maxTokens = widget.maxTokens;
    _numCtx = widget.numCtx;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 760),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.porcelain,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.line),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSystemPrompt(),
                      const SizedBox(height: 14),
                      _SettingSlider(
                        icon: Icons.thermostat_rounded,
                        title: 'Temperature',
                        valueText: _temperature.toStringAsFixed(2),
                        description: _temperatureDescription(),
                        minLabel: '0.0',
                        maxLabel: '2.0',
                        value: _temperature,
                        min: 0,
                        max: 2,
                        divisions: 20,
                        accent: AppColors.orange,
                        onChanged: (value) {
                          setState(() => _temperature = value);
                          widget.onTemperatureChanged(value);
                        },
                      ),
                      const SizedBox(height: 14),
                      _SettingSlider(
                        icon: Icons.format_size_rounded,
                        title: 'Max tokens',
                        valueText: _maxTokens.toString(),
                        description:
                            'Approximately ${(_maxTokens * 0.75).toInt()} words',
                        minLabel: '256',
                        maxLabel: '256K',
                        value: _maxTokens.toDouble(),
                        min: 256,
                        max: 256000,
                        divisions: 15,
                        accent: AppColors.teal,
                        onChanged: (value) {
                          final next = value.toInt();
                          setState(() => _maxTokens = next);
                          widget.onMaxTokensChanged(next);
                        },
                      ),
                      const SizedBox(height: 14),
                      _SettingSlider(
                        icon: Icons.memory_rounded,
                        title: 'Context window',
                        valueText: _numCtx.toString(),
                        description: _contextDescription(),
                        minLabel: '2K',
                        maxLabel: '128K',
                        value: _numCtx.toDouble(),
                        min: 2048,
                        max: 128000,
                        divisions: 12,
                        accent: AppColors.charcoal,
                        onChanged: (value) {
                          final next = value.toInt();
                          setState(() => _numCtx = next);
                          widget.onNumCtxChanged(next);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              _buildActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.ink,
              borderRadius: BorderRadius.circular(9),
            ),
            child:
                const Icon(Icons.tune_rounded, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Advanced Settings',
              style: TextStyle(
                color: AppColors.charcoal,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _buildSystemPrompt() {
    return _SettingsCard(
      icon: Icons.psychology_rounded,
      title: 'System Prompt',
      value: _useSystemPrompt ? 'Enabled' : 'Disabled',
      accent: AppColors.orange,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.line),
            ),
            child: TextField(
              controller: widget.systemPromptController,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: 'You are a helpful assistant...',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.all(14),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            value: _useSystemPrompt,
            onChanged: (value) {
              setState(() => _useSystemPrompt = value);
              widget.onUseSystemPromptChanged(value);
            },
            contentPadding: EdgeInsets.zero,
            activeColor: AppColors.orange,
            title: const Text(
              'Use system prompt',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
            subtitle: const Text(
              'Include this instruction with every request.',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: () {
              widget.onSave();
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  String _temperatureDescription() {
    if (_temperature < 0.3) return 'Very focused and deterministic';
    if (_temperature < 0.7) return 'Balanced creativity and focus';
    if (_temperature < 1.2) return 'More creative and varied';
    return 'Very creative and random';
  }

  String _contextDescription() {
    if (_numCtx < 4096) return 'Short memory for quick questions';
    if (_numCtx < 16384) return 'Standard memory for most conversations';
    if (_numCtx < 65536) return 'Large memory for long documents';
    return 'Massive memory for very large contexts';
  }
}

class _SettingSlider extends StatelessWidget {
  final IconData icon;
  final String title;
  final String valueText;
  final String description;
  final String minLabel;
  final String maxLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final Color accent;
  final ValueChanged<double> onChanged;

  const _SettingSlider({
    required this.icon,
    required this.title,
    required this.valueText,
    required this.description,
    required this.minLabel,
    required this.maxLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.accent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      icon: icon,
      title: title,
      value: valueText,
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(minLabel,
                  style: const TextStyle(color: AppColors.muted, fontSize: 11)),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: accent,
                    inactiveTrackColor: AppColors.line,
                    thumbColor: accent,
                    overlayColor: accent.withOpacity(0.14),
                    trackHeight: 4,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 7),
                  ),
                  child: Slider(
                    value: value,
                    min: min,
                    max: max,
                    divisions: divisions,
                    label: valueText,
                    onChanged: onChanged,
                  ),
                ),
              ),
              Text(maxLabel,
                  style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            ],
          ),
          Text(
            description,
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color accent;
  final Widget child;

  const _SettingsCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.accent,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: accent, size: 17),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.charcoal,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: accent.withOpacity(0.28)),
                ),
                child: Text(
                  value,
                  style: TextStyle(
                    color: accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
