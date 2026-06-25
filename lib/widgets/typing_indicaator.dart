import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class TypingIndicator extends StatefulWidget {
  final bool isDarkMode;
  final String? modelName;

  const TypingIndicator({
    super.key,
    required this.isDarkMode,
    this.modelName,
  });

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.ink,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PulseDot(controller: _controller, offset: 0),
                const SizedBox(width: 4),
                _PulseDot(controller: _controller, offset: 0.18),
                const SizedBox(width: 4),
                _PulseDot(controller: _controller, offset: 0.36),
                const SizedBox(width: 10),
                Text(
                  widget.modelName == null
                      ? 'Thinking...'
                      : '${widget.modelName} is warming up...',
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseDot extends StatelessWidget {
  final AnimationController controller;
  final double offset;

  const _PulseDot({required this.controller, required this.offset});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final value = (controller.value + offset) % 1.0;
        final opacity = 0.32 + (0.68 * (1 - (value - 0.5).abs() * 2));
        final size = 5.5 + (2.5 * opacity);
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.orange.withOpacity(opacity),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}

class GeneratingIndicator extends StatefulWidget {
  final bool isDarkMode;

  const GeneratingIndicator({
    super.key,
    required this.isDarkMode,
  });

  @override
  State<GeneratingIndicator> createState() => _GeneratingIndicatorState();
}

class _GeneratingIndicatorState extends State<GeneratingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 7),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.teal.withOpacity(0.12),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppColors.teal.withOpacity(0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              valueColor: AlwaysStoppedAnimation<Color>(
                AppColors.teal.withOpacity(0.9),
              ),
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'Generating',
            style: TextStyle(
              color: AppColors.teal,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class ParsedThinkingResult {
  final String displayText;
  final String? thinkingText;
  final bool isThinking;

  ParsedThinkingResult({
    required this.displayText,
    this.thinkingText,
    required this.isThinking,
  });
}
