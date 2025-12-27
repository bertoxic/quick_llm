import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../models/conversation.dart';
import '../provider/ChatProvider.dart';
import '../services/storage_service.dart';

/// Manages all conversation-related operations
class ConversationManager {
  final StorageService _storageService;

  ConversationManager(this._storageService);

  /// Create or update conversation with new message
  void createOrUpdate(ChatMessage userMessage, ChatProvider provider) {
    if (provider.selectedConversationIndex == null && provider.messages.length >= 1) {
      _createNewConversation(userMessage, provider);
    } else if (provider.selectedConversationIndex != null) {
      _updateExistingConversation(provider);
    }
  }

  void _createNewConversation(ChatMessage userMessage, ChatProvider provider) {
    final newConversation = Conversation(
      title: userMessage.text.length > 30
          ? '${userMessage.text.substring(0, 30)}...'
          : userMessage.text,
      messages: List.from(provider.messages),
      timestamp: DateTime.now(),
    );

    provider.addConversation(newConversation);
    provider.selectConversation(0);
    save(provider);
    debugPrint('💾 Created new conversation');
  }

  void _updateExistingConversation(ChatProvider provider) {
    final index = provider.selectedConversationIndex!;
    final currentConv = provider.conversations[index];

    provider.updateConversation(
      index,
      Conversation(
        title: currentConv.title,
        messages: List.from(provider.messages),
        timestamp: currentConv.timestamp,
      ),
    );
    save(provider);
    debugPrint('💾 Updated existing conversation');
  }

  /// Save conversation at specific index
  void saveAtIndex(ChatProvider provider, int? index) {
    if (index != null && index < provider.conversations.length) {
      final currentConv = provider.conversations[index];

      provider.updateConversation(
        index,
        Conversation(
          title: currentConv.title,
          messages: currentConv.messages,
          timestamp: currentConv.timestamp,
        ),
      );
      save(provider);
      debugPrint('💾 Saved conversation state at index $index');
    }
  }

  /// Save all conversations
  Future<void> save(ChatProvider provider) async {
    await _storageService.saveConversations(provider.conversations);
  }

  /// Load all conversations
  Future<List<Conversation>> load() async {
    return await _storageService.loadConversations();
  }

  /// Export single conversation
  Future<String> exportConversation(Conversation conv) async {
    return await _storageService.exportConversation(conv);
  }

  /// Export all conversations
  Future<String> exportAll(List<Conversation> conversations) async {
    return await _storageService.exportAllConversations(conversations);
  }
}