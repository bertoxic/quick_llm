import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/chat_message.dart';
import '../models/conversation.dart';
import '../provider/ChatProvider.dart';
import '../services/ollama_service.dart';
import '../widgets/typing_indicaator.dart';
import '../widgets/message_bubble.dart';
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

class _MiniModeScreenState extends State<MiniModeScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final OllamaService _ollamaService = OllamaService();
  final FocusNode _inputFocusNode = FocusNode();

  late final MessageStreamHandler _messageStreamHandler;

  @override
  void initState() {
    super.initState();
    _messageStreamHandler = MessageStreamHandler(_ollamaService);
    _scrollToBottom();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    _messageStreamHandler.dispose();
    super.dispose();
  }

  // Ensure we have a valid conversation to work with
  void _ensureConversationExists(ChatProvider provider) {
    // If no conversation is selected, create one
    if (provider.selectedConversationIndex == null ||
        provider.selectedConversationIndex! >= provider.conversations.length) {
      final newConversation = Conversation(
        title: 'New Chat',
        messages: [],
        timestamp: DateTime.now(),
      );
      provider.addConversation(newConversation);
      provider.selectConversation(0);
      provider.setMessages([]);
      debugPrint('📝 Created new conversation in mini mode');
    }
  }

  // Sync current messages to the selected conversation
  void _syncMessagesToConversation(ChatProvider provider) {
    if (provider.selectedConversationIndex == null) return;

    final index = provider.selectedConversationIndex!;
    if (index >= provider.conversations.length) return;

    final currentConv = provider.conversations[index];
    final updatedConv = Conversation(
      title: currentConv.title,
      messages: List.from(provider.messages),
      timestamp: currentConv.timestamp,
    );

    provider.updateConversation(index, updatedConv);
    debugPrint('💾 Synced ${provider.messages.length} messages to conversation $index');
  }

  Future<void> _sendMessage() async {
    if (!mounted) return;

    final provider = context.read<ChatProvider>();
    final text = _controller.text.trim();

    if (text.isEmpty || provider.isGenerating || provider.isSending) {
      debugPrint('⚠️ Mini mode: Message blocked');
      return;
    }

    // Ensure we have a conversation to work with
    _ensureConversationExists(provider);

    debugPrint('📤 Mini mode: Sending message');

    final userMessage = ChatMessage(
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
    );

    provider.addMessage(userMessage);
    _controller.clear();

    // Create empty assistant message placeholder for streaming
    final assistantMessage = ChatMessage(
      text: '',
      isUser: false,
      timestamp: DateTime.now(),
      modelName: provider.selectedModel,
    );
    provider.addMessage(assistantMessage);

    // Sync both messages immediately
    _syncMessagesToConversation(provider);

    provider.startGenerating();
    provider.setIsSending(true);

    _scrollToBottom();

    final generatingForConversationIndex = provider.selectedConversationIndex;

    try {
      // Build conversation history for context
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

      // Final sync after generation completes
      if (mounted) {
        _syncMessagesToConversation(provider);
      }

    } catch (e) {
      debugPrint('❌ Mini mode error: $e');
      if (mounted) {
        provider.stopGenerating();
        provider.setIsSending(false);
        // Sync even on error to preserve partial responses
        _syncMessagesToConversation(provider);
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

    // Sync messages after stopping (to save partial response)
    _syncMessagesToConversation(provider);

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
              // Sync the cleared state
              _syncMessagesToConversation(provider);
              Navigator.pop(context);
              _showSnackBar('Chat cleared', Icons.delete_sweep);
            },
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // Regenerate the last assistant response
  void _regenerateLastResponse() async {
    if (!mounted) return;
    final provider = context.read<ChatProvider>();

    if (provider.messages.length < 2 || provider.isGenerating) return;

    provider.removeLastMessage();
    _syncMessagesToConversation(provider);

    // Get the last user message text before sending
    final lastUserMessage = provider.messages.last.text;
    _controller.text = lastUserMessage;

    await _sendMessage();
  }

  // Edit a message and resend
  void _editMessage(int index) {
    if (!mounted) return;
    final provider = context.read<ChatProvider>();

    if (index < 0 || index >= provider.messages.length) return;

    final message = provider.messages[index];
    _controller.text = message.text;

    provider.removeMessagesFromIndex(index);
    _syncMessagesToConversation(provider);
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
        // Ensure we have a conversation when building
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _ensureConversationExists(provider);
        });

        return Scaffold(
          backgroundColor: _backgroundColor,
          body: Column(
            children: [
              _buildHeader(provider),
              Expanded(child: _buildMessageList(provider)),
              _buildInputArea(provider),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(ChatProvider provider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
          // Model selector
          Icon(Icons.psychology, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButton<String>(
              value: provider.selectedModel,
              isExpanded: true,
              isDense: true,
              underline: Container(),
              style: TextStyle(
                fontSize: 13,
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
          const SizedBox(width: 8),

          // Action buttons
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

  Widget _buildMessageList(ChatProvider provider) {
    if (provider.messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _accentColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.chat_bubble_outline, size: 36, color: _accentColor),
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
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
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

        return _buildCompactMessageWrapper(
          message: message,
          index: index,
          isLastMessage: isLastMessage,
          provider: provider,
        );
      },
    );
  }

  Widget _buildCompactMessageWrapper({
    required ChatMessage message,
    required int index,
    required bool isLastMessage,
    required ChatProvider provider,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header row with avatar, name, and timestamp
          Row(
            children: [
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
              Text(
                message.isUser ? 'You' : (provider.selectedModel?.split(':').first ?? 'Assistant'),
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
          const SizedBox(height: 6),

          // Message bubble takes full width
          MessageBubble(
            message: message,
            isDarkMode: widget.isDarkMode,
            useFullWidth: true, // Enable full-width mode for mini mode
            onEdit: message.isUser ? () => _editMessage(index) : null,
            onRegenerate: !message.isUser &&
                isLastMessage &&
                !provider.isGenerating
                ? _regenerateLastResponse
                : null,
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
                  hintText: 'Type a message...',
                  hintStyle: TextStyle(fontSize: 13, color: Colors.grey[500]),
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
                style: const TextStyle(fontSize: 13),
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