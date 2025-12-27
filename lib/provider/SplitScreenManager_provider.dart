// split_screen_manager.dart
import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../models/conversation.dart';

class SplitScreenManager extends ChangeNotifier {
  int? _leftConversationIndex;
  int? _rightConversationIndex;
  bool _isSplitMode = false;
  double _splitRatio = 0.5;
  List<ChatMessage> _rightPaneMessages = [];

  int? get leftConversationIndex => _leftConversationIndex;
  int? get rightConversationIndex => _rightConversationIndex;
  bool get isSplitMode => _isSplitMode;
  double get splitRatio => _splitRatio;
  List<ChatMessage> get rightPaneMessages => _rightPaneMessages;

  void enableSplitMode(int leftIndex, int rightIndex) {
    _leftConversationIndex = leftIndex;
    _rightConversationIndex = rightIndex;
    _isSplitMode = true;
    notifyListeners();
  }

  void disableSplitMode() {
    _isSplitMode = false;
    _rightConversationIndex = null;
    _rightPaneMessages = [];
    notifyListeners();
  }

  void setLeftConversation(int index) {
    _leftConversationIndex = index;
    notifyListeners();
  }

  void setRightConversation(int index) {
    _rightConversationIndex = index;
    notifyListeners();
  }

  void setRightPaneMessages(List<ChatMessage> messages) {
    _rightPaneMessages = messages;
    notifyListeners();
  }

  void updateSplitRatio(double ratio) {
    _splitRatio = ratio.clamp(0.2, 0.8);
    notifyListeners();
  }

  void swapPanes() {
    final tempIndex = _leftConversationIndex;
    _leftConversationIndex = _rightConversationIndex;
    _rightConversationIndex = tempIndex;
    notifyListeners();
  }
}


class DraggableConversationTile extends StatelessWidget {
  final int index;
  final Conversation conversation;
  final bool isSelected;
  final bool isGenerating;
  final bool isDarkMode;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final Function(Conversation) onExport;
  final Function(int, int) onDragToSplit;

  const DraggableConversationTile({
    super.key,
    required this.index,
    required this.conversation,
    required this.isSelected,
    required this.isGenerating,
    required this.isDarkMode,
    required this.onTap,
    required this.onDelete,
    required this.onExport,
    required this.onDragToSplit,
  });

  @override
  Widget build(BuildContext context) {
    return LongPressDraggable<int>(
      data: index,
      feedback: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 240,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDarkMode ? Colors.grey[800] : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue, width: 2),
          ),
          child: Text(
            conversation.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _buildTileContent(),
      ),
      child: _buildTileContent(),
    );
  }

  Widget _buildTileContent() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? (isDarkMode ? Colors.blue[800]!.withOpacity(0.4) : Colors.blue[100])
                  : (isDarkMode ? Colors.grey[850]!.withOpacity(0.5) : Colors.white),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isGenerating
                    ? Colors.green.withOpacity(0.5)
                    : (isSelected
                    ? (isDarkMode ? Colors.blue[600]! : Colors.blue[300]!)
                    : Colors.transparent),
                width: isGenerating ? 2.0 : 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        conversation.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                    ),
                    Icon(Icons.drag_indicator, size: 18, color: Colors.grey[600]),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}