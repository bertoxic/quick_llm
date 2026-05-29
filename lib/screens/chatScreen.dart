import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../dialogs/settings_dialog.dart';
import '../models/chat_message.dart';
import '../models/conversation.dart';
import '../provider/ChatProvider.dart';
import '../services/ollama_service.dart';
import '../services/storage_service.dart';
import '../utils/conversation_manager.dart';
import '../utils/helpers.dart';
import '../utils/thinking_parser.dart';
import '../widgets/chat_header.dart';
import '../widgets/message_bubble.dart';
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
  final OllamaService ollamaService = OllamaService();
  final List<File> attachedFiles = [];

  int? conversationIndex;
  String? selectedModel;
  List<ChatMessage> messages = [];
  bool isGenerating = false;
  bool isSending = false;
  DateTime? generationStartedAt;
  String responseBuffer = '';
  String thinkingBuffer = '';
  Map<String, dynamic>? activeRequestDetails;

  void dispose() {
    controller.dispose();
    scrollHelper.dispose();
    ollamaService.dispose();
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

  bool _isAlwaysOnTop = false;
  bool _isMiniMode = false;
  bool _isSplitMode = false;
  bool _copyFileAttachments = true;
  double _splitRatio = 0.5;
  List<String> _availableModels = [];
  Timer? _statsTimer;

  @override
  void initState() {
    super.initState();
    _conversationManager = ConversationManager(_storageService);
    _fileAttachmentHelper = FileAttachmentHelper(_storageService);
    _leftPane = _ChatPaneRuntime(_PaneSide.left);
    _rightPane = _ChatPaneRuntime(_PaneSide.right);

    windowManager.addListener(this);
    _setupScrollListeners();
    _initializeApp();
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    windowManager.removeListener(this);
    _leftPane.dispose();
    _rightPane.dispose();
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
    );

    _systemPromptController.text = provider.systemPrompt;
    setState(() {
      _copyFileAttachments = prefs['copyFileAttachments'] ?? true;
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
      'monitorClipboard': false,
      'copyFileAttachments': _copyFileAttachments,
    });
  }

  Future<void> _fetchAvailableModels() async {
    final models = await OllamaService().fetchAvailableModels();
    if (!mounted) return;

    final provider = context.read<ChatProvider>();
    setState(() {
      _availableModels = models;
    });

    if (models.isEmpty) {
      provider.setSelectedModel(null);
      _leftPane.selectedModel = null;
      _rightPane.selectedModel = null;
      _showSnackBar('No Ollama models found. Pull a model first.', duration: 5);
      return;
    }

    final current = provider.selectedModel != null &&
            models.contains(provider.selectedModel)
        ? provider.selectedModel!
        : models.first;

    provider.setSelectedModel(current);
    _leftPane.selectedModel ??= current;
    _rightPane.selectedModel ??= current;
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
    final messageText = (message ?? pane.controller.text).trim();

    if (selectedModel == null || selectedModel.isEmpty) {
      _showSnackBar('No model selected. Select a model first.');
      return;
    }

    if ((messageText.isEmpty && pane.attachedFiles.isEmpty) ||
        pane.isGenerating ||
        pane.isSending) {
      return;
    }

    ChatMessage userMessage;
    if (regenerate) {
      userMessage = pane.messages.lastWhere((msg) => msg.isUser);
    } else {
      final attachmentPaths =
          pane.attachedFiles.map((file) => file.path).toList();
      userMessage = ChatMessage(
        text: messageText,
        isUser: true,
        timestamp: DateTime.now(),
        attachedFiles: attachmentPaths.isNotEmpty ? attachmentPaths : null,
        details: _buildUserMessageDetails(messageText, attachmentPaths),
      );

      setState(() {
        pane.messages.add(userMessage);
        pane.controller.clear();
        pane.attachedFiles.clear();
      });
    }

    await _ensureConversationForPane(pane, provider);

    final fileTypes =
        FileAttachmentHelper.separateFileTypes(userMessage.attachedFiles);
    final contextMessages = ChatMessageBuilder.extractContextMessages([
      ...pane.messages,
      ChatMessage(text: '', isUser: false, timestamp: DateTime.now()),
    ]);
    final requestDetails = _buildRequestDetails(
      pane: pane,
      provider: provider,
      model: selectedModel,
      prompt: userMessage.text,
      contextMessages: contextMessages,
      attachments: userMessage.attachedFiles ?? const [],
      fileTypes: fileTypes,
    );

    final assistantMessage = ChatMessage(
      text: '',
      isUser: false,
      timestamp: DateTime.now(),
      modelName: selectedModel,
      details: {
        'status': 'generating',
        'request': requestDetails,
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
      currentMessageText: userMessage.text,
    );

    Map<String, dynamic>? finalOllamaPayload;

    try {
      await for (final event in pane.ollamaService.generateChatResponse(
        model: selectedModel,
        prompt: userMessage.text,
        messagesArray: messagesArray,
        systemPrompt: provider.useSystemPrompt ? provider.systemPrompt : null,
        temperature: provider.temperature,
        maxTokens: provider.maxTokens,
        numCtx: provider.numCtx,
        images: fileTypes.images,
        documents: fileTypes.documents,
        audio: fileTypes.audio,
        videos: fileTypes.videos,
        otherFiles: fileTypes.otherFiles,
        requestMetadata: requestDetails,
      )) {
        if (!mounted) break;

        if (event.isThinking) {
          pane.thinkingBuffer += event.delta;
          _updateStreamingAssistant(pane, provider);
        } else if (event.isContent) {
          pane.responseBuffer += event.delta;
          _updateStreamingAssistant(pane, provider);
        } else if (event.isDone) {
          finalOllamaPayload = event.raw;
        } else if (event.isError) {
          pane.responseBuffer = event.delta;
          _updateStreamingAssistant(
            pane,
            provider,
            detailsOverride: {
              'status': 'error',
              'request': requestDetails,
              'error': event.delta,
              if (event.raw != null) 'ollama': event.raw,
            },
          );
        }
      }
    } finally {
      if (!mounted) return;

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

    setState(() {});
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

  void _regenerateLastResponse(_PaneSide side) {
    final pane = _pane(side);
    if (pane.messages.length < 2 || pane.isGenerating) return;
    if (pane.messages.last.isUser) return;

    setState(() {
      pane.messages.removeLast();
    });

    final provider = context.read<ChatProvider>();
    _syncLeftPaneToProviderIfNeeded(pane, provider);
    unawaited(_persistPane(pane, provider));
    _sendMessage(side, regenerate: true);
  }

  void _editMessage(int index, _PaneSide side) {
    final pane = _pane(side);
    if (index < 0 || index >= pane.messages.length || pane.isGenerating) return;

    final provider = context.read<ChatProvider>();
    final message = pane.messages[index];

    setState(() {
      pane.controller.text = message.text;
      pane.messages = pane.messages.sublist(0, index);
    });

    _syncLeftPaneToProviderIfNeeded(pane, provider);
    unawaited(_persistPane(pane, provider));
  }

  void _stopGeneration(_PaneSide side) {
    final pane = _pane(side);
    if (!pane.isGenerating) return;

    pane.ollamaService.cancelGeneration();
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

    setState(() {
      pane.selectedModel = model;
    });

    if (side == _PaneSide.left) {
      provider.setSelectedModel(model);
    }
  }

  void _showSettingsDialog() {
    final provider = context.read<ChatProvider>();

    showDialog(
      context: context,
      builder: (context) => SettingsDialog(
        systemPromptController: _systemPromptController,
        useSystemPrompt: provider.useSystemPrompt,
        temperature: provider.temperature,
        maxTokens: provider.maxTokens,
        numCtx: provider.numCtx,
        onNumCtxChanged: provider.setNumCtx,
        onUseSystemPromptChanged: provider.setUseSystemPrompt,
        onTemperatureChanged: provider.setTemperature,
        onMaxTokensChanged: provider.setMaxTokens,
        onSave: () {
          provider.setSystemPrompt(_systemPromptController.text);
          _savePreferences();
        },
        isDarkMode: widget.isDarkMode,
      ),
    );
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
    required List<ChatMessage> contextMessages,
    required List<String> attachments,
    required ({
      List<String>? images,
      List<String>? documents,
      List<String>? audio,
      List<String>? videos,
      List<String>? otherFiles,
    }) fileTypes,
  }) {
    return {
      'pane': pane.side.name,
      'conversation_index': pane.conversationIndex,
      'model': model,
      'prompt': {
        'characters': prompt.length,
        'estimated_tokens': _estimateTokens(prompt),
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
          body: Row(
            children: [
              if (provider.isSidebarVisible)
                Sidebar(
                  isDarkMode: widget.isDarkMode,
                  conversations: provider.conversations,
                  selectedConversationIndex: _leftPane.conversationIndex,
                  generatingConversationIndex: null,
                  generatingConversationIndices:
                      _generatingConversationIndices(),
                  onNewChat: () => _startNewConversation(side: _PaneSide.left),
                  onLoadConversation: (index) =>
                      _loadConversation(index, side: _PaneSide.left),
                  onDeleteConversation: _deleteConversation,
                  onExportConversation: _exportConversation,
                  onExportAll: _exportAllConversations,
                  onToggleTheme: widget.toggleTheme,
                  onClearAllConversations: _clearAllConversations,
                  onEnableSplitMode: _enableSplitMode,
                  isSplitMode: _isSplitMode,
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
        );
      },
    );
  }

  Widget _buildSingleLayout(ChatProvider provider) {
    return Column(
      children: [
        ChatHeader(
          isDarkMode: widget.isDarkMode,
          isSidebarVisible: provider.isSidebarVisible,
          selectedModel: _leftPane.selectedModel ?? provider.selectedModel,
          availableModels: _availableModels,
          isAlwaysOnTop: _isAlwaysOnTop,
          onToggleSidebar: _toggleSidebar,
          onModelChanged: (model) => _setPaneModel(_PaneSide.left, model),
          onSettingsTap: _showSettingsDialog,
          onMiniModeTap: _toggleMiniMode,
          onToggleAlwaysOnTop: _toggleAlwaysOnTop,
          onRefreshModels: _fetchAvailableModels,
        ),
        Expanded(child: _buildChatPane(_PaneSide.left, showPaneHeader: false)),
      ],
    );
  }

  Widget _buildSplitLayout() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final dividerWidth = 8.0;
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
                  color: Theme.of(context).colorScheme.outlineVariant,
                  child: Center(
                    child: Container(
                      width: 2,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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

    return Column(
      children: [
        if (showPaneHeader) _buildPaneHeader(side),
        Expanded(
          child: pane.messages.isEmpty
              ? const EmptyChatPlaceholder()
              : ListView.builder(
                  controller: pane.scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: pane.messages.length + (pane.isGenerating ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (pane.isGenerating && index == pane.messages.length) {
                      return TypingIndicator(
                        isDarkMode: widget.isDarkMode,
                        modelName: pane.selectedModel,
                      );
                    }

                    final message = pane.messages[index];
                    return MessageBubble(
                      message: message,
                      useFullWidth: _isSplitMode,
                      isDarkMode: widget.isDarkMode,
                      onEdit: message.isUser
                          ? () => _editMessage(index, side)
                          : null,
                      onRegenerate: !message.isUser &&
                              index == pane.messages.length - 1 &&
                              !pane.isGenerating
                          ? () => _regenerateLastResponse(side)
                          : null,
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
        ),
      ],
    );
  }

  Widget _buildPaneHeader(_PaneSide side) {
    final pane = _pane(side);
    final provider = context.read<ChatProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final title = pane.conversationIndex != null &&
            pane.conversationIndex! < provider.conversations.length
        ? provider.conversations[pane.conversationIndex!].title
        : 'New chat';

    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          if (side == _PaneSide.left)
            IconButton(
              icon: const Icon(Icons.menu_rounded),
              onPressed: _toggleSidebar,
              tooltip: 'Sidebar',
            ),
          Icon(
            side == _PaneSide.left
                ? Icons.looks_one_rounded
                : Icons.looks_two_rounded,
            size: 20,
            color: colorScheme.primary,
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
            child: DropdownButton<String>(
              value: pane.selectedModel,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              items: _availableModels
                  .map((model) => DropdownMenuItem(
                        value: model,
                        child: Text(model, overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: pane.isGenerating
                  ? null
                  : (model) {
                      if (model != null) _setPaneModel(side, model);
                    },
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
    final colorScheme = Theme.of(context).colorScheme;
    final isLeft = side == _PaneSide.left;

    return Positioned(
      top: 0,
      bottom: 0,
      left: isLeft ? 0 : null,
      right: isLeft ? null : 0,
      width: 72,
      child: DragTarget<int>(
        onWillAccept: (index) => index != null,
        onAccept: (index) => _dropConversationOnPane(index, side),
        builder: (context, candidates, rejected) {
          final active = candidates.isNotEmpty;
          return IgnorePointer(
            ignoring: !active,
            child: AnimatedOpacity(
              opacity: active ? 1 : 0,
              duration: const Duration(milliseconds: 120),
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withOpacity(0.82),
                  border: Border(
                    left: isLeft
                        ? BorderSide.none
                        : BorderSide(color: colorScheme.primary, width: 2),
                    right: isLeft
                        ? BorderSide(color: colorScheme.primary, width: 2)
                        : BorderSide.none,
                  ),
                ),
                child: Center(
                  child: RotatedBox(
                    quarterTurns: isLeft ? 3 : 1,
                    child: Text(
                      isLeft ? 'Drop left' : 'Drop right',
                      style: TextStyle(
                        color: colorScheme.onPrimaryContainer,
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
