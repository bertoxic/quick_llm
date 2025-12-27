// split_chat_view.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../provider/ChatProvider.dart';
import '../models/chat_message.dart';
import '../widgets/message_bubble.dart';
import '../widgets/typing_indicaator.dart';

class SplitChatView extends StatefulWidget {
  final int? conversationIndex;
  final bool isDarkMode;
  final bool isLeftPane;
  final Function(String, {int? conversationIndex})? onSendMessage;

  const SplitChatView({
    super.key,
    required this.conversationIndex,
    required this.isDarkMode,
    required this.isLeftPane,
    this.onSendMessage,
  });

  @override
  State<SplitChatView> createState() => _SplitChatViewState();
}

class _SplitChatViewState extends State<SplitChatView> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<ChatMessage> _getMessages() {
    final provider = context.read<ChatProvider>();
    if (widget.conversationIndex == null) return [];
    if (widget.conversationIndex! >= provider.conversations.length) return [];
    return provider.conversations[widget.conversationIndex!].messages;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, provider, child) {
        final messages = _getMessages();
        final conversation = widget.conversationIndex != null &&
            widget.conversationIndex! < provider.conversations.length
            ? provider.conversations[widget.conversationIndex!]
            : null;

        return Container(
          decoration: BoxDecoration(
            color: widget.isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
            border: Border.all(
              color: widget.isDarkMode ? Colors.grey[800]! : Colors.grey[300]!,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: widget.isDarkMode ? Colors.grey[850] : Colors.grey[100],
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                ),
                child: Row(
                  children: [
                    Icon(
                      widget.isLeftPane ? Icons.view_sidebar : Icons.view_sidebar_outlined,
                      size: 18,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        conversation?.title ?? 'No conversation selected',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: messages.isEmpty
                    ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 48,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Select a conversation',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ],
                  ),
                )
                    : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    return MessageBubble(
                      message: message,
                      isDarkMode: widget.isDarkMode,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// resizable_split_view.dart
class ResizableSplitView extends StatefulWidget {
  final Widget left;
  final Widget right;
  final double initialRatio;
  final ValueChanged<double>? onRatioChanged;
  final bool isDarkMode;

  const ResizableSplitView({
    super.key,
    required this.left,
    required this.right,
    this.initialRatio = 0.5,
    this.onRatioChanged,
    required this.isDarkMode,
  });

  @override
  State<ResizableSplitView> createState() => _ResizableSplitViewState();
}

class _ResizableSplitViewState extends State<ResizableSplitView> {
  late double _ratio;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _ratio = widget.initialRatio;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final leftWidth = width * _ratio;
        final rightWidth = width * (1 - _ratio);

        return Row(
          children: [
            SizedBox(
              width: leftWidth,
              child: widget.left,
            ),
            GestureDetector(
              onHorizontalDragStart: (_) {
                setState(() => _isDragging = true);
              },
              onHorizontalDragUpdate: (details) {
                setState(() {
                  _ratio = (leftWidth + details.delta.dx) / width;
                  _ratio = _ratio.clamp(0.2, 0.8);
                  widget.onRatioChanged?.call(_ratio);
                });
              },
              onHorizontalDragEnd: (_) {
                setState(() => _isDragging = false);
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: Container(
                  width: 8,
                  color: _isDragging
                      ? Colors.blue.withOpacity(0.5)
                      : (widget.isDarkMode ? Colors.grey[800] : Colors.grey[300]),
                  child: Center(
                    child: Container(
                      width: 2,
                      color: widget.isDarkMode ? Colors.grey[700] : Colors.grey[400],
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: rightWidth,
              child: widget.right,
            ),
          ],
        );
      },
    );
  }
}