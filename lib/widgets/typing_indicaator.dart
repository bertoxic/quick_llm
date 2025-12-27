import 'package:flutter/material.dart';

/// Animated typing indicator that shows when AI is thinking
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
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    )..repeat();
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AI Avatar
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: widget.isDarkMode
                  ? Colors.blue[700]!.withOpacity(0.3)
                  : Colors.blue[100],
              shape: BoxShape.circle,
              border: Border.all(
                color: widget.isDarkMode ? Colors.blue[600]! : Colors.blue[300]!,
                width: 2,
              ),
            ),
            child: Icon(
              Icons.smart_toy_rounded,
              size: 18,
              color: widget.isDarkMode ? Colors.blue[300] : Colors.blue[700],
            ),
          ),
          const SizedBox(width: 12),
          // Typing bubble
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: widget.isDarkMode
                    ? Colors.grey[800]!.withOpacity(0.5)
                    : Colors.grey[200],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: widget.isDarkMode
                      ? Colors.grey[700]!
                      : Colors.grey[300]!,
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.modelName != null) ...[
                    Text(
                      widget.modelName!,
                      style: TextStyle(
                        fontSize: 11,
                        color: widget.isDarkMode
                            ? Colors.grey[500]
                            : Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildDot(0),
                      const SizedBox(width: 4),
                      _buildDot(1),
                      const SizedBox(width: 4),
                      _buildDot(2),
                      const SizedBox(width: 12),
                      Text(
                        'Thinking...',
                        style: TextStyle(
                          fontSize: 13,
                          color: widget.isDarkMode
                              ? Colors.grey[500]
                              : Colors.grey[600],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDot(int index) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        // Calculate delay for each dot
        final delay = index * 0.2;
        final value = (_animation.value + delay) % 1.0;

        // Scale and opacity animation
        final scale = 0.6 + (0.4 * (1 - (value - 0.5).abs() * 2));
        final opacity = 0.3 + (0.7 * (1 - (value - 0.5).abs() * 2));

        return Transform.scale(
          scale: scale,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: (widget.isDarkMode ? Colors.blue[400] : Colors.blue[600])!
                  .withOpacity(opacity),
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}


/// Animated "Generating..." indicator for conversations
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
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;
  String _dots = '';
  int _dotCount = 0;

  @override
  void initState() {
    super.initState();

    // Pulsing animation
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _opacityAnimation = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));

    // Dots animation
    _animateDots();
  }

  void _animateDots() {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _dotCount = (_dotCount + 1) % 4;
          _dots = '.' * _dotCount;
        });
        _animateDots();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacityAnimation,
      builder: (context, child) {
        return Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.15),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: Colors.green.withOpacity(_opacityAnimation.value * 0.5),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Animated spinning circle
              SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Colors.green.withOpacity(_opacityAnimation.value),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Text with animated dots
              Text(
                'Generating$_dots',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.green.withOpacity(_opacityAnimation.value),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// Helper class to store parsed results
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