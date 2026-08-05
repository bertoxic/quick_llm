import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../dialogs/settings_dialog.dart';
import '../dialogs/provider_connection_dialog.dart';
import '../dialogs/voice_settings_dialog.dart';
import '../models/ai_provider.dart';
import '../models/chat_message.dart';
import '../models/conversation.dart';
import '../models/voice_settings.dart';
import '../provider/ChatProvider.dart';
import '../services/ai_service.dart';
import '../services/markdown_pdf_service.dart';
import '../services/storage_service.dart';
import '../services/voice_service.dart';
import '../theme/app_theme.dart';
import '../utils/conversation_manager.dart';
import '../utils/helpers.dart';
import '../utils/local_tools.dart';
import '../utils/thinking_parser.dart';
import '../widgets/chat_header.dart';
import '../widgets/message_bubble.dart';
import '../widgets/model_picker.dart';
import '../widgets/sidebar.dart';
import '../widgets/typing_indicaator.dart';
import 'mini_mode_screen.dart';

enum _PaneSide { left, right }

class _ChatPaneRuntime {
  _ChatPaneRuntime(this.side) {
    scrollHelper = ScrollControllerHelper(scrollController);
  }

  final _PaneSide side;
  final TextEditingController controller = TextEditingController();
  final ScrollController scrollController = ScrollController();
  late final ScrollControllerHelper scrollHelper;
  final AiService aiService = AiService(AiProviderConfig.ollama());
  final List<File> attachedFiles = [];

  int? conversationIndex;
  String? _selectedModel;
  final ValueNotifier<String?> selectedModelListenable = ValueNotifier(null);
  List<ChatMessage> messages = [];
  bool isGenerating = false;
  bool isSending = false;
  DateTime? generationStartedAt;
  String responseBuffer = '';
  String thinkingBuffer = '';
  Map<String, dynamic>? activeRequestDetails;
  QuickAction? selectedAction;

  String? get selectedModel => _selectedModel;

  set selectedModel(String? value) {
    if (_selectedModel == value) return;
    _selectedModel = value;
    selectedModelListenable.value = value;
  }

  void dispose() {
    controller.dispose();
    scrollHelper.dispose();
    aiService.dispose();
    selectedModelListenable.dispose();
  }
}

class _PreviewChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;

  const _PreviewChip({
    required this.icon,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: accent),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: accent,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

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
  final StorageService _storageService = StorageService();
  late final ConversationManager _conversationManager;
  late final FileAttachmentHelper _fileAttachmentHelper;
  late final _ChatPaneRuntime _leftPane;
  late final _ChatPaneRuntime _rightPane;
  final TextEditingController _systemPromptController = TextEditingController();
  final MarkdownPdfService _markdownPdfService = MarkdownPdfService();
  final VoiceService _voiceService = VoiceService();

  bool _isAlwaysOnTop = false;
  bool _isMiniMode = false;
  bool _isSplitMode = false;
  bool _copyFileAttachments = true;
  String? _audioProcessingMessageKey;
  String? _audioReadyMessageKey;
  String? _audioReadyStatus;
  String? _pdfExportingMessageKey;
  String? _pdfExportStatus;
  String? _activeAudioMessageKey;
  bool _isActiveAudioPlaying = false;
  Duration _activeAudioPosition = Duration.zero;
  Duration? _activeAudioDuration;
  VoiceSettings _voiceSettings = VoiceSettings.kokoro();
  double _splitRatio = 0.5;
  List<String> _availableModels = [];
  String _chatSearchQuery = '';
  List<int> _chatSearchMatches = [];
  int _chatSearchCursor = 0;
  Timer? _statsTimer;
  Timer? _audioStatusTimer;
  StreamSubscription<PlayerState>? _audioPlayerStateSubscription;
  StreamSubscription<Duration>? _audioPositionSubscription;
  StreamSubscription<Duration?>? _audioDurationSubscription;

  @override
  void initState() {
    super.initState();
    _conversationManager = ConversationManager(_storageService);
    _fileAttachmentHelper = FileAttachmentHelper(_storageService);
    _leftPane = _ChatPaneRuntime(_PaneSide.left);
    _rightPane = _ChatPaneRuntime(_PaneSide.right);

    windowManager.addListener(this);
    _listenToAudioPlayer();
    _setupScrollListeners();
    _initializeApp();
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _audioStatusTimer?.cancel();
    unawaited(_audioPlayerStateSubscription?.cancel() ?? Future.value());
    unawaited(_audioPositionSubscription?.cancel() ?? Future.value());
    unawaited(_audioDurationSubscription?.cancel() ?? Future.value());
    windowManager.removeListener(this);
    _leftPane.dispose();
    _rightPane.dispose();
    unawaited(_voiceService.dispose());
    _systemPromptController.dispose();
    super.dispose();
  }

  void _setupScrollListeners() {
    _leftPane.scrollHelper.setupListener(
      onUserScrolledUp: () {
        if (mounted) setState(() {});
      },
      isGenerating: () => _leftPane.isGenerating,
    );
    _rightPane.scrollHelper.setupListener(
      onUserScrolledUp: () {
        if (mounted) setState(() {});
      },
      isGenerating: () => _rightPane.isGenerating,
    );
  }

  Future<void> _initializeApp() async {
    await _loadConversations();
    await _loadPreferences();
    await _fetchAvailableModels();

    if (!mounted) return;

    final provider = context.read<ChatProvider>();
    if (provider.conversations.isNotEmpty) {
      _loadConversation(0, side: _PaneSide.left);
    } else {
      _startNewConversation(side: _PaneSide.left);
    }
  }

  _ChatPaneRuntime _pane(_PaneSide side) {
    return side == _PaneSide.left ? _leftPane : _rightPane;
  }

  _PaneSide _otherSide(_PaneSide side) {
    return side == _PaneSide.left ? _PaneSide.right : _PaneSide.left;
  }

  void _setChatSearchQuery(String query) {
    setState(() {
      _chatSearchQuery = query;
      _refreshChatSearchMatches(updateState: false);
      _chatSearchCursor = 0;
    });
    _scrollToActiveSearchMatch();
  }

  void _clearChatSearch() {
    setState(() {
      _chatSearchQuery = '';
      _chatSearchMatches = [];
      _chatSearchCursor = 0;
    });
  }

  void _goToNextSearchMatch() {
    if (_chatSearchMatches.isEmpty) return;
    setState(() {
      _chatSearchCursor = (_chatSearchCursor + 1) % _chatSearchMatches.length;
    });
    _scrollToActiveSearchMatch();
  }

  void _goToPreviousSearchMatch() {
    if (_chatSearchMatches.isEmpty) return;
    setState(() {
      _chatSearchCursor = (_chatSearchCursor - 1 + _chatSearchMatches.length) %
          _chatSearchMatches.length;
    });
    _scrollToActiveSearchMatch();
  }

  void _refreshChatSearchMatches({bool updateState = true}) {
    final query = _chatSearchQuery.trim().toLowerCase();
    final matches = <int>[];
    if (query.isNotEmpty) {
      for (var i = 0; i < _leftPane.messages.length; i++) {
        final message = _leftPane.messages[i];
        if (_messageMatchesSearch(message, query)) matches.add(i);
      }
    }

    void apply() {
      _chatSearchMatches = matches;
      if (_chatSearchCursor >= _chatSearchMatches.length) {
        _chatSearchCursor = 0;
      }
    }

    if (updateState && mounted) {
      setState(apply);
    } else {
      apply();
    }
  }

  void _scrollToActiveSearchMatch() {
    if (_chatSearchMatches.isEmpty) return;
    final messageIndex = _chatSearchMatches[_chatSearchCursor];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_leftPane.scrollController.hasClients) return;
      final maxExtent = _leftPane.scrollController.position.maxScrollExtent;
      final denominator = (_leftPane.messages.length - 1).clamp(1, 1 << 30);
      final target = (maxExtent * (messageIndex / denominator))
          .clamp(0.0, maxExtent)
          .toDouble();
      _leftPane.scrollController
          .animateTo(
            target,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
          )
          .catchError((_) {});
    });
  }

  Future<void> _loadConversations() async {
    final conversations = await _conversationManager.load();
    if (mounted) {
      context.read<ChatProvider>().setConversations(conversations);
    }
  }

  Future<void> _loadPreferences() async {
    final prefs = await _storageService.loadPreferences();
    if (!mounted) return;

    final provider = context.read<ChatProvider>();
    provider.updateSettings(
      isSidebarVisible: prefs['sidebarVisible'] ?? true,
      systemPrompt: prefs['systemPrompt'] ?? '',
      temperature: prefs['temperature'] ?? 0.7,
      maxTokens: prefs['maxTokens'] ?? 2048,
      numCtx: prefs['numCtx'] ?? 32768,
      useSystemPrompt: prefs['useSystemPrompt'] ?? false,
      enableToolCalling: prefs['enableToolCalling'] ?? true,
      model: prefs['selectedModel'] as String?,
    );
    provider.setAiProvider(AiProviderConfig.fromPreferences(prefs));
    _leftPane.aiService.configure(provider.aiProvider);
    _rightPane.aiService.configure(provider.aiProvider);

    _systemPromptController.text = provider.systemPrompt;
    setState(() {
      _copyFileAttachments = prefs['copyFileAttachments'] ?? true;
      _voiceSettings = VoiceSettings.fromPreferences(prefs);
    });
  }

  Future<void> _savePreferences() async {
    if (!mounted) return;

    final provider = context.read<ChatProvider>();
    await _storageService.savePreferences({
      'sidebarVisible': provider.isSidebarVisible,
      'systemPrompt': provider.systemPrompt,
      'temperature': provider.temperature,
      'maxTokens': provider.maxTokens,
      'numCtx': provider.numCtx,
      'useSystemPrompt': provider.useSystemPrompt,
      'enableToolCalling': provider.enableToolCalling,
      'monitorClipboard': false,
      'copyFileAttachments': _copyFileAttachments,
      'selectedModel': provider.selectedModel,
      ...provider.aiProvider.toPreferenceValues(),
      ..._voiceSettings.toPreferenceValues(),
    });
  }

  Future<void> _fetchAvailableModels() async {
    final provider = context.read<ChatProvider>();
    _leftPane.aiService.configure(provider.aiProvider);
    _rightPane.aiService.configure(provider.aiProvider);
    final models = await _leftPane.aiService.fetchAvailableModels();
    if (!mounted) return;

    if (models.isEmpty) {
      provider.setSelectedModel(null, notify: false);
      setState(() {
        _availableModels = models;
        _leftPane.selectedModel = null;
        _rightPane.selectedModel = null;
      });
      _showSnackBar(
        'No models found for ${provider.aiProvider.displayName}. Check the connection in Settings.',
        duration: 5,
      );
      return;
    }

    final current = provider.selectedModel != null &&
            models.contains(provider.selectedModel)
        ? provider.selectedModel!
        : models.first;

    provider.setSelectedModel(current, notify: false);
    setState(() {
      _availableModels = models;
      if (!models.contains(_leftPane.selectedModel)) {
        _leftPane.selectedModel = current;
      }
      if (!models.contains(_rightPane.selectedModel)) {
        _rightPane.selectedModel = current;
      }
    });
  }

  Future<void> _sendMessage(
    _PaneSide side, {
    bool regenerate = false,
    String? message,
  }) async {
    if (!mounted) return;

    final pane = _pane(side);
    final provider = context.read<ChatProvider>();
    final selectedModel = pane.selectedModel ?? provider.selectedModel;
    final selectedAction = regenerate ? null : pane.selectedAction;
    var messageText = (message ?? pane.controller.text).trim();
    ChatMessage? userMessage;

    if (selectedModel == null || selectedModel.isEmpty) {
      _showSnackBar('No model selected. Select a model first.');
      return;
    }

    if (regenerate) {
      for (var i = pane.messages.length - 1; i >= 0; i--) {
        if (pane.messages[i].isUser) {
          userMessage = pane.messages[i];
          messageText = userMessage.text.trim();
          break;
        }
      }
      if (userMessage == null) return;
    } else {
      if (messageText.isEmpty && pane.attachedFiles.isEmpty) return;
    }

    if (pane.isGenerating || pane.isSending) return;
    pane.aiService.configure(provider.aiProvider);

    if (!regenerate) {
      final attachmentPaths =
          pane.attachedFiles.map((file) => file.path).toList();
      final newUserMessage = ChatMessage(
        text: messageText,
        isUser: true,
        timestamp: DateTime.now(),
        attachedFiles: attachmentPaths.isNotEmpty ? attachmentPaths : null,
        details: _buildUserMessageDetails(messageText, attachmentPaths),
      );
      userMessage = newUserMessage;

      setState(() {
        pane.messages.add(newUserMessage);
        pane.controller.clear();
        pane.attachedFiles.clear();
        pane.selectedAction = null;
      });
    }

    final activeUserMessage = userMessage!;

    await _ensureConversationForPane(pane, provider);

    final fileTypes =
        FileAttachmentHelper.separateFileTypes(activeUserMessage.attachedFiles);
    final contextMessages = ChatMessageBuilder.extractContextMessages([
      ...pane.messages,
      ChatMessage(text: '', isUser: false, timestamp: DateTime.now()),
    ]);
    var toolContext = provider.enableToolCalling
        ? await LocalToolService.contextForPrompt(
            activeUserMessage.text,
            forcedAction: selectedAction?.executionMode,
          )
        : const LocalToolContext([]);
    final effectivePrompt = provider.enableToolCalling
        ? LocalToolService.composePrompt(activeUserMessage.text, toolContext)
        : activeUserMessage.text;
    final requestDetails = _buildRequestDetails(
      pane: pane,
      provider: provider,
      model: selectedModel,
      prompt: activeUserMessage.text,
      effectivePrompt: effectivePrompt,
      contextMessages: contextMessages,
      attachments: activeUserMessage.attachedFiles ?? const [],
      fileTypes: fileTypes,
      toolContext: toolContext,
    );
    if (selectedAction != null) {
      requestDetails['quick_action'] = selectedAction.executionMode;
    }

    final assistantMessage = ChatMessage(
      text: '',
      isUser: false,
      timestamp: DateTime.now(),
      modelName: selectedModel,
      details: {
        'status': 'generating',
        'request': requestDetails,
        'tools': toolContext.toDetails(),
      },
    );

    setState(() {
      pane.selectedModel = selectedModel;
      pane.messages.add(assistantMessage);
      pane.isSending = true;
      pane.isGenerating = true;
      pane.generationStartedAt = DateTime.now();
      pane.responseBuffer = '';
      pane.thinkingBuffer = '';
      pane.activeRequestDetails = requestDetails;
    });

    _syncLeftPaneToProviderIfNeeded(pane, provider);
    await _persistPane(pane, provider);
    pane.scrollHelper.resetAutoScroll();
    pane.scrollHelper.scrollToBottom();
    _startStatsTimer();

    final messagesArray = ChatMessageBuilder.buildMessagesArray(
      contextMessages: contextMessages,
      currentMessageText: effectivePrompt,
    );

    Map<String, dynamic>? finalOllamaPayload;

    try {
      await for (final event in pane.aiService.generateChatResponse(
        model: selectedModel,
        prompt: effectivePrompt,
        messagesArray: messagesArray,
        systemPrompt: LocalToolService.applySystemInstructions(
          provider.useSystemPrompt ? provider.systemPrompt : null,
          enableTools: provider.enableToolCalling,
        ),
        temperature: provider.temperature,
        maxTokens: provider.maxTokens,
        numCtx: provider.numCtx,
        images: fileTypes.images,
        documents: fileTypes.documents,
        audio: fileTypes.audio,
        videos: fileTypes.videos,
        otherFiles: fileTypes.otherFiles,
        tools: provider.enableToolCalling
            ? LocalToolService.ollamaToolDefinitions()
            : null,
        toolExecutor: provider.enableToolCalling
            ? (toolCalls) async {
                final batch = await LocalToolService.executeOllamaToolCalls(
                  toolCalls,
                  fallbackPrompt: activeUserMessage.text,
                );
                toolContext = toolContext.merge(batch.context);
                requestDetails['tools'] = toolContext.toDetails();
                return batch.toolMessages;
              }
            : null,
        requestMetadata: requestDetails,
      )) {
        if (!mounted) break;

        if (event.isThinking) {
          pane.thinkingBuffer += event.delta;
          _updateStreamingAssistant(pane, provider);
        } else if (event.isContent) {
          pane.responseBuffer += event.delta;
          _updateStreamingAssistant(pane, provider);
        } else if (event.isContentReplacement) {
          pane.responseBuffer = event.delta;
          _updateStreamingAssistant(pane, provider);
        } else if (event.isDone) {
          finalOllamaPayload = event.raw;
        } else if (event.isToolCall || event.isToolResult) {
          _updateStreamingAssistant(
            pane,
            provider,
            detailsOverride: {
              'status': event.isToolCall ? 'tool_calling' : 'generating',
              'request': requestDetails,
              'tools': toolContext.toDetails(),
              'ollama_tool': event.raw,
            },
          );
        } else if (event.isError) {
          pane.responseBuffer = event.delta;
          _updateStreamingAssistant(
            pane,
            provider,
            detailsOverride: {
              'status': 'error',
              'request': requestDetails,
              'tools': toolContext.toDetails(),
              'error': event.delta,
              if (event.raw != null) 'ollama': event.raw,
            },
          );
        }
      }
    } finally {
      if (mounted) {
        final finalDetails = _buildAssistantDetails(
          pane: pane,
          requestDetails: requestDetails,
          ollamaPayload: finalOllamaPayload,
          status: finalOllamaPayload == null &&
                  pane.responseBuffer.startsWith('Error:')
              ? 'error'
              : 'complete',
        );

        _updateStreamingAssistant(
          pane,
          provider,
          detailsOverride: finalDetails,
          isThinking: false,
        );

        setState(() {
          pane.isGenerating = false;
          pane.isSending = false;
        });

        await _persistPane(pane, provider);
        _stopStatsTimerIfIdle();
      }
    }
  }

  void _updateStreamingAssistant(
    _ChatPaneRuntime pane,
    ChatProvider provider, {
    Map<String, dynamic>? detailsOverride,
    bool? isThinking,
  }) {
    if (pane.messages.isEmpty || pane.messages.last.isUser) return;

    final current = pane.messages.last;
    final parsed = ThinkingParser.parse(pane.responseBuffer, current);
    final hasSeparateThinking = pane.thinkingBuffer.trim().isNotEmpty;
    final thinkingText =
        hasSeparateThinking ? pane.thinkingBuffer : parsed.thinkingText;
    final displayText =
        hasSeparateThinking ? pane.responseBuffer : parsed.displayText;

    pane.messages[pane.messages.length - 1] = current.copyWith(
      text: displayText,
      thinkingText: thinkingText?.trim().isEmpty == true ? null : thinkingText,
      isThinking:
          isThinking ?? (hasSeparateThinking && pane.responseBuffer.isEmpty),
      details: detailsOverride ?? current.details,
    );

    _syncLeftPaneToProviderIfNeeded(pane, provider);

    setState(() {
      if (pane.side == _PaneSide.left && _chatSearchQuery.trim().isNotEmpty) {
        _refreshChatSearchMatches(updateState: false);
      }
    });
    if (pane.scrollHelper.isAutoScrollEnabled) {
      pane.scrollHelper.scrollToBottom();
    }
  }

  Future<void> _ensureConversationForPane(
    _ChatPaneRuntime pane,
    ChatProvider provider,
  ) async {
    if (pane.conversationIndex != null &&
        pane.conversationIndex! < provider.conversations.length) {
      await _persistPane(pane, provider);
      return;
    }

    final firstUserMessage = pane.messages.firstWhere(
      (message) => message.isUser,
      orElse: () => ChatMessage(
        text: 'New chat',
        isUser: true,
        timestamp: DateTime.now(),
      ),
    );

    final newConversation = Conversation(
      title: _titleFromMessage(firstUserMessage),
      messages: List<ChatMessage>.from(pane.messages),
      timestamp: DateTime.now(),
    );

    provider.addConversation(newConversation);
    _shiftPaneIndicesAfterInsert(pane, provider);
    pane.conversationIndex = 0;

    if (pane.side == _PaneSide.left) {
      provider.selectConversation(0);
      provider.setMessages(List<ChatMessage>.from(pane.messages));
    }

    await _conversationManager.save(provider);
  }

  void _shiftPaneIndicesAfterInsert(
    _ChatPaneRuntime sourcePane,
    ChatProvider provider,
  ) {
    for (final pane in [_leftPane, _rightPane]) {
      if (identical(pane, sourcePane)) continue;
      if (pane.conversationIndex != null) {
        pane.conversationIndex = pane.conversationIndex! + 1;
      }
    }

    if (sourcePane.side != _PaneSide.left &&
        _leftPane.conversationIndex != null) {
      provider.selectConversation(_leftPane.conversationIndex);
    }
  }

  Future<void> _persistPane(
    _ChatPaneRuntime pane,
    ChatProvider provider,
  ) async {
    final index = pane.conversationIndex;
    if (index == null || index >= provider.conversations.length) return;

    final current = provider.conversations[index];
    provider.updateConversation(
      index,
      current.copyWith(messages: List<ChatMessage>.from(pane.messages)),
    );

    if (pane.side == _PaneSide.left) {
      provider.selectConversation(index);
      provider.setMessages(List<ChatMessage>.from(pane.messages));
    }

    await _conversationManager.save(provider);
  }

  void _syncLeftPaneToProviderIfNeeded(
    _ChatPaneRuntime pane,
    ChatProvider provider,
  ) {
    if (pane.side != _PaneSide.left) return;
    provider.selectConversation(pane.conversationIndex);
    provider.setMessages(List<ChatMessage>.from(pane.messages));
  }

  void _startNewConversation({_PaneSide side = _PaneSide.left}) {
    final pane = _pane(side);
    final provider = context.read<ChatProvider>();

    if (pane.isGenerating) {
      _showSnackBar('Stop the current response first.');
      return;
    }

    setState(() {
      pane.conversationIndex = null;
      pane.messages = [];
      pane.attachedFiles.clear();
      pane.controller.clear();
      if (side == _PaneSide.left) {
        _chatSearchMatches = [];
        _chatSearchCursor = 0;
      }
    });

    if (side == _PaneSide.left) {
      provider.selectConversation(null);
      provider.clearMessages();
    }
  }

  void _loadConversation(int index, {_PaneSide side = _PaneSide.left}) {
    if (!mounted) return;

    final provider = context.read<ChatProvider>();
    final pane = _pane(side);
    if (index < 0 || index >= provider.conversations.length) return;

    if (pane.isGenerating) {
      _showSnackBar('Stop the current response in this pane first.');
      return;
    }

    final conversation = provider.conversations[index];
    setState(() {
      pane.conversationIndex = index;
      pane.messages =
          conversation.messages.map((message) => message.copyWith()).toList();
      pane.attachedFiles.clear();
      pane.controller.clear();
      if (side == _PaneSide.left) {
        _refreshChatSearchMatches(updateState: false);
      }
    });

    if (side == _PaneSide.left) {
      provider.selectConversation(index);
      provider.setMessages(List<ChatMessage>.from(pane.messages));
    }

    _checkMissingAttachmentsForPane(pane);
    pane.scrollHelper.scrollToBottom();
  }

  void _deleteConversation(int index) {
    final provider = context.read<ChatProvider>();
    if (index < 0 || index >= provider.conversations.length) return;

    if ((_leftPane.conversationIndex == index && _leftPane.isGenerating) ||
        (_rightPane.conversationIndex == index && _rightPane.isGenerating)) {
      _showSnackBar('Stop generation before deleting this conversation.');
      return;
    }

    provider.deleteConversation(index);

    for (final pane in [_leftPane, _rightPane]) {
      if (pane.conversationIndex == index) {
        pane.conversationIndex = null;
        pane.messages = [];
      } else if (pane.conversationIndex != null &&
          pane.conversationIndex! > index) {
        pane.conversationIndex = pane.conversationIndex! - 1;
      }
    }

    _syncLeftPaneToProviderIfNeeded(_leftPane, provider);
    unawaited(_conversationManager.save(provider));
  }

  void _toggleConversationPin(int index) {
    final provider = context.read<ChatProvider>();
    if (index < 0 || index >= provider.conversations.length) return;

    final conversation = provider.conversations[index];
    provider.updateConversation(
      index,
      conversation.copyWith(isPinned: !conversation.isPinned),
    );
    unawaited(_conversationManager.save(provider));
  }

  void _regenerateLastResponse(_PaneSide side) {
    final pane = _pane(side);
    if (pane.messages.length < 2 || pane.isGenerating) return;
    if (pane.messages.last.isUser) return;

    setState(() {
      pane.messages.removeLast();
      if (side == _PaneSide.left) {
        _refreshChatSearchMatches(updateState: false);
      }
    });

    final provider = context.read<ChatProvider>();
    _syncLeftPaneToProviderIfNeeded(pane, provider);
    unawaited(_persistPane(pane, provider));
    _sendMessage(side, regenerate: true);
  }

  void _editMessage(int index, _PaneSide side, String text) {
    final pane = _pane(side);
    if (index < 0 || index >= pane.messages.length || pane.isGenerating) return;

    final provider = context.read<ChatProvider>();
    final message = pane.messages[index];
    if (!message.isUser) return;
    final trimmedText = text.trim();
    if (trimmedText.isEmpty) return;
    final attachments = message.attachedFiles ?? const <String>[];

    setState(() {
      pane.messages[index] = message.copyWith(
        text: trimmedText,
        details: _buildUserMessageDetails(trimmedText, attachments),
      );
      pane.messages = pane.messages.sublist(0, index + 1);
      if (side == _PaneSide.left) {
        _refreshChatSearchMatches(updateState: false);
      }
    });

    _syncLeftPaneToProviderIfNeeded(pane, provider);
    unawaited(_persistPane(pane, provider));
    _sendMessage(side, regenerate: true, message: trimmedText);
  }

  void _stopGeneration(_PaneSide side) {
    final pane = _pane(side);
    if (!pane.isGenerating) return;

    pane.aiService.cancelGeneration();
    final provider = context.read<ChatProvider>();
    final stoppedDetails = _buildAssistantDetails(
      pane: pane,
      requestDetails: pane.activeRequestDetails ?? const {},
      status: 'stopped',
    );

    _updateStreamingAssistant(
      pane,
      provider,
      detailsOverride: stoppedDetails,
      isThinking: false,
    );

    setState(() {
      pane.isGenerating = false;
      pane.isSending = false;
    });

    unawaited(_persistPane(pane, provider));
    _stopStatsTimerIfIdle();
  }

  Future<void> _pickFiles({_PaneSide side = _PaneSide.left}) async {
    final files = await _fileAttachmentHelper.pickFiles(
      context: context,
      copyFileAttachments: _copyFileAttachments,
    );

    if (files.isEmpty || !mounted) return;

    setState(() {
      _pane(side).attachedFiles.addAll(files);
    });
  }

  void _removeAttachedFile(int index, {_PaneSide side = _PaneSide.left}) {
    final pane = _pane(side);
    if (index < 0 || index >= pane.attachedFiles.length) return;

    setState(() {
      pane.attachedFiles.removeAt(index);
    });
  }

  Future<void> _checkMissingAttachmentsForPane(_ChatPaneRuntime pane) async {
    final files = <String>[];
    for (final message in pane.messages) {
      if (message.attachedFiles != null) {
        files.addAll(message.attachedFiles!);
      }
    }

    await _fileAttachmentHelper.checkMissingAttachments(
      context: context,
      allFiles: files,
    );
  }

  void _enableSplitMode(int leftIndex, int rightIndex) {
    setState(() {
      _isSplitMode = true;
    });
    _loadConversation(leftIndex, side: _PaneSide.left);
    _loadConversation(rightIndex, side: _PaneSide.right);
  }

  void _dropConversationOnPane(int index, _PaneSide side) {
    if (!mounted) return;

    final provider = context.read<ChatProvider>();
    final otherSide = _otherSide(side);
    final otherPane = _pane(otherSide);
    final selected = provider.selectedConversationIndex;

    setState(() {
      _isSplitMode = true;
    });

    _loadConversation(index, side: side);

    if (otherPane.conversationIndex == null &&
        selected != null &&
        selected >= 0 &&
        selected < provider.conversations.length &&
        selected != index) {
      _loadConversation(selected, side: otherSide);
    }
  }

  void _disableSplitMode() {
    if (_rightPane.isGenerating) {
      _stopGeneration(_PaneSide.right);
    }

    setState(() {
      _isSplitMode = false;
      _rightPane.conversationIndex = null;
      _rightPane.messages = [];
      _rightPane.attachedFiles.clear();
      _rightPane.controller.clear();
    });
  }

  void _swapPanes() {
    if (_leftPane.isGenerating || _rightPane.isGenerating) {
      _showSnackBar('Stop generation before swapping panes.');
      return;
    }

    final leftIndex = _leftPane.conversationIndex;
    final rightIndex = _rightPane.conversationIndex;

    if (rightIndex != null) {
      _loadConversation(rightIndex, side: _PaneSide.left);
    } else {
      _startNewConversation(side: _PaneSide.left);
    }

    if (leftIndex != null) {
      _loadConversation(leftIndex, side: _PaneSide.right);
    } else {
      _startNewConversation(side: _PaneSide.right);
    }
  }

  void _setPaneModel(_PaneSide side, String model) {
    final pane = _pane(side);
    final provider = context.read<ChatProvider>();
    if (pane.selectedModel == model) return;

    pane.selectedModel = model;

    if (side == _PaneSide.left) {
      // The pane has already rebuilt locally. Avoid a second app-wide provider
      // notification just to mirror this value for persistence.
      provider.setSelectedModel(model, notify: false);
      unawaited(_savePreferences());
    }
  }

  void _showSettingsDialog() {
    final provider = context.read<ChatProvider>();

    showDialog(
      context: context,
      builder: (context) => SettingsDialog(
        systemPromptController: _systemPromptController,
        useSystemPrompt: provider.useSystemPrompt,
        enableToolCalling: provider.enableToolCalling,
        temperature: provider.temperature,
        maxTokens: provider.maxTokens,
        numCtx: provider.numCtx,
        onNumCtxChanged: provider.setNumCtx,
        onUseSystemPromptChanged: provider.setUseSystemPrompt,
        onEnableToolCallingChanged: provider.setEnableToolCalling,
        onTemperatureChanged: provider.setTemperature,
        onMaxTokensChanged: provider.setMaxTokens,
        onSave: () {
          provider.setSystemPrompt(_systemPromptController.text);
          _savePreferences();
        },
        aiProvider: provider.aiProvider,
        onProviderTap: _showProviderConnectionDialog,
        voiceSettings: _voiceSettings,
        onVoiceTap: _showVoiceSettingsDialog,
        isDarkMode: widget.isDarkMode,
      ),
    );
  }

  Future<void> _showVoiceSettingsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => VoiceSettingsDialog(
        initialSettings: _voiceSettings,
        onLoadVoices: _voiceService.fetchVoices,
        onTestSpeech: _voiceService.speak,
        onSave: (settings) async {
          setState(() => _voiceSettings = settings);
          await _savePreferences();
        },
      ),
    );
  }

  Future<void> _speakMessage(String text, String messageKey) async {
    if (!_voiceSettings.enabled) {
      _showSnackBar('Enable Local Voice / TTS in Settings first.');
      return;
    }
    if (_audioProcessingMessageKey != null) {
      _showSnackBar('Audio is already being generated.');
      return;
    }

    if (_activeAudioMessageKey == messageKey) {
      if (_isActiveAudioPlaying) {
        await _voiceService.stop();
      } else {
        await _voiceService.resume();
      }
      return;
    }

    _beginAudioProcessing(messageKey);
    try {
      await _voiceService.speak(text, _voiceSettings);
      if (mounted) {
        setState(() {
          _activeAudioMessageKey = messageKey;
          _isActiveAudioPlaying = _voiceService.isPlaying;
          _activeAudioPosition = _voiceService.position;
          _activeAudioDuration = _voiceService.duration;
        });
      }
      _completeAudioProcessing(
        messageKey,
        status: 'Audio ready — playing now',
        notification: 'Audio is ready and playing.',
      );
    } catch (error) {
      if (mounted) _showSnackBar('Voice playback failed: $error');
    } finally {
      _endAudioProcessing(messageKey);
    }
  }

  Future<void> _downloadMessageAudio(String text, String messageKey) async {
    if (!_voiceSettings.enabled) {
      _showSnackBar('Enable Local Voice / TTS in Settings first.');
      return;
    }
    if (_audioProcessingMessageKey != null) {
      _showSnackBar('Audio is already being generated.');
      return;
    }

    _beginAudioProcessing(messageKey);
    try {
      final audioFile = await _voiceService.download(text, _voiceSettings);
      _completeAudioProcessing(
        messageKey,
        status: 'Audio downloaded',
        notification: 'Audio downloaded to ${audioFile.path}',
      );
    } catch (error) {
      if (mounted) _showSnackBar('Audio download failed: $error');
    } finally {
      _endAudioProcessing(messageKey);
    }
  }

  Future<void> _downloadMessagePdf(
    ChatMessage message,
    String messageKey,
  ) async {
    if (_pdfExportingMessageKey != null) {
      _showSnackBar('A PDF is already being created.');
      return;
    }

    setState(() {
      _pdfExportingMessageKey = messageKey;
      _pdfExportStatus = 'Preparing PDF';
    });
    // Let the per-message loading indicator paint before the export begins.
    await WidgetsBinding.instance.endOfFrame;
    try {
      final pdfFile = await _markdownPdfService.download(
        message.text,
        artifacts: _pdfVisualArtifacts(message),
        onStage: (stage) {
          if (!mounted || _pdfExportingMessageKey != messageKey) return;
          setState(() => _pdfExportStatus = stage);
        },
      );
      if (mounted) _showSnackBar('PDF downloaded to ${pdfFile.path}');
    } catch (error) {
      if (mounted) _showSnackBar('PDF download failed: $error');
    } finally {
      if (mounted && _pdfExportingMessageKey == messageKey) {
        setState(() {
          _pdfExportingMessageKey = null;
          _pdfExportStatus = null;
        });
      }
    }
  }

  List<MarkdownPdfArtifact> _pdfVisualArtifacts(ChatMessage message) {
    final details = message.details;
    if (details == null) return const <MarkdownPdfArtifact>[];

    Map? tools = details['tools'] is Map ? details['tools'] as Map : null;
    final request = details['request'];
    if (tools == null && request is Map && request['tools'] is Map) {
      tools = request['tools'] as Map;
    }
    final activities = tools?['activity'];
    if (activities is! List) return const <MarkdownPdfArtifact>[];

    final artifacts = <MarkdownPdfArtifact>[];
    for (final activity in activities) {
      if (activity is! Map || activity['artifact'] is! Map) continue;
      final artifact = activity['artifact'] as Map;
      final type = '${artifact['type'] ?? ''}'.trim().toLowerCase();
      final content = '${artifact['content'] ?? ''}'.trim();
      if ((type != 'svg' && type != 'mermaid') || content.isEmpty) continue;
      if (artifacts.any(
        (existing) =>
            existing.type == type && existing.content.trim() == content,
      )) {
        continue;
      }
      artifacts.add(
        MarkdownPdfArtifact(
          type: type,
          content: content,
          label:
              '${artifact['label'] ?? activity['title'] ?? 'Generated diagram'}',
        ),
      );
    }
    return artifacts;
  }

  void _beginAudioProcessing(String messageKey) {
    _audioStatusTimer?.cancel();
    setState(() {
      _audioProcessingMessageKey = messageKey;
      _audioReadyMessageKey = null;
      _audioReadyStatus = null;
    });
  }

  void _completeAudioProcessing(
    String messageKey, {
    required String status,
    required String notification,
  }) {
    if (!mounted) return;

    setState(() {
      _audioProcessingMessageKey = null;
      _audioReadyMessageKey = messageKey;
      _audioReadyStatus = status;
    });
    _showSnackBar(notification);
    _audioStatusTimer?.cancel();
    _audioStatusTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || _audioReadyMessageKey != messageKey) return;
      setState(() {
        _audioReadyMessageKey = null;
        _audioReadyStatus = null;
      });
    });
  }

  void _endAudioProcessing(String messageKey) {
    if (!mounted || _audioProcessingMessageKey != messageKey) return;
    setState(() => _audioProcessingMessageKey = null);
  }

  void _listenToAudioPlayer() {
    _audioPlayerStateSubscription = _voiceService.playerStateStream.listen(
      (state) {
        if (!mounted || _activeAudioMessageKey == null) return;
        setState(() {
          _isActiveAudioPlaying = state.playing;
          if (state.processingState == ProcessingState.completed) {
            _isActiveAudioPlaying = false;
          }
        });
      },
    );
    _audioPositionSubscription = _voiceService.positionStream.listen(
      (position) {
        if (!mounted || _activeAudioMessageKey == null) return;
        setState(() => _activeAudioPosition = position);
      },
    );
    _audioDurationSubscription = _voiceService.durationStream.listen(
      (duration) {
        if (!mounted || _activeAudioMessageKey == null) return;
        setState(() => _activeAudioDuration = duration);
      },
    );
  }

  Future<void> _seekAudio(String messageKey, Duration position) async {
    if (_activeAudioMessageKey != messageKey) return;
    await _voiceService.seek(position);
    if (mounted) setState(() => _activeAudioPosition = position);
  }

  Future<void> _showProviderConnectionDialog() async {
    if (_leftPane.isGenerating || _rightPane.isGenerating) {
      _showSnackBar(
          'Stop active generation before changing the AI connection.');
      return;
    }

    final provider = context.read<ChatProvider>();
    await showDialog<void>(
      context: context,
      builder: (context) => ProviderConnectionDialog(
        initialConfiguration: provider.aiProvider,
        onSave: _applyProviderConfiguration,
      ),
    );
  }

  Future<void> _applyProviderConfiguration(
      AiProviderConfig configuration) async {
    final provider = context.read<ChatProvider>();
    provider.setAiProvider(configuration);
    _leftPane.aiService.configure(configuration);
    _rightPane.aiService.configure(configuration);
    await _savePreferences();
    await _fetchAvailableModels();
    await _savePreferences();
  }

  Future<void> _toggleAlwaysOnTop() async {
    final next = !_isAlwaysOnTop;
    await windowManager.setAlwaysOnTop(next);
    if (mounted) {
      setState(() {
        _isAlwaysOnTop = next;
      });
    }
  }

  void _toggleSidebar() {
    context.read<ChatProvider>().toggleSidebar();
    _savePreferences();
  }

  Future<void> _toggleMiniMode() async {
    final provider = context.read<ChatProvider>();
    await _persistPane(_leftPane, provider);

    setState(() {
      _isMiniMode = true;
    });
    await windowManager.setSize(const Size(350, 500));
    await windowManager.setAlwaysOnTop(true);
  }

  Future<void> _onExitMiniMode() async {
    final provider = context.read<ChatProvider>();

    setState(() {
      _isMiniMode = false;
    });

    await windowManager.setSize(const Size(1000, 700));
    if (!_isAlwaysOnTop) {
      await windowManager.setAlwaysOnTop(false);
    }

    if (provider.selectedConversationIndex != null) {
      _loadConversation(provider.selectedConversationIndex!,
          side: _PaneSide.left);
    }
  }

  Future<void> _exportConversation(Conversation conv) async {
    try {
      final path = await _conversationManager.exportConversation(conv);
      if (mounted) _showSnackBar('Exported to $path');
    } catch (e) {
      if (mounted) _showSnackBar('Export failed: $e');
    }
  }

  Future<void> _exportAllConversations() async {
    try {
      final path = await _conversationManager.exportAll(
        context.read<ChatProvider>().conversations,
      );
      if (mounted) _showSnackBar('Exported all to $path');
    } catch (e) {
      if (mounted) _showSnackBar('Export failed: $e');
    }
  }

  Future<void> _clearAllConversations() async {
    final success = await _storageService.clearAllConversations();
    if (!mounted || !success) return;

    final provider = context.read<ChatProvider>();
    provider.setConversations([]);
    _startNewConversation(side: _PaneSide.left);
    _startNewConversation(side: _PaneSide.right);
    setState(() {
      _isSplitMode = false;
    });
    _showSnackBar('All conversations cleared');
  }

  void _startStatsTimer() {
    _statsTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_leftPane.isGenerating || _rightPane.isGenerating) {
        setState(() {});
      }
    });
  }

  void _stopStatsTimerIfIdle() {
    if (_leftPane.isGenerating || _rightPane.isGenerating) return;
    _statsTimer?.cancel();
    _statsTimer = null;
  }

  Map<String, dynamic> _buildUserMessageDetails(
    String prompt,
    List<String> attachments,
  ) {
    return {
      'role': 'user',
      'prompt': {
        'characters': prompt.length,
        'estimated_tokens': _estimateTokens(prompt),
        'is_attachment_only': prompt.trim().isEmpty && attachments.isNotEmpty,
      },
      'attachments': _attachmentDetails(attachments),
    };
  }

  Map<String, dynamic> _buildRequestDetails({
    required _ChatPaneRuntime pane,
    required ChatProvider provider,
    required String model,
    required String prompt,
    required String effectivePrompt,
    required List<ChatMessage> contextMessages,
    required List<String> attachments,
    required ({
      List<String>? images,
      List<String>? documents,
      List<String>? audio,
      List<String>? videos,
      List<String>? otherFiles,
    }) fileTypes,
    required LocalToolContext toolContext,
  }) {
    return {
      'pane': pane.side.name,
      'conversation_index': pane.conversationIndex,
      'model': model,
      'provider': {
        'name': provider.aiProvider.displayName,
        'kind': provider.aiProvider.kind.name,
        'endpoint': provider.aiProvider.normalizedEndpoint,
      },
      'prompt': {
        'characters': prompt.length,
        'effective_characters': effectivePrompt.length,
        'estimated_tokens': _estimateTokens(prompt),
        'effective_estimated_tokens': _estimateTokens(effectivePrompt),
        'context_messages': contextMessages.length,
        'context_characters': contextMessages.fold<int>(
            0, (sum, message) => sum + message.text.length),
      },
      'settings': {
        'temperature': provider.temperature,
        'max_tokens': provider.maxTokens,
        'num_ctx': provider.numCtx,
        'system_prompt_used': provider.useSystemPrompt,
        'system_prompt_characters':
            provider.useSystemPrompt ? provider.systemPrompt.length : 0,
        'tool_calling_enabled': provider.enableToolCalling,
        'available_tool_count': provider.enableToolCalling
            ? LocalToolService.tierOneTools.length
            : 0,
      },
      'attachments': {
        'total': attachments.length,
        'images': fileTypes.images?.length ?? 0,
        'documents': fileTypes.documents?.length ?? 0,
        'audio': fileTypes.audio?.length ?? 0,
        'videos': fileTypes.videos?.length ?? 0,
        'other': fileTypes.otherFiles?.length ?? 0,
        'files': _attachmentDetails(attachments),
      },
      'tools': toolContext.toDetails(),
      'started_at': DateTime.now().toIso8601String(),
    };
  }

  Map<String, dynamic> _buildAssistantDetails({
    required _ChatPaneRuntime pane,
    required Map<String, dynamic> requestDetails,
    Map<String, dynamic>? ollamaPayload,
    String status = 'complete',
  }) {
    final completedAt = DateTime.now();
    final elapsed = pane.generationStartedAt == null
        ? null
        : completedAt.difference(pane.generationStartedAt!);

    final evalCount = _asNum(ollamaPayload?['eval_count']);
    final evalDuration = _asNum(ollamaPayload?['eval_duration']);
    final tokensPerSecond =
        evalCount != null && evalDuration != null && evalDuration > 0
            ? evalCount / (evalDuration / 1000000000)
            : null;

    return {
      'status': status,
      'request': requestDetails,
      if (requestDetails['tools'] != null) 'tools': requestDetails['tools'],
      'response': {
        'characters': pane.responseBuffer.length,
        'thinking_characters': pane.thinkingBuffer.length,
        'estimated_tokens': _estimateTokens(pane.responseBuffer),
        'completed_at': completedAt.toIso8601String(),
        if (elapsed != null) 'elapsed_ms': elapsed.inMilliseconds,
      },
      if (ollamaPayload != null) 'ollama': ollamaPayload,
      'derived': {
        if (ollamaPayload?['total_duration'] != null)
          'total_duration_ms':
              _nanosecondsToMs(ollamaPayload!['total_duration']),
        if (ollamaPayload?['load_duration'] != null)
          'load_duration_ms': _nanosecondsToMs(ollamaPayload!['load_duration']),
        if (ollamaPayload?['prompt_eval_duration'] != null)
          'prompt_eval_duration_ms':
              _nanosecondsToMs(ollamaPayload!['prompt_eval_duration']),
        if (ollamaPayload?['eval_duration'] != null)
          'eval_duration_ms': _nanosecondsToMs(ollamaPayload!['eval_duration']),
        if (tokensPerSecond != null)
          'tokens_per_second': tokensPerSecond.toStringAsFixed(2),
      },
    };
  }

  List<Map<String, dynamic>> _attachmentDetails(List<String> attachments) {
    return attachments.map((path) {
      final file = File(path);
      int? size;
      try {
        if (file.existsSync()) {
          size = file.lengthSync();
        }
      } catch (_) {
        size = null;
      }

      return {
        'name': FileAttachmentHelper.getFileName(path),
        'extension': FileAttachmentHelper.extensionForPath(path),
        'path': path,
        if (size != null) 'bytes': size,
      };
    }).toList();
  }

  int _estimateTokens(String text) {
    if (text.trim().isEmpty) return 0;
    return (text.trim().split(RegExp(r'\s+')).length * 1.35).ceil();
  }

  num? _asNum(dynamic value) => value is num ? value : null;

  num? _nanosecondsToMs(dynamic value) {
    final number = _asNum(value);
    return number == null ? null : number / 1000000;
  }

  String _titleFromMessage(ChatMessage message) {
    final source =
        message.text.trim().isEmpty ? 'Attachment chat' : message.text.trim();
    return source.length > 34 ? '${source.substring(0, 34)}...' : source;
  }

  Set<int> _generatingConversationIndices() {
    return {
      if (_leftPane.isGenerating && _leftPane.conversationIndex != null)
        _leftPane.conversationIndex!,
      if (_rightPane.isGenerating && _rightPane.conversationIndex != null)
        _rightPane.conversationIndex!,
    };
  }

  void _showSnackBar(String message, {int duration = 3}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: duration),
      ),
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
            onExitMiniMode: _onExitMiniMode,
          );
        }

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: SelectionArea(
            child: Row(
              children: [
                Sidebar(
                  isDarkMode: widget.isDarkMode,
                  isPanelVisible: provider.isSidebarVisible,
                  conversations: provider.conversations,
                  selectedConversationIndex: _leftPane.conversationIndex,
                  generatingConversationIndex: null,
                  generatingConversationIndices:
                      _generatingConversationIndices(),
                  onNewChat: () => _startNewConversation(side: _PaneSide.left),
                  onLoadConversation: (index) =>
                      _loadConversation(index, side: _PaneSide.left),
                  onDeleteConversation: _deleteConversation,
                  onTogglePinConversation: _toggleConversationPin,
                  onExportConversation: _exportConversation,
                  onExportAll: _exportAllConversations,
                  onToggleTheme: widget.toggleTheme,
                  onToggleSidebar: _toggleSidebar,
                  onClearAllConversations: _clearAllConversations,
                  onEnableSplitMode: _enableSplitMode,
                  isSplitMode: _isSplitMode,
                  selectedModel:
                      _leftPane.selectedModel ?? provider.selectedModel,
                  selectedModelListenable: _leftPane.selectedModelListenable,
                  availableModels: _availableModels,
                  onModelChanged: (model) =>
                      _setPaneModel(_PaneSide.left, model),
                  onSettingsTap: _showSettingsDialog,
                  onMiniModeTap: _toggleMiniMode,
                  onToggleAlwaysOnTop: _toggleAlwaysOnTop,
                  onRefreshModels: _fetchAvailableModels,
                  isAlwaysOnTop: _isAlwaysOnTop,
                ),
                Expanded(
                  child: Stack(
                    children: [
                      _isSplitMode
                          ? _buildSplitLayout()
                          : _buildSingleLayout(provider),
                      _buildEdgeDropTarget(_PaneSide.left),
                      _buildEdgeDropTarget(_PaneSide.right),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSingleLayout(ChatProvider provider) {
    return Column(
      children: [
        ChatHeader(
          onSearchChanged: _setChatSearchQuery,
          isDarkMode: widget.isDarkMode,
          selectedModel: _leftPane.selectedModel ?? provider.selectedModel,
          selectedModelListenable: _leftPane.selectedModelListenable,
          availableModels: _availableModels,
          isAlwaysOnTop: _isAlwaysOnTop,
          onModelChanged: (model) => _setPaneModel(_PaneSide.left, model),
          onSettingsTap: _showSettingsDialog,
          onMiniModeTap: _toggleMiniMode,
          onToggleAlwaysOnTop: _toggleAlwaysOnTop,
          onRefreshModels: _fetchAvailableModels,
          onSearchNext: _goToNextSearchMatch,
          onSearchPrevious: _goToPreviousSearchMatch,
          onClearSearch: _clearChatSearch,
          searchQuery: _chatSearchQuery,
          searchMatchCount: _chatSearchMatches.length,
          searchActiveIndex: _chatSearchCursor,
        ),
        Expanded(child: _buildChatPane(_PaneSide.left, showPaneHeader: false)),
      ],
    );
  }

  Widget _buildSplitLayout() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const dividerWidth = 8.0;
        final availableWidth = constraints.maxWidth - dividerWidth;
        final leftWidth = availableWidth * _splitRatio;
        final rightWidth = availableWidth * (1 - _splitRatio);

        return Row(
          children: [
            SizedBox(
              width: leftWidth,
              child: _buildChatPane(_PaneSide.left, showPaneHeader: true),
            ),
            MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                onHorizontalDragUpdate: (details) {
                  setState(() {
                    _splitRatio =
                        ((_splitRatio * availableWidth + details.delta.dx) /
                                availableWidth)
                            .clamp(0.25, 0.75);
                  });
                },
                child: Container(
                  width: dividerWidth,
                  color: AppColors.line,
                  child: Center(
                    child: Container(
                      width: 2,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.teal,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: rightWidth,
              child: _buildChatPane(_PaneSide.right, showPaneHeader: true),
            ),
          ],
        );
      },
    );
  }

  Widget _buildChatPane(_PaneSide side, {required bool showPaneHeader}) {
    final pane = _pane(side);
    final imagePaths = _imagePreviewPaths(pane);

    return Column(
      children: [
        if (showPaneHeader) _buildPaneHeader(side),
        if (imagePaths.isNotEmpty && !_isSplitMode)
          _buildMediaPreviewStrip(imagePaths),
        Expanded(
          child: pane.messages.isEmpty
              ? const EmptyChatPlaceholder()
              : ListView.builder(
                  controller: pane.scrollController,
                  padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
                  itemCount: pane.messages.length + (pane.isGenerating ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (pane.isGenerating && index == pane.messages.length) {
                      return TypingIndicator(
                        isDarkMode: widget.isDarkMode,
                        modelName: pane.selectedModel,
                      );
                    }

                    final message = pane.messages[index];
                    final audioMessageKey =
                        '${side.name}-${message.timestamp.microsecondsSinceEpoch}';
                    final searchQuery =
                        side == _PaneSide.left ? _chatSearchQuery.trim() : '';
                    final isSearchMatch = _messageMatchesSearch(
                      message,
                      searchQuery,
                    );
                    final activeMessageIndex = _chatSearchMatches.isEmpty
                        ? -1
                        : _chatSearchMatches[_chatSearchCursor];
                    return MessageBubble(
                      key: ValueKey(
                        '${pane.side.name}-$index-${message.timestamp.microsecondsSinceEpoch}-${message.isUser}',
                      ),
                      message: message,
                      useFullWidth: _isSplitMode,
                      isDarkMode: widget.isDarkMode,
                      searchQuery: isSearchMatch ? searchQuery : '',
                      isActiveSearchMatch:
                          side == _PaneSide.left && index == activeMessageIndex,
                      onEdit: message.isUser
                          ? (text) => _editMessage(index, side, text)
                          : null,
                      onRegenerate: !message.isUser &&
                              index == pane.messages.length - 1 &&
                              !pane.isGenerating
                          ? () => _regenerateLastResponse(side)
                          : null,
                      onSpeak: !message.isUser && !pane.isGenerating
                          ? () => _speakMessage(message.text, audioMessageKey)
                          : null,
                      onDownload: !message.isUser && !pane.isGenerating
                          ? (format) {
                              if (format == MessageDownloadFormat.audio) {
                                _downloadMessageAudio(
                                  message.text,
                                  audioMessageKey,
                                );
                              } else {
                                _downloadMessagePdf(message, audioMessageKey);
                              }
                            }
                          : null,
                      isAudioProcessing:
                          _audioProcessingMessageKey == audioMessageKey,
                      audioStatus: _audioProcessingMessageKey == audioMessageKey
                          ? 'Generating audio…'
                          : _audioReadyMessageKey == audioMessageKey
                              ? _audioReadyStatus
                              : null,
                      isPdfExporting:
                          _pdfExportingMessageKey == audioMessageKey,
                      pdfStatus: _pdfExportingMessageKey == audioMessageKey
                          ? _pdfExportStatus
                          : null,
                      isActiveAudio: _activeAudioMessageKey == audioMessageKey,
                      isActiveAudioPlaying: _isActiveAudioPlaying,
                      audioPosition: _activeAudioPosition,
                      audioDuration: _activeAudioDuration,
                      onSeekAudio: (position) =>
                          _seekAudio(audioMessageKey, position),
                    );
                  },
                ),
        ),
        ChatInputArea(
          controller: pane.controller,
          isDarkMode: widget.isDarkMode,
          isGenerating: pane.isGenerating,
          attachedFiles: pane.attachedFiles,
          onSendMessage: () {
            _sendMessage(side);
          },
          onStopGeneration: () => _stopGeneration(side),
          onPickFiles: () => _pickFiles(side: side),
          onRemoveFile: (index) => _removeAttachedFile(index, side: side),
          selectedAction: pane.selectedAction,
          onActionSelected: (action) {
            if (pane.isGenerating) return;
            final provider = context.read<ChatProvider>();
            if (!provider.enableToolCalling) {
              _showSnackBar(
                  'Enable native tools in Settings to use action tags.');
              return;
            }
            setState(() {
              pane.selectedAction =
                  pane.selectedAction == action ? null : action;
            });
          },
        ),
      ],
    );
  }

  bool _messageMatchesSearch(ChatMessage message, String query) {
    if (query.isEmpty) return false;
    final needle = query.toLowerCase();
    return [message.text, message.thinkingText ?? '']
        .any((text) => text.toLowerCase().contains(needle));
  }

  List<String> _imagePreviewPaths(_ChatPaneRuntime pane) {
    final paths = <String>[];

    for (final file in pane.attachedFiles) {
      final extension = FileAttachmentHelper.extensionForPath(file.path);
      if (FileAttachmentHelper.supportedImageExtensions.contains(extension)) {
        paths.add(file.path);
      }
    }

    for (final message in pane.messages.reversed) {
      final attachments = message.attachedFiles;
      if (attachments == null) continue;

      for (final path in attachments) {
        final extension = FileAttachmentHelper.extensionForPath(path);
        if (FileAttachmentHelper.supportedImageExtensions.contains(extension)) {
          paths.add(path);
        }
      }

      if (paths.length >= 4) break;
    }

    return paths.take(4).toList();
  }

  Widget _buildMediaPreviewStrip(List<String> imagePaths) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      height: 198,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 26,
            child: Row(
              children: [
                _PreviewChip(
                  icon: Icons.image_search_rounded,
                  label: '${imagePaths.length} uploaded',
                  accent: AppColors.orange,
                ),
                const SizedBox(width: 7),
                const _PreviewChip(
                  icon: Icons.open_in_full_rounded,
                  label: '1024x1024px',
                  accent: AppColors.teal,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    imagePaths.map(FileAttachmentHelper.getFileName).join(', '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Icon(Icons.thumb_up_alt_outlined,
                    size: 16, color: AppColors.muted),
                const SizedBox(width: 14),
                const Icon(Icons.thumb_down_alt_outlined,
                    size: 16, color: AppColors.muted),
                const SizedBox(width: 14),
                const Icon(Icons.volume_up_outlined,
                    size: 16, color: AppColors.muted),
                const SizedBox(width: 14),
                const Icon(Icons.refresh_rounded,
                    size: 16, color: AppColors.muted),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Row(
              children: imagePaths
                  .map(
                    (path) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 7),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(path),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: Colors.white,
                                child: const Icon(
                                  Icons.broken_image_outlined,
                                  color: AppColors.orange,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaneHeader(_PaneSide side) {
    final pane = _pane(side);
    final provider = context.read<ChatProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final title = pane.conversationIndex != null &&
            pane.conversationIndex! < provider.conversations.length
        ? provider.conversations[pane.conversationIndex!].title
        : 'New chat';

    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Icon(
            side == _PaneSide.left
                ? Icons.looks_one_rounded
                : Icons.looks_two_rounded,
            size: 20,
            color: AppColors.orange,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 210,
            child: ValueListenableBuilder<String?>(
              valueListenable: pane.selectedModelListenable,
              builder: (context, selectedModel, child) => ModelPickerButton(
                selectedModel: selectedModel,
                models: _availableModels,
                enabled: !pane.isGenerating,
                foregroundColor: colorScheme.onSurface,
                backgroundColor: Colors.transparent,
                onSelected: (model) => _setPaneModel(side, model),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _buildGenerationStatus(pane),
          if (side == _PaneSide.left) ...[
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _fetchAvailableModels,
              tooltip: 'Refresh models',
            ),
            IconButton(
              icon: const Icon(Icons.tune_rounded),
              onPressed: _showSettingsDialog,
              tooltip: 'Settings',
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.swap_horiz_rounded),
              onPressed: _swapPanes,
              tooltip: 'Swap panes',
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: _disableSplitMode,
              tooltip: 'Close split',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGenerationStatus(_ChatPaneRuntime pane) {
    if (!pane.isGenerating) {
      final lastAssistant = _lastAssistantMessage(pane);
      final details = lastAssistant?.details;
      final tps = details?['derived'] is Map
          ? (details!['derived'] as Map)['tokens_per_second']
          : null;

      if (tps == null) return const SizedBox.shrink();

      return Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Chip(
          label: Text('$tps tok/s'),
          visualDensity: VisualDensity.compact,
        ),
      );
    }

    final elapsed = pane.generationStartedAt == null
        ? Duration.zero
        : DateTime.now().difference(pane.generationStartedAt!);
    final seconds = elapsed.inSeconds;

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Chip(
        avatar: const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        label: Text('${seconds}s / ${pane.responseBuffer.length} chars'),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  ChatMessage? _lastAssistantMessage(_ChatPaneRuntime pane) {
    for (var i = pane.messages.length - 1; i >= 0; i--) {
      if (!pane.messages[i].isUser) return pane.messages[i];
    }
    return null;
  }

  Widget _buildEdgeDropTarget(_PaneSide side) {
    final isLeft = side == _PaneSide.left;

    return Positioned(
      top: 0,
      bottom: 0,
      left: isLeft ? 0 : null,
      right: isLeft ? null : 0,
      width: 72,
      child: DragTarget<int>(
        onWillAcceptWithDetails: (details) => true,
        onAcceptWithDetails: (details) =>
            _dropConversationOnPane(details.data, side),
        builder: (context, candidates, rejected) {
          final active = candidates.isNotEmpty;
          return IgnorePointer(
            ignoring: !active,
            child: AnimatedOpacity(
              opacity: active ? 1 : 0,
              duration: const Duration(milliseconds: 120),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: 0.82),
                  border: Border(
                    left: isLeft
                        ? BorderSide.none
                        : const BorderSide(color: AppColors.orange, width: 2),
                    right: isLeft
                        ? const BorderSide(color: AppColors.orange, width: 2)
                        : BorderSide.none,
                  ),
                ),
                child: Center(
                  child: RotatedBox(
                    quarterTurns: isLeft ? 3 : 1,
                    child: Text(
                      isLeft ? 'Drop left' : 'Drop right',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
