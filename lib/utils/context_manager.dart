import 'package:flutter/material.dart';
import '../models/chat_message.dart';

class ContextManager {
  /// Estimate tokens (rough approximation: 1 token ≈ 4 characters)
  static int estimateTokens(String text) {
    return (text.length / 4).ceil();
  }

  /// Get context-aware message history
  ///
  /// Strategies:
  /// - 'sliding_window': Keep last N messages
  /// - 'token_based': Fit as many messages as possible within token budget
  /// - 'hybrid': Keep first message + recent messages (recommended)
  /// - 'smart': Prioritize important messages (first, last N, and long messages)
  ///
  /// CRITICAL: The last N messages (recentMessagesToProtect) are ALWAYS included completely,
  /// even if they exceed token budget. Older messages are truncated to fit.
  ///
  /// Recommended usage:
  /// - For ongoing conversations: recentMessagesToProtect = 2-4 (includes current exchange)
  /// - For long conversations: recentMessagesToProtect = 5-10 (more context)
  static String buildContextHistory({
    required List<ChatMessage> messages,
    required int maxContextTokens,
    String strategy = 'smart',
    bool includeCurrentMessage = false,
    int recentMessagesToProtect = 4, // Always include last 4 messages completely (2 exchanges)
  }) {
    if (messages.isEmpty) return '';

    // Determine which messages to process
    final messagesToProcess = includeCurrentMessage
        ? messages
        : messages.sublist(0, messages.length - 1);

    if (messagesToProcess.isEmpty) return '';

    switch (strategy) {
      case 'sliding_window':
        return _buildSlidingWindow(messagesToProcess, maxContextTokens, recentMessagesToProtect);
      case 'token_based':
        return _buildTokenBased(messagesToProcess, maxContextTokens, recentMessagesToProtect);
      case 'hybrid':
        return _buildHybrid(messagesToProcess, maxContextTokens, recentMessagesToProtect);
      case 'smart':
        return _buildSmart(messagesToProcess, maxContextTokens, recentMessagesToProtect);
      default:
        return _buildSmart(messagesToProcess, maxContextTokens, recentMessagesToProtect);
    }
  }

  /// Strategy 1: Sliding Window (keep last N messages)
  static String _buildSlidingWindow(
      List<ChatMessage> messages,
      int maxTokens,
      int recentMessagesToProtect,
      ) {
    const maxMessages = 20; // Configurable window size
    final startIndex = messages.length > maxMessages
        ? messages.length - maxMessages
        : 0;

    final conversationHistory = StringBuffer();
    int totalTokens = 0;

    for (int i = startIndex; i < messages.length; i++) {
      final msg = messages[i];
      final msgText = msg.isUser ? 'User: ${msg.text}\n\n' : 'Assistant: ${msg.text}\n\n';
      conversationHistory.write(msgText);
      totalTokens += estimateTokens(msg.text);
    }

    debugPrint('📊 Sliding Window: ${messages.length - startIndex} messages, ~$totalTokens tokens');
    return conversationHistory.toString();
  }

  /// Strategy 2: Token-Based (keep as many messages as fit in token budget)
  /// PROTECTED: Last N messages are ALWAYS included completely
  static String _buildTokenBased(
      List<ChatMessage> messages,
      int maxTokens,
      int recentMessagesToProtect,
      ) {
    if (messages.isEmpty) return '';

    // STEP 1: Reserve space for recent messages (always include them completely)
    final recentCount = messages.length >= recentMessagesToProtect
        ? recentMessagesToProtect
        : messages.length;

    final recentMessages = messages.sublist(messages.length - recentCount);
    int recentTokens = 0;
    for (final msg in recentMessages) {
      recentTokens += estimateTokens(msg.text);
    }

    debugPrint('🔒 Protected last $recentCount messages: $recentTokens tokens');

    // STEP 2: Calculate remaining budget for older messages
    final remainingBudget = maxTokens - recentTokens;
    final olderMessages = messages.length > recentCount
        ? messages.sublist(0, messages.length - recentCount)
        : <ChatMessage>[];

    // STEP 3: Fill remaining budget with older messages (from most recent backwards)
    final selectedOlderMessages = <ChatMessage>[];
    int olderTokens = 0;

    for (int i = olderMessages.length - 1; i >= 0; i--) {
      final msg = olderMessages[i];
      final msgTokens = estimateTokens(msg.text);

      if (olderTokens + msgTokens > remainingBudget) {
        break; // Stop if we exceed remaining budget
      }

      selectedOlderMessages.insert(0, msg);
      olderTokens += msgTokens;
    }

    // STEP 4: Build final context string
    final conversationHistory = StringBuffer();

    // Add older messages
    for (final msg in selectedOlderMessages) {
      if (msg.isUser) {
        conversationHistory.write('User: ${msg.text}\n\n');
      } else {
        conversationHistory.write('Assistant: ${msg.text}\n\n');
      }
    }

    // Add ellipsis if we skipped messages
    if (selectedOlderMessages.length < olderMessages.length) {
      final skipped = olderMessages.length - selectedOlderMessages.length;
      conversationHistory.write('[... $skipped earlier messages omitted ...]\n\n');
    }

    // Add protected recent messages (ALWAYS COMPLETE)
    for (final msg in recentMessages) {
      if (msg.isUser) {
        conversationHistory.write('User: ${msg.text}\n\n');
      } else {
        conversationHistory.write('Assistant: ${msg.text}\n\n');
      }
    }

    final totalTokens = olderTokens + recentTokens;
    debugPrint('📊 Token-Based: $totalTokens tokens ($olderTokens older + $recentTokens recent)');
    debugPrint('📝 Messages: ${selectedOlderMessages.length} older + $recentCount recent = ${selectedOlderMessages.length + recentCount} total');

    return conversationHistory.toString();
  }

  /// Strategy 3: Hybrid (keep first message + recent messages)
  /// PROTECTED: Last N messages are ALWAYS included completely
  static String _buildHybrid(
      List<ChatMessage> messages,
      int maxTokens,
      int recentMessagesToProtect,
      ) {
    if (messages.length <= 2) {
      return _buildTokenBased(messages, maxTokens, recentMessagesToProtect);
    }

    // STEP 1: Reserve space for recent messages (PROTECTED)
    final recentCount = messages.length >= recentMessagesToProtect
        ? recentMessagesToProtect
        : messages.length;

    final recentMessages = messages.sublist(messages.length - recentCount);
    int recentTokens = 0;
    for (final msg in recentMessages) {
      recentTokens += estimateTokens(msg.text);
    }

    // STEP 2: Reserve space for first message
    final firstMessage = messages.first;
    final firstTokens = estimateTokens(firstMessage.text);

    // STEP 3: Calculate remaining budget
    final remainingBudget = maxTokens - recentTokens - firstTokens;

    // STEP 4: Fill middle messages
    final conversationHistory = StringBuffer();

    // Always add first message
    conversationHistory.write('User: ${firstMessage.text}\n\n');

    // Add middle messages if budget allows
    final middleMessages = <ChatMessage>[];
    int middleTokens = 0;

    for (int i = messages.length - recentCount - 1; i > 0; i--) {
      final msg = messages[i];
      final msgTokens = estimateTokens(msg.text);

      if (middleTokens + msgTokens > remainingBudget) {
        break;
      }

      middleMessages.insert(0, msg);
      middleTokens += msgTokens;
    }

    // Add ellipsis if we skipped messages
    if (middleMessages.isNotEmpty && messages.indexOf(middleMessages.first) > 1) {
      final skipped = messages.indexOf(middleMessages.first) - 1;
      conversationHistory.write('[... $skipped messages omitted ...]\n\n');
    }

    // Add middle messages
    for (final msg in middleMessages) {
      if (msg.isUser) {
        conversationHistory.write('User: ${msg.text}\n\n');
      } else {
        conversationHistory.write('Assistant: ${msg.text}\n\n');
      }
    }

    // Add ellipsis before recent if needed
    if (middleMessages.isNotEmpty) {
      final lastMiddleIndex = messages.indexOf(middleMessages.last);
      final firstRecentIndex = messages.indexOf(recentMessages.first);
      if (firstRecentIndex > lastMiddleIndex + 1) {
        final skipped = firstRecentIndex - lastMiddleIndex - 1;
        conversationHistory.write('[... $skipped messages omitted ...]\n\n');
      }
    }

    // Add protected recent messages (ALWAYS COMPLETE)
    for (final msg in recentMessages) {
      if (msg.isUser) {
        conversationHistory.write('User: ${msg.text}\n\n');
      } else {
        conversationHistory.write('Assistant: ${msg.text}\n\n');
      }
    }

    final totalTokens = firstTokens + middleTokens + recentTokens;
    debugPrint('📊 Hybrid: $totalTokens tokens (first + $middleTokens middle + $recentTokens recent)');
    debugPrint('📝 Messages: 1 first + ${middleMessages.length} middle + $recentCount recent');

    return conversationHistory.toString();
  }

  /// Strategy 4: Smart (prioritize first, last N, and important messages)
  /// PROTECTED: Last N messages are ALWAYS included completely
  static String _buildSmart(
      List<ChatMessage> messages,
      int maxTokens,
      int recentMessagesToProtect,
      ) {
    if (messages.length <= 5) {
      return _buildTokenBased(messages, maxTokens, recentMessagesToProtect);
    }

    // STEP 1: Reserve space for recent messages (PROTECTED)
    final recentCount = messages.length >= recentMessagesToProtect
        ? recentMessagesToProtect
        : messages.length;

    final recentMessages = messages.sublist(messages.length - recentCount);
    int recentTokens = 0;
    for (final msg in recentMessages) {
      recentTokens += estimateTokens(msg.text);
    }

    debugPrint('🔒 Protected last $recentCount messages: $recentTokens tokens');

    // STEP 2: Reserve space for first message
    final firstMessage = messages.first;
    final firstTokens = estimateTokens(firstMessage.text);

    // STEP 3: Calculate remaining budget for middle messages
    final remainingBudget = maxTokens - recentTokens - firstTokens;

    final conversationHistory = StringBuffer();
    final selectedMessages = <ChatMessage>[];

    // Add first message
    selectedMessages.add(firstMessage);

    // STEP 4: Fill middle messages (between first and recent)
    final middleMessages = <ChatMessage>[];
    int middleTokens = 0;

    final middleStart = 1; // After first message
    final middleEnd = messages.length - recentCount; // Before recent messages

    for (int i = middleEnd - 1; i >= middleStart; i--) {
      final msg = messages[i];
      final msgTokens = estimateTokens(msg.text);

      if (middleTokens + msgTokens > remainingBudget) {
        break;
      }

      middleMessages.insert(0, msg);
      middleTokens += msgTokens;
    }

    selectedMessages.addAll(middleMessages);
    selectedMessages.addAll(recentMessages);

    // STEP 5: Build context string
    int lastIndex = 0;

    for (final msg in selectedMessages) {
      final currentIndex = messages.indexOf(msg);

      // Add ellipsis if we skipped messages
      if (currentIndex > lastIndex + 1) {
        final skipped = currentIndex - lastIndex - 1;
        conversationHistory.write('[... $skipped messages omitted ...]\n\n');
      }

      if (msg.isUser) {
        conversationHistory.write('User: ${msg.text}\n\n');
      } else {
        conversationHistory.write('Assistant: ${msg.text}\n\n');
      }

      lastIndex = currentIndex;
    }

    final totalTokens = firstTokens + middleTokens + recentTokens;
    debugPrint('📊 Smart Strategy: $totalTokens tokens (first + $middleTokens middle + $recentTokens recent)');
    debugPrint('📝 Messages: 1 first + ${middleMessages.length} middle + $recentCount recent = ${selectedMessages.length} total');

    return conversationHistory.toString();
  }

  /// Helper method to analyze your context
  static void analyzeContext(List<ChatMessage> messages, int maxTokens) {
    debugPrint('\n=== CONTEXT ANALYSIS ===');
    debugPrint('Total messages: ${messages.length}');
    debugPrint('Max tokens allowed: $maxTokens');

    int totalTokens = 0;
    for (var msg in messages) {
      totalTokens += estimateTokens(msg.text);
    }

    debugPrint('Total tokens in all messages: $totalTokens');
    debugPrint('Token budget usage: ${(totalTokens / maxTokens * 100).toStringAsFixed(1)}%');

    if (totalTokens > maxTokens) {
      debugPrint('⚠️ WARNING: Total tokens exceed budget by ${totalTokens - maxTokens}');
    }

    debugPrint('======================\n');
  }
}