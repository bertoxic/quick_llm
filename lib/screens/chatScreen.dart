import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:async';
import 'dart:io';
import '../../dialogs/settings_dialog.dart';
import '../../models/chat_message.dart';
import '../../models/conversation.dart';
import '../../provider/ChatProvider.dart';
import '../../services/ollama_service.dart';
import '../../services/storage_service.dart';
import '../../widgets/chat_header.dart';
import '../../widgets/message_bubble.dart';
import '../../widgets/sidebar.dart';
import '../../widgets/typing_indicaator.dart';
import '../../utils/conversation_manager.dart';
import '../../utils/message_stream_handler.dart';
import '../provider/SplitScreenManager_provider.dart';
import '../utils/helpers.dart';
import 'mini_mode_screen.dart';

class ChatScreen extends StatefulWidget {
  final VoidCallback toggleTheme;
  final bool isDarkMode;

  const ChatScreen({
    super.key,
    required this.toggleTheme,
    required this.isDarkMode,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WindowListener {
  // Controllers
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _rightController = TextEditingController();
  final TextEditingController _systemPromptController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ScrollController _rightScrollController = ScrollController();

  // Services
  final OllamaService _ollamaService = OllamaService();
  final StorageService _storageService = StorageService();
  late final SplitScreenManager _splitScreenManager;
  late final ConversationManager _conversationManager;
  late final MessageStreamHandler _messageStreamHandler;
  late final FileAttachmentHelper _fileAttachmentHelper;
  late final ScrollControllerHelper _scrollHelper;
  late final ScrollControllerHelper _rightScrollHelper;

  // State
  bool _isAlwaysOnTop = false;
  bool _isMiniMode = false;
  List<String> _availableModels = [];
  List<File> _attachedFiles = [];
  List<File> _rightAttachedFiles = [];
  bool _copyFileAttachments = true;
  bool _shouldStopGeneration = false;
  StreamSubscription? _currentStreamSubscription;

  @override
  void initState() {
    super.initState();
    _splitScreenManager = SplitScreenManager();
    _conversationManager = ConversationManager(_storageService);
    _messageStreamHandler = MessageStreamHandler(_ollamaService);
    _fileAttachmentHelper = FileAttachmentHelper(_storageService);
    _scrollHelper = ScrollControllerHelper(_scrollController);
    _rightScrollHelper = ScrollControllerHelper(_rightScrollController);

    windowManager.addListener(this);
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _loadConversations();
    await _loadPreferences();
    await _fetchAvailableModels();
    _startNewConversation();
    _setupScrollListener();
  }

  @override
  void dispose() {
    _currentStreamSubscription?.cancel();
    windowManager.removeListener(this);
    _controller.dispose();
    _rightController.dispose();
    _systemPromptController.dispose();
    _scrollHelper.dispose();
    _rightScrollHelper.dispose();
    _messageStreamHandler.dispose();
    super.dispose();
  }

  void _setupScrollListener() {
    _scrollHelper.setupListener(
      onUserScrolledUp: () {
        if (mounted) setState(() {});
      },
      isGenerating: () => context.read<ChatProvider>().isGenerating,
    );
    _rightScrollHelper.setupListener(
      onUserScrolledUp: () {
        if (mounted) setState(() {});
      },
      isGenerating: () => context.read<ChatProvider>().isGenerating,
    );
  }

  // === MESSAGE SENDING ===
  Future<void> _sendMessage({
    bool regenerate = false,
    String? message,
    bool isRightPane = false,
  }) async {
    if (!mounted) return;

    final provider = context.read<ChatProvider>();
    final controller = isRightPane ? _rightController : _controller;
    final messageText = message ?? controller.text.trim();
    final attachedFiles = isRightPane ? _rightAttachedFiles : _attachedFiles;
    final scrollHelper = isRightPane ? _rightScrollHelper : _scrollHelper;

    if (!provider.hasValidModel) {
      _showSnackBar('⚠️ No model selected. Please select a model first.');
      return;
    }

    if (messageText.isEmpty || provider.isGenerating || provider.isSending) {
      debugPrint('⚠️ Message send blocked');
      return;
    }

    final userMessage = ChatMessage(
      text: messageText,
      isUser: true,
      timestamp: DateTime.now(),
      attachedFiles: attachedFiles.isNotEmpty
          ? attachedFiles.map((f) => f.path).toList()
          : null,
    );

    // Add user message to the correct pane
    if (!regenerate) {
      if (isRightPane) {
        // Add to right pane messages
        final updatedMessages = List<ChatMessage>.from(_splitScreenManager.rightPaneMessages)
          ..add(userMessage);
        _splitScreenManager.setRightPaneMessages(updatedMessages);
      } else {
        // Add to left pane messages
        provider.addMessage(userMessage);
      }
    }

    // Start generation
    provider.startGenerating();

    // Add empty assistant message to the correct pane
    final assistantMessage = ChatMessage(
      text: '',
      isUser: false,
      timestamp: DateTime.now(),
      modelName: provider.selectedModel,
    );

    if (isRightPane) {
      final updatedMessages = List<ChatMessage>.from(_splitScreenManager.rightPaneMessages)
        ..add(assistantMessage);
      _splitScreenManager.setRightPaneMessages(updatedMessages);
    } else {
      provider.addMessage(assistantMessage);
    }

    setState(() {
      _shouldStopGeneration = false;
    });
    scrollHelper.resetAutoScroll();

    if (!regenerate) {
      controller.clear();
      attachedFiles.clear();
    }
    scrollHelper.scrollToBottom();

    // Determine which conversation to update
    int? conversationIndex;
    if (isRightPane) {
      conversationIndex = _splitScreenManager.rightConversationIndex;
      // If right pane has a conversation, we'll update it after generation completes
    } else {
      // Create/update conversation for left pane
      _conversationManager.createOrUpdate(userMessage, provider);
      conversationIndex = provider.selectedConversationIndex;
    }

    try {
      await _generateResponse(
        provider,
        messageText,
        userMessage,
        conversationIndex,
        scrollHelper,
        isRightPane: isRightPane,
      );
    } catch (e) {
      debugPrint('❌ Error during streaming: $e');
      if (mounted) {
        provider.stopGenerating();
        provider.setIsSending(false);
      }
    } finally {
      if (mounted) {
        provider.setIsSending(false);
      }
    }
  }

  Future<void> _generateResponse(
      ChatProvider provider,
      String messageText,
      ChatMessage userMessage,
      int? generatingForConversationIndex,
      ScrollControllerHelper scrollHelper, {
        bool isRightPane = false,
      }) async {
    // Get messages from the correct pane
    final allMessages = isRightPane
        ? _splitScreenManager.rightPaneMessages
        : provider.messages;
    final messagesForContext = ChatMessageBuilder.extractContextMessages(allMessages);

    debugPrint('📚 Total messages in conversation: ${allMessages.length}');
    debugPrint('📚 Messages for context: ${messagesForContext.length}');
    debugPrint('📍 Pane: ${isRightPane ? "RIGHT" : "LEFT"}');

    // Separate attached files
    final fileTypes = FileAttachmentHelper.separateFileTypes(userMessage.attachedFiles);

    // Build messages array for Ollama
    final messagesArray = ChatMessageBuilder.buildMessagesArray(
      contextMessages: messagesForContext,
      currentMessageText: messageText,
    );

    // Generate response
    final stream = _ollamaService.generateResponse(
      model: provider.selectedModel,
      prompt: messageText,
      messagesArray: messagesArray,
      systemPrompt: provider.useSystemPrompt ? provider.systemPrompt : null,
      temperature: provider.temperature,
      maxTokens: provider.maxTokens,
      images: fileTypes.images,
      documents: fileTypes.documents,
    );

    await _messageStreamHandler.handleStream(
      stream: stream,
      provider: provider,
      generatingForIndex: generatingForConversationIndex,
      isRightPane: isRightPane, // PASS THE PARAMETER
      onUpdate: () {
        if (mounted) {
          // Update the correct pane
          if (isRightPane) {
            // For right pane, only update the last message (the streaming response)
            if (generatingForConversationIndex != null &&
                generatingForConversationIndex < provider.conversations.length) {
              final conv = provider.conversations[generatingForConversationIndex];
              if (conv.messages.isNotEmpty) {
                // Get the latest assistant message from conversation
                final latestMessage = conv.messages.last;

                // Update only the last message in right pane
                final currentRightMessages = List<ChatMessage>.from(_splitScreenManager.rightPaneMessages);
                if (currentRightMessages.isNotEmpty && !currentRightMessages.last.isUser) {
                  currentRightMessages[currentRightMessages.length - 1] = ChatMessage(
                    text: latestMessage.text,
                    isUser: false,
                    timestamp: latestMessage.timestamp,
                    thinkingText: latestMessage.thinkingText,
                    isThinking: latestMessage.isThinking,
                    modelName: latestMessage.modelName,
                    attachedFiles: latestMessage.attachedFiles,
                  );
                  _splitScreenManager.setRightPaneMessages(currentRightMessages);
                }
              }
            }
          }
          setState(() {});
          if (scrollHelper.isAutoScrollEnabled) {
            scrollHelper.scrollToBottom();
          }
        }
      },
      onStopGenerationChanged: (isSending) {
        if (mounted) {
          provider.setIsSending(isSending);
        }
      },
    );

    // Save conversation
    if (generatingForConversationIndex != null && mounted) {
      _conversationManager.saveAtIndex(provider, generatingForConversationIndex);
      debugPrint('✅ Message stream finished\n');
    }
  }

  void _stopGeneration() {
    debugPrint('🛑 Stop button pressed');
    if (!mounted) return;

    final provider = context.read<ChatProvider>();
    if (provider.generatingConversationIndex != null) {
      _conversationManager.saveAtIndex(provider, provider.generatingConversationIndex!);
    }

    _messageStreamHandler.cancelActiveStream();
    _currentStreamSubscription?.cancel();
    _currentStreamSubscription = null;
    _ollamaService.cancelGeneration();
    provider.stopGenerating();
    provider.setIsSending(false);

    setState(() {
      _shouldStopGeneration = true;
    });
  }

  // === FILE HANDLING ===
  Future<void> _pickFiles({bool isRightPane = false}) async {
    final files = await _fileAttachmentHelper.pickFiles(
      context: context,
      copyFileAttachments: _copyFileAttachments,
    );

    if (files.isNotEmpty && mounted) {
      setState(() {
        if (isRightPane) {
          _rightAttachedFiles.addAll(files);
        } else {
          _attachedFiles.addAll(files);
        }
      });
    }
  }

  void _removeAttachedFile(int index, {bool isRightPane = false}) {
    final attachedFiles = isRightPane ? _rightAttachedFiles : _attachedFiles;
    if (index >= 0 && index < attachedFiles.length) {
      setState(() {
        attachedFiles.removeAt(index);
      });
    }
  }

  Future<void> _checkMissingAttachments() async {
    if (!mounted) return;
    final provider = context.read<ChatProvider>();
    final allFiles = <String>[];

    for (var message in provider.messages) {
      if (message.attachedFiles != null) {
        allFiles.addAll(message.attachedFiles!);
      }
    }

    await _fileAttachmentHelper.checkMissingAttachments(
      context: context,
      allFiles: allFiles,
    );
  }

  // === CONVERSATION MANAGEMENT ===
  void _startNewConversation() {
    if (!mounted) return;
    final provider = context.read<ChatProvider>();
    provider.clearMessages();
    provider.selectConversation(null);
    provider.stopGenerating();

    setState(() {
      _shouldStopGeneration = false;
      provider.setIsSending(false);
      _attachedFiles.clear();
      _rightAttachedFiles.clear();
    });
  }

  void _loadConversation(int index, {bool isRightPane = false}) {
    if (!mounted) return;
    final provider = context.read<ChatProvider>();
    if (index < 0 || index >= provider.conversations.length) return;

    if (provider.isGenerating && !isRightPane) {
      debugPrint('⚠️ Cannot switch conversations while generating');
      _showSnackBar('Please wait for the current response to finish');
      return;
    }

    if (isRightPane) {
      // Load messages for right pane into split screen manager
      _splitScreenManager.setRightConversation(index);
      final messages = provider.conversations[index].messages.map((m) => ChatMessage(
        text: m.text,
        isUser: m.isUser,
        timestamp: m.timestamp,
        thinkingText: m.thinkingText,
        isThinking: m.isThinking,
        modelName: m.modelName,
        attachedFiles: m.attachedFiles,
      )).toList();
      _splitScreenManager.setRightPaneMessages(messages);
    } else {
      // Load messages for left pane into provider
      provider.selectConversation(index);
      final messages = provider.conversations[index].messages.map((m) => ChatMessage(
        text: m.text,
        isUser: m.isUser,
        timestamp: m.timestamp,
        thinkingText: m.thinkingText,
        isThinking: m.isThinking,
        modelName: m.modelName,
        attachedFiles: m.attachedFiles,
      )).toList();
      provider.setMessages(messages);
    }

    _checkMissingAttachments();
    if (isRightPane) {
      _rightScrollHelper.scrollToBottom();
    } else {
      _scrollHelper.scrollToBottom();
    }
  }

  Future<void> _loadConversations() async {
    final conversations = await _conversationManager.load();
    if (mounted) {
      context.read<ChatProvider>().setConversations(conversations);
    }
  }

  void _deleteConversation(int index) {
    if (!mounted) return;
    final provider = context.read<ChatProvider>();
    if (index < 0 || index >= provider.conversations.length) return;

    provider.deleteConversation(index);
    _conversationManager.save(provider);
  }

  // === MESSAGE ACTIONS ===
  void _regenerateLastResponse({bool isRightPane = false}) async {
    if (!mounted) return;
    final provider = context.read<ChatProvider>();

    final messages = isRightPane
        ? _splitScreenManager.rightPaneMessages
        : provider.messages;

    if (messages.length < 2 || provider.isGenerating) return;

    // Remove last assistant message
    if (isRightPane) {
      final updatedMessages = List<ChatMessage>.from(messages)..removeLast();
      _splitScreenManager.setRightPaneMessages(updatedMessages);

      // Also remove from conversation if it exists
      final convIndex = _splitScreenManager.rightConversationIndex;
      if (convIndex != null && convIndex < provider.conversations.length) {
        provider.conversations[convIndex].messages.removeLast();
      }
    } else {
      provider.removeLastMessage();
    }

    final lastUserMessage = messages[messages.length - 2].text;
    _sendMessage(regenerate: true, message: lastUserMessage, isRightPane: isRightPane);
  }

// 9. Update _editMessage to handle right pane
  void _editMessage(int index, {bool isRightPane = false}) {
    if (!mounted) return;
    final provider = context.read<ChatProvider>();

    final messages = isRightPane
        ? _splitScreenManager.rightPaneMessages
        : provider.messages;

    if (index < 0 || index >= messages.length) return;

    final message = messages[index];
    final controller = isRightPane ? _rightController : _controller;
    controller.text = message.text;

    // Remove messages from index onwards
    if (isRightPane) {
      final updatedMessages = messages.sublist(0, index);
      _splitScreenManager.setRightPaneMessages(updatedMessages);

      // Also update conversation
      final convIndex = _splitScreenManager.rightConversationIndex;
      if (convIndex != null && convIndex < provider.conversations.length) {
        provider.conversations[convIndex].messages =
            provider.conversations[convIndex].messages.sublist(0, index);
      }
    } else {
      provider.removeMessagesFromIndex(index);
    }
  }

  // === SETTINGS & PREFERENCES ===
  Future<void> _loadPreferences() async {
    final prefs = await _storageService.loadPreferences();
    if (mounted) {
      final provider = context.read<ChatProvider>();
      provider.updateSettings(
        isSidebarVisible: prefs['sidebarVisible'] ?? true,
        systemPrompt: prefs['systemPrompt'] ?? '',
        temperature: prefs['temperature'] ?? 0.7,
        maxTokens: prefs['maxTokens'] ?? 2048,
        useSystemPrompt: prefs['useSystemPrompt'] ?? false,
      );
      _systemPromptController.text = provider.systemPrompt;

      setState(() {
        _copyFileAttachments = prefs['copyFileAttachments'] ?? true;
      });
    }
  }

  Future<void> _savePreferences() async {
    if (!mounted) return;
    final provider = context.read<ChatProvider>();
    await _storageService.savePreferences({
      'sidebarVisible': provider.isSidebarVisible,
      'systemPrompt': provider.systemPrompt,
      'temperature': provider.temperature,
      'maxTokens': provider.maxTokens,
      'useSystemPrompt': provider.useSystemPrompt,
      'monitorClipboard': false,
      'copyFileAttachments': _copyFileAttachments,
    });
  }

  void _showSettingsDialog() {
    if (!mounted) return;
    final provider = context.read<ChatProvider>();
    showDialog(
      context: context,
      builder: (context) => SettingsDialog(
        systemPromptController: _systemPromptController,
        useSystemPrompt: provider.useSystemPrompt,
        temperature: provider.temperature,
        maxTokens: provider.maxTokens,
        onUseSystemPromptChanged: (value) => provider.setUseSystemPrompt(value),
        onTemperatureChanged: (value) => provider.setTemperature(value),
        onMaxTokensChanged: (value) => provider.setMaxTokens(value),
        onSave: () {
          provider.setSystemPrompt(_systemPromptController.text);
          _savePreferences();
        },
        isDarkMode: widget.isDarkMode,
      ),
    );
  }

  // === MODELS ===
  Future<void> _fetchAvailableModels() async {
    try {
      final models = await _ollamaService.fetchAvailableModels();
      if (models.isNotEmpty && mounted) {
        final provider = context.read<ChatProvider>();
        setState(() {
          _availableModels = models;
        });

        if (provider.selectedModel == null || !models.contains(provider.selectedModel)) {
          provider.setSelectedModel(models.first);
        }
      } else if (models.isEmpty && mounted) {
        final provider = context.read<ChatProvider>();
        setState(() {
          _availableModels = [];
        });
        provider.setSelectedModel(null);
        _showSnackBar('⚠️ No models found. Please install Ollama models.', duration: 5);
      }
    } catch (e) {
      debugPrint('Error fetching models: $e');
      if (mounted) {
        final provider = context.read<ChatProvider>();
        setState(() {
          _availableModels = [];
        });
        provider.setSelectedModel(null);
        _showSnackBar('⚠️ Cannot connect to Ollama: $e', duration: 5);
      }
    }
  }

  // === SPLIT SCREEN MANAGEMENT ===
  void _enableSplitMode(int leftIndex, int rightIndex) {
    if (!mounted) return;
    setState(() {
      _splitScreenManager.enableSplitMode(leftIndex, rightIndex);
    });
    _loadConversation(leftIndex, isRightPane: false);
    _loadConversation(rightIndex, isRightPane: true);

    debugPrint('✅ Split mode enabled: Left: $leftIndex, Right: $rightIndex');
  }

// 5. Update _disableSplitMode to clear right pane state
  void _disableSplitMode() {
    if (!mounted) return;
    setState(() {
      _splitScreenManager.disableSplitMode();
      _rightAttachedFiles.clear();
    });

    debugPrint('❌ Split mode disabled');
  }

  void _swapPanes() {
    if (!mounted) return;

    // Get current indices before swap
    final leftIdx = _splitScreenManager.leftConversationIndex;
    final rightIdx = _splitScreenManager.rightConversationIndex;

    // Perform the swap
    setState(() {
      _splitScreenManager.swapPanes();
    });

    // Reload both conversations with their new positions
    if (_splitScreenManager.leftConversationIndex != null) {
      _loadConversation(_splitScreenManager.leftConversationIndex!, isRightPane: false);
    }
    if (_splitScreenManager.rightConversationIndex != null) {
      _loadConversation(_splitScreenManager.rightConversationIndex!, isRightPane: true);
    }

    debugPrint('🔄 Swapped panes: Left: ${_splitScreenManager.leftConversationIndex}, Right: ${_splitScreenManager.rightConversationIndex}');
  }

  // === WINDOW MANAGEMENT ===
  Future<void> _toggleAlwaysOnTop() async {
    try {
      final newValue = !_isAlwaysOnTop;
      await windowManager.setAlwaysOnTop(newValue);
      if (mounted) {
        setState(() {
          _isAlwaysOnTop = newValue;
        });
      }
    } catch (e) {
      debugPrint('Error toggling always on top: $e');
    }
  }

  void _toggleSidebar() {
    if (!mounted) return;
    context.read<ChatProvider>().toggleSidebar();
    _savePreferences();
  }

  Future<void> _toggleMiniMode() async {
    try {
      setState(() {
        _isMiniMode = true;
      });
      await windowManager.setSize(const Size(350, 500));
      await windowManager.setAlwaysOnTop(true);
    } catch (e) {
      debugPrint('Error entering mini mode: $e');
    }
  }

  // === EXPORT ===
  Future<void> _exportConversation(Conversation conv) async {
    try {
      final path = await _conversationManager.exportConversation(conv);
      if (mounted) {
        _showSnackBar('Exported to $path');
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Export failed: $e');
      }
    }
  }

  Future<void> _exportAllConversations() async {
    try {
      final provider = context.read<ChatProvider>();
      final path = await _conversationManager.exportAll(provider.conversations);
      if (mounted) {
        _showSnackBar('Exported all to $path');
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Export failed: $e');
      }
    }
  }

  // === HELPERS ===
  void _showSnackBar(String message, {int duration = 3}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: duration),
      ),
    );
  }

  Widget _buildChatPane({
    required List<ChatMessage> messages,
    required ScrollController scrollController,
    required TextEditingController textController,
    required List<File> attachedFiles,
    required bool isRightPane,
    int? conversationIndex,
  }) {
    final provider = context.read<ChatProvider>();

    return Column(
      children: [
        if (isRightPane)
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: widget.isDarkMode ? Colors.grey[850] : Colors.grey[200],
              border: Border(bottom: BorderSide(color: Colors.grey[700]!)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    conversationIndex != null && conversationIndex < provider.conversations.length
                        ? provider.conversations[conversationIndex].title
                        : 'No conversation',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.swap_horiz),
                  onPressed: _swapPanes,
                  tooltip: 'Swap panes',
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _disableSplitMode,
                  tooltip: 'Exit split mode',
                ),
              ],
            ),
          ),
        Expanded(
          child: messages.isEmpty
              ? const EmptyChatPlaceholder()
              : ListView.builder(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            // FIXED: Show typing indicator in both panes when generating
            itemCount: messages.length + (provider.isGenerating ? 1 : 0),
            itemBuilder: (context, index) {
              // FIXED: Show typing indicator in both panes
              if (provider.isGenerating && index == messages.length) {
                return TypingIndicator(
                  isDarkMode: widget.isDarkMode,
                  modelName: provider.selectedModel,
                );
              }

              final message = messages[index];
              return MessageBubble(
                message: message,
                isDarkMode: widget.isDarkMode,
                onEdit: message.isUser ? () => _editMessage(index, isRightPane: isRightPane) : null,
                onRegenerate: !message.isUser &&
                    index == messages.length - 1 &&
                    !provider.isGenerating
                    ? () => _regenerateLastResponse(isRightPane: isRightPane)
                    : null,
              );
            },
          ),
        ),
        ChatInputArea(
          controller: textController,
          isDarkMode: widget.isDarkMode,
          // FIXED: Disable input in both panes when generating
          isGenerating: provider.isGenerating,
          attachedFiles: attachedFiles,
          onSendMessage: () => _sendMessage(isRightPane: isRightPane),
          onStopGeneration: _stopGeneration,
          onPickFiles: () => _pickFiles(isRightPane: isRightPane),
          onRemoveFile: (index) => _removeAttachedFile(index, isRightPane: isRightPane),
        ),
      ],
    );
  }
  @override
  Widget build(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, provider, child) {
        if (_isMiniMode) {
          return MiniModeScreen(
            isDarkMode: widget.isDarkMode,
            availableModels: _availableModels,
            onExitMiniMode: () async {
              try {
                setState(() {
                  _isMiniMode = false;
                });
                await windowManager.setSize(const Size(1000, 700));
                if (!_isAlwaysOnTop) {
                  await windowManager.setAlwaysOnTop(false);
                }
              } catch (e) {
                debugPrint('Error exiting mini mode: $e');
              }
            },
          );
        }

        return Scaffold(
          body: Row(
            children: [
              if (provider.isSidebarVisible)
                Sidebar(
                  isDarkMode: widget.isDarkMode,
                  conversations: provider.conversations,
                  selectedConversationIndex: provider.selectedConversationIndex,
                  generatingConversationIndex: provider.generatingConversationIndex,
                  onNewChat: _startNewConversation,
                  onLoadConversation: _loadConversation,
                  onDeleteConversation: _deleteConversation,
                  onExportConversation: _exportConversation,
                  onExportAll: _exportAllConversations,
                  onToggleTheme: widget.toggleTheme,
                  onClearAllConversations: () async {
                    final success = await _storageService.clearAllConversations();
                    if (success) {
                      setState(() {
                        provider.conversations.clear();
                      });
                      _showSnackBar('All conversations cleared');
                    }
                  },
                  onEnableSplitMode: _enableSplitMode,
                  isSplitMode: _splitScreenManager.isSplitMode,
                ),
              Expanded(
                child: _splitScreenManager.isSplitMode
                    ? Row(
                  children: [
                    Expanded(
                      flex: (_splitScreenManager.splitRatio * 100).toInt(),
                      child: Column(
                        children: [
                          ChatHeader(
                            isDarkMode: widget.isDarkMode,
                            isSidebarVisible: provider.isSidebarVisible,
                            selectedModel: provider.selectedModel,
                            availableModels: _availableModels,
                            isAlwaysOnTop: _isAlwaysOnTop,
                            onToggleSidebar: _toggleSidebar,
                            onModelChanged: (model) => provider.setSelectedModel(model),
                            onSettingsTap: _showSettingsDialog,
                            onMiniModeTap: _toggleMiniMode,
                            onToggleAlwaysOnTop: _toggleAlwaysOnTop,
                            onRefreshModels: _fetchAvailableModels,
                          ),
                          Expanded(
                            child: _buildChatPane(
                              messages: provider.messages,
                              scrollController: _scrollController,
                              textController: _controller,
                              attachedFiles: _attachedFiles,
                              isRightPane: false,
                              conversationIndex: provider.selectedConversationIndex,
                            ),
                          ),
                        ],
                      ),
                    ),
                    MouseRegion(
                      cursor: SystemMouseCursors.resizeColumn,
                      child: GestureDetector(
                        onPanUpdate: (details) {
                          setState(() {
                            final delta = details.delta.dx / context.size!.width;
                            _splitScreenManager.updateSplitRatio(
                              _splitScreenManager.splitRatio + delta,
                            );
                          });
                        },
                        child: Container(
                          width: 4,
                          color: widget.isDarkMode ? Colors.grey[700] : Colors.grey[300],
                        ),
                      ),
                    ),
                    Expanded(
                      flex: ((1 - _splitScreenManager.splitRatio) * 100).toInt(),
                      child: _buildChatPane(
                        // messages: _splitScreenManager.rightConversationIndex != null &&
                        //     _splitScreenManager.rightConversationIndex! < provider.conversations.length
                        //     ? provider.conversations[_splitScreenManager.rightConversationIndex!]
                        //     .messages
                        //     .map((m) => ChatMessage(
                        //   text: m.text,
                        //   isUser: m.isUser,
                        //   timestamp: m.timestamp,
                        //   thinkingText: m.thinkingText,
                        //   isThinking: m.isThinking,
                        //   modelName: m.modelName,
                        //   attachedFiles: m.attachedFiles,
                        // ))
                        //     .toList()
                        //     : [],
                        messages: _splitScreenManager.rightPaneMessages,
                        scrollController: _rightScrollController,
                        textController: _rightController,
                        attachedFiles: _rightAttachedFiles,
                        isRightPane: true,
                        conversationIndex: _splitScreenManager.rightConversationIndex,
                      ),
                    ),
                  ],
                )
                    : Column(
                  children: [
                    ChatHeader(
                      isDarkMode: widget.isDarkMode,
                      isSidebarVisible: provider.isSidebarVisible,
                      selectedModel: provider.selectedModel,
                      availableModels: _availableModels,
                      isAlwaysOnTop: _isAlwaysOnTop,
                      onToggleSidebar: _toggleSidebar,
                      onModelChanged: (model) => provider.setSelectedModel(model),
                      onSettingsTap: _showSettingsDialog,
                      onMiniModeTap: _toggleMiniMode,
                      onToggleAlwaysOnTop: _toggleAlwaysOnTop,
                      onRefreshModels: _fetchAvailableModels,
                    ),
                    Expanded(
                      child: provider.messages.isEmpty
                          ? const EmptyChatPlaceholder()
                          : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: provider.messages.length + (provider.isGenerating ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (provider.isGenerating && index == provider.messages.length) {
                            return TypingIndicator(
                              isDarkMode: widget.isDarkMode,
                              modelName: provider.selectedModel,
                            );
                          }

                          final message = provider.messages[index];
                          return MessageBubble(
                            message: message,
                            isDarkMode: widget.isDarkMode,
                            onEdit: message.isUser ? () => _editMessage(index) : null,
                            onRegenerate: !message.isUser &&
                                index == provider.messages.length - 1 &&
                                !provider.isGenerating
                                ? _regenerateLastResponse
                                : null,
                          );
                        },
                      ),
                    ),
                    ChatInputArea(
                      controller: _controller,
                      isDarkMode: widget.isDarkMode,
                      isGenerating: provider.isGenerating,
                      attachedFiles: _attachedFiles,
                      onSendMessage: _sendMessage,
                      onStopGeneration: _stopGeneration,
                      onPickFiles: _pickFiles,
                      onRemoveFile: _removeAttachedFile,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

