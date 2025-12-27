import 'package:flutter/material.dart';

/// Dialog for configuring advanced AI settings with modern design
/// Allows users to customize system prompt, temperature, and token limits
class SettingsDialog extends StatefulWidget {
  /// Controller for the system prompt text field
  final TextEditingController systemPromptController;

  /// Whether to use the system prompt in requests
  final bool useSystemPrompt;

  /// Temperature setting (0.0 - 2.0) for response randomness
  final double temperature;

  /// Maximum number of tokens to generate
  final int maxTokens;

  /// Dark mode flag for theming
  final bool isDarkMode;

  /// Callback when use system prompt checkbox changes
  final Function(bool) onUseSystemPromptChanged;

  /// Callback when temperature slider changes
  final Function(double) onTemperatureChanged;

  /// Callback when max tokens slider changes
  final Function(int) onMaxTokensChanged;

  /// Callback when user saves the settings
  final VoidCallback onSave;

  const SettingsDialog({
    super.key,
    required this.systemPromptController,
    required this.useSystemPrompt,
    required this.temperature,
    required this.maxTokens,
    required this.isDarkMode,
    required this.onUseSystemPromptChanged,
    required this.onTemperatureChanged,
    required this.onMaxTokensChanged,
    required this.onSave,
  });

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late bool _useSystemPrompt;
  late double _temperature;
  late int _maxTokens;

  @override
  void initState() {
    super.initState();
    _useSystemPrompt = widget.useSystemPrompt;
    _temperature = widget.temperature;
    _maxTokens = widget.maxTokens;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 500,
        constraints: const BoxConstraints(maxHeight: 700),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: widget.isDarkMode
                ? [
              const Color(0xFF1E1E1E),
              const Color(0xFF252525),
            ]
                : [
              Colors.white,
              Colors.grey[50]!,
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: widget.isDarkMode ? Colors.grey[800]! : Colors.grey[300]!,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: widget.isDarkMode
                  ? Colors.black.withOpacity(0.5)
                  : Colors.black.withOpacity(0.15),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSystemPromptSection(),
                    const SizedBox(height: 24),
                    _buildDivider(),
                    const SizedBox(height: 24),
                    _buildTemperatureSection(),
                    const SizedBox(height: 24),
                    _buildMaxTokensSection(),
                  ],
                ),
              ),
            ),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  /// Builds the modern dialog header
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: widget.isDarkMode
              ? [
            Colors.grey[850]!.withOpacity(0.8),
            Colors.grey[900]!.withOpacity(0.6),
          ]
              : [
            Colors.grey[100]!,
            Colors.grey[50]!,
          ],
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
        border: Border(
          bottom: BorderSide(
            color: widget.isDarkMode ? Colors.grey[800]! : Colors.grey[300]!,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: widget.isDarkMode
                  ? Colors.red[900]!.withOpacity(0.3)
                  : Colors.red[50],
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.tune_rounded,
              size: 24,
              color: widget.isDarkMode ? Colors.red[300] : Colors.red[700],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Advanced Settings',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: widget.isDarkMode ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the system prompt configuration section
  Widget _buildSystemPromptSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.psychology_rounded,
          title: 'System Prompt',
          tooltip: 'System prompts define the AI\'s behavior and personality',
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: widget.isDarkMode
                ? Colors.grey[850]!.withOpacity(0.6)
                : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.isDarkMode ? Colors.grey[800]! : Colors.grey[300]!,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.isDarkMode
                    ? Colors.black.withOpacity(0.2)
                    : Colors.black.withOpacity(0.03),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: TextField(
            controller: widget.systemPromptController,
            decoration: InputDecoration(
              hintText: 'You are a helpful assistant...',
              hintStyle: TextStyle(
                color: widget.isDarkMode ? Colors.grey[600] : Colors.grey[400],
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(16),
              helperText: 'Define how the AI should behave',
              helperStyle: TextStyle(
                color: widget.isDarkMode ? Colors.grey[500] : Colors.grey[600],
                fontSize: 12,
              ),
            ),
            style: TextStyle(
              color: widget.isDarkMode ? Colors.white : Colors.black87,
              fontSize: 14,
            ),
            maxLines: 4,
            minLines: 3,
          ),
        ),
        const SizedBox(height: 12),
        _buildCheckboxTile(
          title: 'Enable System Prompt',
          subtitle: 'Use this prompt for all requests',
          value: _useSystemPrompt,
          onChanged: (value) {
            setState(() {
              _useSystemPrompt = value ?? false;
            });
            widget.onUseSystemPromptChanged(_useSystemPrompt);
          },
        ),
      ],
    );
  }

  /// Builds the temperature slider section
  Widget _buildTemperatureSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.thermostat_rounded,
          title: 'Temperature',
          tooltip: 'Higher values make output more random, lower values more focused',
          value: _temperature.toStringAsFixed(2),
          valueColor: Colors.red,
        ),
        const SizedBox(height: 16),
        _buildSlider(
          value: _temperature,
          min: 0.0,
          max: 2.0,
          divisions: 20,
          minLabel: '0.0',
          maxLabel: '2.0',
          activeColor: Colors.red,
          onChanged: (value) {
            setState(() {
              _temperature = value;
            });
            widget.onTemperatureChanged(value);
          },
        ),
        const SizedBox(height: 8),
        Text(
          _getTemperatureDescription(),
          style: TextStyle(
            fontSize: 12,
            color: widget.isDarkMode ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
      ],
    );
  }

  /// Builds the max tokens slider section
  Widget _buildMaxTokensSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.format_size_rounded,
          title: 'Max Tokens',
          tooltip: 'Maximum length of the AI response',
          value: _maxTokens.toString(),
          valueColor: Colors.green,
        ),
        const SizedBox(height: 16),
        _buildSlider(
          value: _maxTokens.toDouble(),
          min: 256,
          max: 104096,
          divisions: 15,
          minLabel: '256',
          maxLabel: '104096',
          activeColor: Colors.green,
          onChanged: (value) {
            setState(() {
              _maxTokens = value.toInt();
            });
            widget.onMaxTokensChanged(value.toInt());
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Approximately ${(_maxTokens * 0.75).toInt()} words',
          style: TextStyle(
            fontSize: 12,
            color: widget.isDarkMode ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
      ],
    );
  }

  /// Builds a section header with icon and optional value display
  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required String tooltip,
    String? value,
    Color? valueColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: widget.isDarkMode
                    ? (valueColor ?? Colors.red[900])!.withOpacity(0.3)
                    : (valueColor ?? Colors.red[50]),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 18,
                color: widget.isDarkMode
                    ? (valueColor ?? Colors.red[300])
                    : (valueColor ?? Colors.red[700]),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: widget.isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: tooltip,
              child: Icon(
                Icons.info_outline,
                size: 16,
                color: widget.isDarkMode ? Colors.grey[500] : Colors.grey[600],
              ),
            ),
          ],
        ),
        if (value != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: widget.isDarkMode
                  ? (valueColor ?? Colors.red[900])!.withOpacity(0.3)
                  : (valueColor ?? Colors.red[50]),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: widget.isDarkMode
                    ? (valueColor ?? Colors.red[700])!
                    : (valueColor ?? Colors.red[300])!,
                width: 1,
              ),
            ),
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: widget.isDarkMode
                    ? (valueColor ?? Colors.red[300])
                    : (valueColor ?? Colors.red[700]),
              ),
            ),
          ),
      ],
    );
  }

  /// Builds a modern slider with labels
  Widget _buildSlider({
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String minLabel,
    required String maxLabel,
    required Color activeColor,
    required ValueChanged<double> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: widget.isDarkMode
            ? Colors.grey[850]!.withOpacity(0.6)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.isDarkMode ? Colors.grey[800]! : Colors.grey[300]!,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Text(
            minLabel,
            style: TextStyle(
              fontSize: 12,
              color: widget.isDarkMode ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: activeColor,
                inactiveTrackColor: widget.isDarkMode
                    ? Colors.grey[800]
                    : Colors.grey[300],
                thumbColor: activeColor,
                overlayColor: activeColor.withOpacity(0.2),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              ),
              child: Slider(
                value: value,
                min: min,
                max: max,
                divisions: divisions,
                label: value is int ? value.toString() : value.toStringAsFixed(2),
                onChanged: onChanged,
              ),
            ),
          ),
          Text(
            maxLabel,
            style: TextStyle(
              fontSize: 12,
              color: widget.isDarkMode ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  /// Builds a modern checkbox list tile
  Widget _buildCheckboxTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool?> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: widget.isDarkMode
            ? Colors.grey[850]!.withOpacity(0.6)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value
              ? (widget.isDarkMode ? Colors.red[700]! : Colors.red[300]!)
              : (widget.isDarkMode ? Colors.grey[800]! : Colors.grey[300]!),
          width: 1.5,
        ),
      ),
      child: CheckboxListTile(
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: widget.isDarkMode ? Colors.white : Colors.black87,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: widget.isDarkMode ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
        value: value,
        onChanged: onChanged,
        activeColor: widget.isDarkMode ? Colors.red[300] : Colors.red[700],
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        controlAffinity: ListTileControlAffinity.leading,
      ),
    );
  }

  /// Builds a divider
  Widget _buildDivider() {
    return Container(
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.transparent,
            widget.isDarkMode ? Colors.grey[800]! : Colors.grey[300]!,
            Colors.transparent,
          ],
        ),
      ),
    );
  }

  /// Builds the action buttons
  Widget _buildActions() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: widget.isDarkMode
              ? [
            Colors.grey[850]!.withOpacity(0.8),
            Colors.grey[900]!.withOpacity(0.6),
          ]
              : [
            Colors.grey[100]!,
            Colors.grey[50]!,
          ],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
        border: Border(
          top: BorderSide(
            color: widget.isDarkMode ? Colors.grey[800]! : Colors.grey[300]!,
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _buildButton(
            label: 'Cancel',
            onPressed: () => Navigator.pop(context),
            isPrimary: false,
          ),
          const SizedBox(width: 12),
          _buildButton(
            label: 'Save',
            onPressed: () {
              widget.onSave();
              Navigator.pop(context);
            },
            isPrimary: true,
          ),
        ],
      ),
    );
  }

  /// Builds a modern button
  Widget _buildButton({
    required String label,
    required VoidCallback onPressed,
    required bool isPrimary,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: isPrimary
            ? LinearGradient(
          colors: widget.isDarkMode
              ? [Colors.red[700]!, Colors.red[800]!]
              : [Colors.red[600]!, Colors.red[700]!],
        )
            : null,
        color: isPrimary
            ? null
            : (widget.isDarkMode
            ? Colors.grey[850]!.withOpacity(0.5)
            : Colors.grey[200]),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isPrimary
              ? (widget.isDarkMode ? Colors.red[600]! : Colors.red[500]!)
              : (widget.isDarkMode ? Colors.grey[700]! : Colors.grey[400]!),
          width: 1,
        ),
        boxShadow: isPrimary
            ? [
          BoxShadow(
            color: (widget.isDarkMode ? Colors.red[900]! : Colors.red[300]!)
                .withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: isPrimary
                    ? Colors.white
                    : (widget.isDarkMode ? Colors.grey[300] : Colors.grey[800]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Returns a description based on the temperature value
  String _getTemperatureDescription() {
    if (_temperature < 0.3) {
      return 'Very focused and deterministic';
    } else if (_temperature < 0.7) {
      return 'Balanced creativity and focus';
    } else if (_temperature < 1.2) {
      return 'More creative and varied';
    } else {
      return 'Very creative and random';
    }
  }
}