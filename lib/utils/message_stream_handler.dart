import 'dart:async';
import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../models/conversation.dart';
import '../provider/ChatProvider.dart';
import '../services/ollama_service.dart';
import 'thinking_parser.dart';

/// Handles streaming message generation and updates
class MessageStreamHandler {
  final OllamaService _ollamaService;

  // REDUCED debounce for smoother updates (was 50ms)
  Timer? _updateDebounceTimer;
  static const _updateDebounceMs = 16; // ~60fps for smooth updates

  bool _isStreamActive = false;
  StreamSubscription<String>? _activeStreamSubscription;

  MessageStreamHandler(this._ollamaService);
  // Track if we should continue updating
  bool _shouldContinueUpdating = true;

  /// Call this when changing contexts (e.g., switching screens)
  void pauseUpdates() {
    _shouldContinueUpdating = false;
    debugPrint('⏸️ MessageStreamHandler paused');
  }

  /// Resume updates after context change
  void resumeUpdates() {
    _shouldContinueUpdating = true;
    debugPrint('▶️ MessageStreamHandler resumed');
  }
  /// Cancel any active stream
  void cancelActiveStream() {
    debugPrint('🔴 Cancelling active stream');
    _activeStreamSubscription?.cancel();
    _activeStreamSubscription = null;
    _updateDebounceTimer?.cancel();
    _isStreamActive = false;
  }

  /// Process streaming response with thinking support
  Future<void> handleStream({
    required Stream<String> stream,
    required ChatProvider provider,
    required int? generatingForIndex,
    required VoidCallback onUpdate,
    required Function(bool) onStopGenerationChanged,
    bool isRightPane = false,
  }) async {
    if (_isStreamActive) {
      debugPrint('⚠️ Stream already active, cancelling previous stream');
      cancelActiveStream();
      await Future.delayed(const Duration(milliseconds: 50));
    }

    _isStreamActive = true;
    String localStreamingResponse = '';
    bool streamCompleted = false;
    bool hadError = false;

    debugPrint('🚀 Starting stream for conversation index: $generatingForIndex (${isRightPane ? "RIGHT" : "LEFT"} pane)');

    try {
      onStopGenerationChanged(true);

      _activeStreamSubscription = stream.listen(
            (token) {
          if (!provider.isGenerating) {
            debugPrint('🛑 Generation stopped by user, cancelling stream');
            _activeStreamSubscription?.cancel();
            return;
          }

          localStreamingResponse += token;
          provider.updateStreamingResponse(localStreamingResponse);

          // IMMEDIATE update for fast typing effect
          _updateMessageWithThinking(
            provider,
            localStreamingResponse,
            generatingForIndex,
            isRightPane: isRightPane,
          );

          // Schedule UI callback with minimal debounce
          _updateDebounceTimer?.cancel();
          _updateDebounceTimer = Timer(
            const Duration(milliseconds: _updateDebounceMs),
            onUpdate,
          );
        },
        onError: (error) {
          hadError = true;
          debugPrint('❌ Stream error: $error');
          _updateDebounceTimer?.cancel();

          _handleStreamError(
            error,
            provider,
            localStreamingResponse,
            generatingForIndex,
            isRightPane: isRightPane,
          );
        },
        onDone: () {
          streamCompleted = true;
          debugPrint('✅ Stream completed successfully');
          _updateDebounceTimer?.cancel();

          if (localStreamingResponse.isNotEmpty) {
            _updateMessageWithThinking(
              provider,
              localStreamingResponse,
              generatingForIndex,
              isRightPane: isRightPane,
            );
          }
        },
        cancelOnError: true,
      );

      await _activeStreamSubscription!.asFuture();

    } catch (e) {
      hadError = true;
      debugPrint('❌ Error during streaming: $e');
      _updateDebounceTimer?.cancel();

      if (generatingForIndex != null && localStreamingResponse.isNotEmpty) {
        _updateMessageWithThinking(
          provider,
          localStreamingResponse,
          generatingForIndex,
          isRightPane: isRightPane,
        );
      }
    } finally {
      _updateDebounceTimer?.cancel();
      _activeStreamSubscription?.cancel();
      _activeStreamSubscription = null;

      _isStreamActive = false;
      onStopGenerationChanged(false);

      if (provider.isGenerating) {
        provider.stopGenerating();
        debugPrint('🏁 Generation stopped in finally block');
      }

      debugPrint('📊 Stream summary - Completed: $streamCompleted, Error: $hadError, Response length: ${localStreamingResponse.length}');
    }
  }

  /// Update message with thinking text extraction
  void _updateMessageWithThinking(
      ChatProvider provider,
      String streamingText,
      int? targetConversationIndex, {
        bool isRightPane = false,
      }) {
    // Don't update if we're in a context switch
    if (!_shouldContinueUpdating) {
      debugPrint('⏸️ Skipping update during context switch');
      return;
    }

    if (targetConversationIndex == null ||
        targetConversationIndex >= provider.conversations.length) {
      debugPrint('⚠️ Invalid conversation index: $targetConversationIndex');
      return;
    }

    final targetConv = provider.conversations[targetConversationIndex];
    if (targetConv.messages.isEmpty) {
      debugPrint('⚠️ No messages in conversation');
      return;
    }

    final currentMsg = targetConv.messages.last;
    if (currentMsg.isUser) {
      debugPrint('⚠️ Last message is user message, skipping update');
      return;
    }

    final parsed = ThinkingParser.parse(streamingText, currentMsg);

    final updatedMessage = ChatMessage(
      text: parsed.displayText,
      isUser: false,
      timestamp: currentMsg.timestamp,
      thinkingText: parsed.thinkingText,
      isThinking: parsed.isThinking,
      modelName: currentMsg.modelName ?? provider.selectedModel,
      attachedFiles: currentMsg.attachedFiles,
    );

    final updatedMessages = List<ChatMessage>.from(targetConv.messages);
    updatedMessages[updatedMessages.length - 1] = updatedMessage;

    provider.updateConversation(
      targetConversationIndex,
      Conversation(
        title: targetConv.title,
        messages: updatedMessages,
        timestamp: targetConv.timestamp,
      ),
    );

    if (!isRightPane && provider.selectedConversationIndex == targetConversationIndex) {
      provider.setMessages(updatedMessages);
    }
  }

  void dispose() {
    _updateDebounceTimer?.cancel();
    _activeStreamSubscription?.cancel();
    _activeStreamSubscription = null;
    _isStreamActive = false;
    _shouldContinueUpdating = false; // Add this
  }
  /// Handle streaming errors
  void _handleStreamError(
      dynamic error,
      ChatProvider provider,
      String localStreamingResponse,
      int? generatingForIndex, {
        bool isRightPane = false,
      }) {
    final errorStr = error.toString();
    final isCancellation = errorStr.contains('Connection closed') ||
        errorStr.contains('ClientException') ||
        errorStr.contains('cancelled');

    debugPrint('🔍 Error type: ${isCancellation ? "Cancellation" : "Error"}');

    if (generatingForIndex == null ||
        generatingForIndex >= provider.conversations.length) {
      return;
    }

    final targetConv = provider.conversations[generatingForIndex];

    if (!isCancellation && targetConv.messages.isNotEmpty) {
      _updateErrorMessage(provider, generatingForIndex, errorStr, isRightPane: isRightPane);
    } else if (isCancellation && targetConv.messages.isNotEmpty) {
      _handleCancellation(provider, generatingForIndex, targetConv, localStreamingResponse, isRightPane: isRightPane);
    }

    if (localStreamingResponse.isNotEmpty) {
      _updateMessageWithThinking(
        provider,
        localStreamingResponse,
        generatingForIndex,
        isRightPane: isRightPane,
      );
    }
  }

  void _updateErrorMessage(
      ChatProvider provider,
      int index,
      String errorMessage, {
        bool isRightPane = false,
      }) {
    final targetConv = provider.conversations[index];
    final updatedMessages = List<ChatMessage>.from(targetConv.messages);

    updatedMessages[updatedMessages.length - 1] = ChatMessage(
      text: 'Error: $errorMessage',
      isUser: false,
      timestamp: updatedMessages.last.timestamp,
      modelName: provider.selectedModel,
    );

    provider.updateConversation(
      index,
      Conversation(
        title: targetConv.title,
        messages: updatedMessages,
        timestamp: targetConv.timestamp,
      ),
    );

    if (!isRightPane && provider.selectedConversationIndex == index) {
      provider.setMessages(updatedMessages);
    }
  }

  void _handleCancellation(
      ChatProvider provider,
      int index,
      Conversation targetConv,
      String partialResponse, {
        bool isRightPane = false,
      }) {
    if (partialResponse.isNotEmpty) {
      debugPrint('✂️ Keeping partial response (${partialResponse.length} chars) after cancellation');
      return;
    }

    final currentText = targetConv.messages.last.text;
    if (currentText.isEmpty) {
      final updatedMessages = List<ChatMessage>.from(targetConv.messages);
      updatedMessages.removeLast();

      provider.updateConversation(
        index,
        Conversation(
          title: targetConv.title,
          messages: updatedMessages,
          timestamp: targetConv.timestamp,
        ),
      );

      if (!isRightPane && provider.selectedConversationIndex == index) {
        provider.setMessages(updatedMessages);
      }

      debugPrint('🗑️ Removed empty assistant message after cancellation');
    }
  }
  }

