import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/chat_message.dart';
import '../provider/ChatProvider.dart';
import '../services/ollama_service.dart';
import '../widgets/typing_indicaator.dart';
import '../widgets/message_bubble.dart'; // ✅ ADDED: Import MessageBubble
import '../utils/message_stream_handler.dart';
import 'dart:async';

class MiniModeScreen extends StatefulWidget {
  final bool isDarkMode;
  final List<String> availableModels;
  final VoidCallback onExitMiniMode;

  const MiniModeScreen({
    super.key,
    required this.isDarkMode,
    required this.availableModels,
    required this.onExitMiniMode,
  });

  @override
  State<MiniModeScreen> createState() => _MiniModeScreenState();
}

class _MiniModeScreenState extends State<MiniModeScreen> with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final OllamaService _ollamaService = OllamaService();
  final FocusNode _inputFocusNode = FocusNode();

  late final MessageStreamHandler _messageStreamHandler;

  bool _isExpanded = false;

  // Suggested prompts
  List<String> _suggestedPrompts = [
    'Explain this concept',
    'Write code for...',
    'Summarize',
    'Debug this',
  ];

  late AnimationController _expandController;
  late Animation<double> _expandAnimation;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _messageStreamHandler = MessageStreamHandler(_ollamaService);
    _setupAnimations();
    _scrollToBottom();
  }

  void _setupAnimations() {
    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeInOut,
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    _expandController.dispose();
    _pulseController.dispose();
    _messageStreamHandler.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    if (!mounted) return;

    final provider = context.read<ChatProvider>();
    final text = _controller.text.trim();

    if (text.isEmpty || provider.isGenerating || provider.isSending) {
      debugPrint('⚠️ Mini mode: Message blocked');
      return;
    }

    debugPrint('📤 Mini mode: Sending message');

    final userMessage = ChatMessage(
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
    );

    provider.addMessage(userMessage);
    _controller.clear();

    provider.startGenerating();
    provider.setIsSending(true);

    _scrollToBottom();

    final generatingForConversationIndex = provider.selectedConversationIndex;

    try {
      final conversationHistory = StringBuffer();
      final messages = provider.messages;

      for (int i = 0; i < messages.length; i++) {
        final msg = messages[i];
        conversationHistory.write(
            msg.isUser ? 'User: ${msg.text}\n\n' : 'Assistant: ${msg.text}\n\n'
        );
      }

      final fullPrompt = conversationHistory.isEmpty
          ? text
          : '${conversationHistory.toString()}User: $text';

      final stream = _ollamaService.generateResponse(
        model: provider.selectedModel,
        prompt: fullPrompt,
        systemPrompt: provider.useSystemPrompt ? provider.systemPrompt : null,
        temperature: provider.temperature,
        maxTokens: provider.maxTokens,
      );

      await _messageStreamHandler.handleStream(
        stream: stream,
        provider: provider,
        generatingForIndex: generatingForConversationIndex,
        onUpdate: () {
          if (mounted && provider.selectedConversationIndex == generatingForConversationIndex) {
            setState(() {});
            _scrollToBottom();
          }
        },
        onStopGenerationChanged: (isSending) {
          if (mounted) {
            provider.setIsSending(isSending);
          }
        },
      );

      debugPrint('✅ Mini mode: Message complete');

    } catch (e) {
      debugPrint('❌ Mini mode error: $e');
      if (mounted) {
        provider.stopGenerating();
        provider.setIsSending(false);
      }
    } finally {
      if (mounted) {
        provider.setIsSending(false);
        if (provider.isGenerating) {
          provider.stopGenerating();
        }
      }
    }
  }

  void _stopGeneration() {
    debugPrint('🛑 Mini mode: Stop button pressed');

    if (!mounted) return;
    final provider = context.read<ChatProvider>();

    _messageStreamHandler.cancelActiveStream();
    _ollamaService.cancelGeneration();
    provider.stopGenerating();
    provider.setIsSending(false);

    debugPrint('✅ Mini mode: Generation stopped');
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && mounted) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
    if (_isExpanded) {
      _expandController.forward();
    } else {
      _expandController.reverse();
    }
  }

  void _copyLastResponse() {
    final provider = context.read<ChatProvider>();
    if (provider.messages.isEmpty) return;

    final lastAssistant = provider.messages.lastWhere(
          (m) => !m.isUser,
      orElse: () => ChatMessage(text: '', isUser: false, timestamp: DateTime.now()),
    );

    if (lastAssistant.text.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: lastAssistant.text));
      _showSnackBar('Copied to clipboard', Icons.check_circle);
    }
  }

  void _clearChat() {
    final provider = context.read<ChatProvider>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Chat'),
        content: const Text('Are you sure you want to clear all messages?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              provider.clearMessages();
              Navigator.pop(context);
              _showSnackBar('Chat cleared', Icons.delete_sweep);
            },
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _addNewPrompt() {
    final TextEditingController promptController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Quick Prompt', style: TextStyle(fontSize: 16)),
        content: TextField(
          controller: promptController,
          decoration: const InputDecoration(
            hintText: 'Enter prompt text...',
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (promptController.text.trim().isNotEmpty) {
                setState(() {
                  _suggestedPrompts.add(promptController.text.trim());
                });
                Navigator.pop(context);
                _showSnackBar('Prompt added', Icons.check_circle);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _removePrompt(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Prompt', style: TextStyle(fontSize: 16)),
        content: Text('Remove "${_suggestedPrompts[index]}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _suggestedPrompts.removeAt(index);
              });
              Navigator.pop(context);
              _showSnackBar('Prompt removed', Icons.delete);
            },
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _usePrompt(String prompt) {
    _controller.text = prompt;
    _inputFocusNode.requestFocus();
  }

  void _showSnackBar(String message, IconData icon) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  // ✅ ADDED: Regenerate function for MessageBubble
  void _regenerateLastResponse() async {
    if (!mounted) return;
    final provider = context.read<ChatProvider>();

    if (provider.messages.length < 2 || provider.isGenerating) return;

    // Remove last assistant message
    provider.removeLastMessage();

    // Get the last user message and resend it
    final lastUserMessage = provider.messages.last.text;
    await _sendMessage();
  }

  // ✅ ADDED: Edit message function for MessageBubble
  void _editMessage(int index) {
    if (!mounted) return;
    final provider = context.read<ChatProvider>();

    if (index < 0 || index >= provider.messages.length) return;

    final message = provider.messages[index];
    _controller.text = message.text;

    // Remove messages from this point onwards
    provider.removeMessagesFromIndex(index);
  }

  Color get _backgroundColor => widget.isDarkMode
      ? const Color(0xFF1E1E1E)
      : const Color(0xFFF5F5F5);

  Color get _surfaceColor => widget.isDarkMode
      ? const Color(0xFF2A2A2A)
      : Colors.white;

  Color get _accentColor => widget.isDarkMode
      ? Colors.blue[400]!
      : Colors.blue[600]!;

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, provider, child) {
        return Scaffold(
          backgroundColor: _backgroundColor,
          body: Column(
            children: [
              _buildCompactHeader(provider),
              if (_isExpanded) _buildExpandedControls(provider),
              Expanded(child: _buildMessageList(provider)),
              _buildInputArea(provider),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCompactHeader(ChatProvider provider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: _surfaceColor,
        border: Border(
          bottom: BorderSide(
            color: widget.isDarkMode ? Colors.grey[800]! : Colors.grey[300]!,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: MouseRegion(
              cursor: SystemMouseCursors.move,
              child: Row(
                children: [
                  Icon(Icons.drag_indicator, size: 18, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Mini Mode',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: widget.isDarkMode ? Colors.white : Colors.black87,
                          ),
                        ),
                        Text(
                          provider.selectedModel ?? "",
                          style: TextStyle(fontSize: 9, color: Colors.grey[600]),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          _buildHeaderButton(
            icon: _isExpanded ? Icons.expand_less : Icons.expand_more,
            onPressed: _toggleExpanded,
            tooltip: _isExpanded ? 'Hide controls' : 'Show controls',
          ),
          _buildHeaderButton(
            icon: Icons.copy,
            onPressed: _copyLastResponse,
            tooltip: 'Copy last response',
          ),
          _buildHeaderButton(
            icon: Icons.delete_outline,
            onPressed: _clearChat,
            tooltip: 'Clear chat',
          ),
          _buildHeaderButton(
            icon: Icons.fullscreen,
            onPressed: widget.onExitMiniMode,
            tooltip: 'Exit mini mode',
            color: _accentColor,
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderButton({
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
    Color? color,
  }) {
    return IconButton(
      icon: Icon(icon, size: 18),
      onPressed: onPressed,
      tooltip: tooltip,
      color: color,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      splashRadius: 16,
    );
  }

  Widget _buildExpandedControls(ChatProvider provider) {
    return SizeTransition(
      sizeFactor: _expandAnimation,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _surfaceColor,
          border: Border(
            bottom: BorderSide(
              color: widget.isDarkMode ? Colors.grey[800]! : Colors.grey[300]!,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Model selector
            Row(
              children: [
                Icon(Icons.psychology, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<String>(
                    value: provider.selectedModel,
                    isExpanded: true,
                    isDense: true,
                    underline: Container(),
                    style: TextStyle(
                      fontSize: 12,
                      color: widget.isDarkMode ? Colors.white : Colors.black87,
                    ),
                    items: widget.availableModels.map((model) {
                      return DropdownMenuItem(
                        value: model,
                        child: Text(model, overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null && !provider.isGenerating) {
                        provider.setSelectedModel(value);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Quick prompts section
            Row(
              children: [
                Icon(Icons.bolt, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Text(
                  'Quick Prompts',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600],
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: _addNewPrompt,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _accentColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: _accentColor.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, size: 12, color: _accentColor),
                        const SizedBox(width: 2),
                        Text(
                          'Add',
                          style: TextStyle(
                            fontSize: 10,
                            color: _accentColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Prompt chips
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _suggestedPrompts.asMap().entries.map((entry) {
                final index = entry.key;
                final prompt = entry.value;
                return _buildPromptChip(prompt, index);
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPromptChip(String prompt, int index) {
    return InkWell(
      onTap: () => _usePrompt(prompt),
      onLongPress: () => _removePrompt(index),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: widget.isDarkMode
              ? Colors.blue[900]!.withOpacity(0.3)
              : Colors.blue[50],
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: widget.isDarkMode
                ? Colors.blue[700]!.withOpacity(0.5)
                : Colors.blue[200]!,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.flash_on,
              size: 12,
              color: widget.isDarkMode ? Colors.blue[300] : Colors.blue[700],
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                prompt,
                style: TextStyle(
                  fontSize: 11,
                  color: widget.isDarkMode ? Colors.blue[200] : Colors.blue[800],
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ MODIFIED: Now uses MessageBubble widget with centered compact layout
  Widget _buildMessageList(ChatProvider provider) {
    if (provider.messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _pulseAnimation,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _accentColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.chat_bubble_outline, size: 36, color: _accentColor),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Start chatting',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Compact mode with full markdown support',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
      itemCount: provider.messages.length + (provider.isGenerating ? 1 : 0),
      itemBuilder: (context, index) {
        if (provider.isGenerating && index == provider.messages.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: TypingIndicator(
              isDarkMode: widget.isDarkMode,
              modelName: provider.selectedModel,
            ),
          );
        }

        final message = provider.messages[index];
        final isLastMessage = index == provider.messages.length - 1;

        // ✅ Wrap MessageBubble in custom compact layout
        return _buildCompactMessageWrapper(
          message: message,
          index: index,
          isLastMessage: isLastMessage,
          provider: provider,
        );
      },
    );
  }

  // ✅ ADDED: Compact wrapper that centers MessageBubble with avatar
  Widget _buildCompactMessageWrapper({
    required ChatMessage message,
    required int index,
    required bool isLastMessage,
    required ChatProvider provider,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: message.isUser ? _accentColor : Colors.grey[700],
              shape: BoxShape.circle,
            ),
            child: Icon(
              message.isUser ? Icons.person : Icons.smart_toy,
              size: 14,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 8),

          // Message content with MessageBubble
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row with name and timestamp
                Row(
                  children: [
                    Text(
                      message.isUser ? 'You' : (provider.selectedModel?.split(':').first ?? ''),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: widget.isDarkMode ? Colors.grey[300] : Colors.grey[800],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _formatTimestamp(message.timestamp),
                      style: TextStyle(fontSize: 9, color: Colors.grey[600]),
                    ),
                    if (!message.isUser &&
                        message.thinkingText != null &&
                        message.thinkingText!.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.psychology,
                        size: 12,
                        color: Colors.orange[400],
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),

                // Use MessageBubble for markdown rendering
                Transform.scale(
                  scale: 0.95, // Slightly smaller for compact mode
                  alignment: Alignment.topLeft,
                  child: MessageBubble(
                    message: message,
                    isDarkMode: widget.isDarkMode,
                    onEdit: message.isUser ? () => _editMessage(index) : null,
                    onRegenerate: !message.isUser &&
                        isLastMessage &&
                        !provider.isGenerating
                        ? _regenerateLastResponse
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) return 'now';
    if (difference.inHours < 1) return '${difference.inMinutes}m';
    if (difference.inDays < 1) return '${difference.inHours}h';
    return '${difference.inDays}d';
  }

  Widget _buildInputArea(ChatProvider provider) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _surfaceColor,
        border: Border(
          top: BorderSide(
            color: widget.isDarkMode ? Colors.grey[800]! : Colors.grey[300]!,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 100),
              child: TextField(
                controller: _controller,
                focusNode: _inputFocusNode,
                decoration: InputDecoration(
                  hintText: 'Quick message...',
                  hintStyle: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: widget.isDarkMode ? Colors.grey[700]! : Colors.grey[300]!,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: widget.isDarkMode ? Colors.grey[700]! : Colors.grey[300]!,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: _accentColor, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 12),
                maxLines: null,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => provider.isGenerating ? null : _sendMessage(),
                enabled: !provider.isGenerating,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            decoration: BoxDecoration(
              color: provider.isGenerating ? Colors.red : _accentColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              icon: Icon(provider.isGenerating ? Icons.stop : Icons.send, size: 18),
              onPressed: provider.isGenerating ? _stopGeneration : _sendMessage,
              color: Colors.white,
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              tooltip: provider.isGenerating ? 'Stop' : 'Send',
            ),
          ),
        ],
      ),
    );
  }
}