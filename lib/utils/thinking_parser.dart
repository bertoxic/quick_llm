import 'package:flutter/material.dart';
import '../models/chat_message.dart';

/// Result of parsing thinking text
class ParsedThinkingResult {
  final String displayText;
  final String? thinkingText;
  final bool isThinking;

  ParsedThinkingResult({
    required this.displayText,
    this.thinkingText,
    required this.isThinking,
  });
}

/// Handles extraction of thinking text from streaming responses
class ThinkingParser {
  /// Parse streaming text for thinking patterns
  static ParsedThinkingResult parse(String fullText, ChatMessage currentMsg) {
    String displayText = fullText;
    String? thinkingText;
    bool isThinking = false;

    // Get accumulated thinking from previous updates
    String accumulatedThinking = currentMsg.thinkingText ?? '';

    // Pattern 1: Check for "Thinking..." with "...done thinking." markers
    final thinkingStartIndex = fullText.indexOf('Thinking...');
    final doneThinkingIndex = fullText.indexOf('...done thinking.');

    if (thinkingStartIndex != -1) {
      final result = _parseThinkingPattern(
        fullText,
        thinkingStartIndex,
        doneThinkingIndex,
      );
      return result;
    }
    // Pattern 2: Check for <think> tags (for models like DeepSeek)
    else if (fullText.contains('<think>')) {
      final result = _parseThinkTags(fullText);
      return result;
    }
    // No thinking pattern found - preserve existing thinking state
    else if (currentMsg.isThinking ||
        (currentMsg.thinkingText != null && currentMsg.thinkingText!.isNotEmpty)) {
      thinkingText = accumulatedThinking;
      isThinking = currentMsg.isThinking;
      displayText = fullText;
    }

    // Clean up display text - remove extra whitespace
    displayText = displayText.replaceAll(RegExp(r'\s+'), ' ').trim();

    return ParsedThinkingResult(
      displayText: displayText,
      thinkingText: thinkingText,
      isThinking: isThinking,
    );
  }

  /// Parse "Thinking..." pattern
  static ParsedThinkingResult _parseThinkingPattern(
      String fullText,
      int startIndex,
      int endIndex,
      ) {
    if (endIndex != -1 && endIndex > startIndex) {
      // Complete thinking block found
      final thinkingContent = fullText
          .substring(startIndex + 'Thinking...'.length, endIndex)
          .trim();

      final displayText = (fullText.substring(0, startIndex).trim() +
          ' ' +
          fullText.substring(endIndex + '...done thinking.'.length).trim())
          .trim();


      return ParsedThinkingResult(
        displayText: displayText,
        thinkingText: thinkingContent,
        isThinking: false,
      );
    } else {
      // Thinking in progress
      final thinkingContent = fullText
          .substring(startIndex + 'Thinking...'.length)
          .trim();

      final displayText = fullText.substring(0, startIndex).trim();


      return ParsedThinkingResult(
        displayText: displayText,
        thinkingText: thinkingContent,
        isThinking: true,
      );
    }
  }

  /// Parse <think> tags
  static ParsedThinkingResult _parseThinkTags(String fullText) {
    final thinkOpenIndex = fullText.indexOf('<think>');
    final thinkCloseIndex = fullText.indexOf('</think>');

    if (thinkCloseIndex != -1 && thinkCloseIndex > thinkOpenIndex) {
      // Complete think block found
      final thinkingContent = fullText
          .substring(thinkOpenIndex + '<think>'.length, thinkCloseIndex)
          .trim();

      final displayText = (fullText.substring(0, thinkOpenIndex).trim() +
          ' ' +
          fullText.substring(thinkCloseIndex + '</think>'.length).trim())
          .trim();

      debugPrint('✅ Complete <think> block extracted: ${thinkingContent.length} chars');

      return ParsedThinkingResult(
        displayText: displayText,
        thinkingText: thinkingContent,
        isThinking: false,
      );
    } else {
      // Thinking in progress with <think> tags
      final thinkingContent = fullText
          .substring(thinkOpenIndex + '<think>'.length)
          .trim();

      final displayText = fullText.substring(0, thinkOpenIndex).trim();

      debugPrint('🤔 <think> in progress: ${thinkingContent.length} chars');

      return ParsedThinkingResult(
        displayText: displayText,
        thinkingText: thinkingContent,
        isThinking: true,
      );
    }
  }
}