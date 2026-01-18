import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../models/conversation.dart';
import '../services/ollama_service.dart';

/// Provider class to manage shared chat state across the app
class ChatProvider with ChangeNotifier {
  // OllamaService instance
  final OllamaService ollamaService = OllamaService();

  // Messages and conversations
  List<ChatMessage> _messages = [];
  List<Conversation> _conversations = [];
  int? _selectedConversationIndex;
  bool _isSending = false;
  bool get isSending => _isSending;
  int _numCtx = 32768;

  // Callback for when conversation indices might shift
  Function()? onConversationIndicesChanged;

  void setIsSending(bool value) {
    _isSending = value;
    notifyListeners();
  }

  // Generation state
  bool _isGenerating = false;
  int? _generatingConversationIndex;
  String _streamingResponse = '';

  // Settings
  String? _selectedModel;
  double _temperature = 0.7;
  int _maxTokens = 256000;
  String _systemPrompt = '';
  bool _useSystemPrompt = false;
  bool _isDarkMode = true;
  bool _isSidebarVisible = true;

  // Getters
  List<ChatMessage> get messages => _messages;
  List<Conversation> get conversations => _conversations;
  int? get selectedConversationIndex => _selectedConversationIndex;
  bool get isGenerating => _isGenerating;
  int? get generatingConversationIndex => _generatingConversationIndex;
  String get streamingResponse => _streamingResponse;
  String? get selectedModel => _selectedModel;
  double get temperature => _temperature;
  int get maxTokens => _maxTokens;
  String get systemPrompt => _systemPrompt;
  bool get useSystemPrompt => _useSystemPrompt;
  bool get isDarkMode => _isDarkMode;
  bool get isSidebarVisible => _isSidebarVisible;
  bool get hasValidModel => _selectedModel != null && _selectedModel!.isNotEmpty;

  // Message operations
  void addMessage(ChatMessage message) {
    _messages.add(message);
    notifyListeners();
  }

  void updateLastMessage(ChatMessage message) {
    if (_messages.isNotEmpty) {
      _messages[_messages.length - 1] = message;
      notifyListeners();
    }
  }

  void removeLastMessage() {
    if (_messages.isNotEmpty) {
      _messages.removeLast();
      notifyListeners();
    }
  }

  void clearMessages() {
    _messages.clear();
    notifyListeners();
  }
  void setNumCtx(int value) {
    _numCtx = value;
    print('✅ Context window updated: $_numCtx tokens');
    notifyListeners();
  }

  int get nu => _numCtx;

  void setMessages(List<ChatMessage> messages) {
    _messages = List.from(messages);
    notifyListeners();
  }

  void removeMessagesFromIndex(int index) {
    if (index >= 0 && index < _messages.length) {
      _messages.removeRange(index, _messages.length);
      notifyListeners();
    }
  }

  // Conversation operations
  void setConversations(List<Conversation> conversations) {
    _conversations = conversations;
    notifyListeners();
  }

  void addConversation(Conversation conversation) {
    _conversations.insert(0, conversation);
    // Notify that indices have shifted
    onConversationIndicesChanged?.call();
    notifyListeners();
  }

  void updateConversation(int index, Conversation conversation) {
    if (index >= 0 && index < _conversations.length) {
      _conversations[index] = conversation;
      notifyListeners();
    }
  }

  void deleteConversation(int index) {
    if (index >= 0 && index < _conversations.length) {
      _conversations.removeAt(index);
      if (_selectedConversationIndex == index) {
        _selectedConversationIndex = null;
        clearMessages();
      } else if (_selectedConversationIndex != null && _selectedConversationIndex! > index) {
        _selectedConversationIndex = _selectedConversationIndex! - 1;
      }
      // Notify that indices have shifted
      onConversationIndicesChanged?.call();
      notifyListeners();
    }
  }

  void selectConversation(int? index) {
    _selectedConversationIndex = index;
    notifyListeners();
  }

  // Generation state management
  void startGenerating() {
    _isGenerating = true;
    _generatingConversationIndex = _selectedConversationIndex;
    _streamingResponse = '';
    notifyListeners();
  }

  void stopGenerating() {
    _isGenerating = false;
    _generatingConversationIndex = null;
    notifyListeners();
  }

  void updateStreamingResponse(String response) {
    _streamingResponse = response;
    // Don't notify listeners here to avoid excessive rebuilds
    // This will be handled by debounced UI updates
  }

  void clearStreamingResponse() {
    _streamingResponse = '';
    notifyListeners();
  }

  // Settings management
  void setSelectedModel(String? model) {
    _selectedModel = model;
    notifyListeners();
  }

  void setTemperature(double temp) {
    _temperature = temp;
    notifyListeners();
  }

  void setMaxTokens(int tokens) {
    _maxTokens = tokens;
    notifyListeners();
  }

  void setSystemPrompt(String prompt) {
    _systemPrompt = prompt;
    notifyListeners();
  }

  void setUseSystemPrompt(bool use) {
    _useSystemPrompt = use;
    notifyListeners();
  }

  void toggleDarkMode() {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
  }

  void setDarkMode(bool isDark) {
    _isDarkMode = isDark;
    notifyListeners();
  }

  void toggleSidebar() {
    _isSidebarVisible = !_isSidebarVisible;
    notifyListeners();
  }

  void setSidebarVisible(bool visible) {
    _isSidebarVisible = visible;
    notifyListeners();
  }

  // Bulk settings update (for loading from storage)
  void updateSettings({
    String? model,
    double? temperature,
    int? maxTokens,
    String? systemPrompt,
    bool? useSystemPrompt,
    bool? isDarkMode,
    bool? isSidebarVisible,
  }) {
    if (model != null) _selectedModel = model;
    if (temperature != null) _temperature = temperature;
    if (maxTokens != null) _maxTokens = maxTokens;
    if (systemPrompt != null) _systemPrompt = systemPrompt;
    if (useSystemPrompt != null) _useSystemPrompt = useSystemPrompt;
    if (isDarkMode != null) _isDarkMode = isDarkMode;
    if (isSidebarVisible != null) _isSidebarVisible = isSidebarVisible;
    notifyListeners();
  }

  // Cleanup when provider is disposed
  @override
  void dispose() {
    ollamaService.dispose();
    super.dispose();
  }
}