import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

import '../models/chat_message.dart';
import '../models/conversation.dart';

/// Service for handling all persistent storage operations
/// Uses SharedPreferences for settings and file system for exports
class StorageService {

  // ============= PREFERENCES =============

  /// Loads all user preferences from SharedPreferences
  /// Returns a map with default values for missing keys
  Future<Map<String, dynamic>> loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'sidebarVisible': prefs.getBool('sidebarVisible') ?? true,
      'systemPrompt': prefs.getString('systemPrompt') ?? '',
      'temperature': prefs.getDouble('temperature') ?? 0.7,
      'maxTokens': prefs.getInt('maxTokens') ?? 2048,
      'useSystemPrompt': prefs.getBool('useSystemPrompt') ?? false,
      'monitorClipboard': prefs.getBool('monitorClipboard') ?? false,
      'copyFileAttachments': prefs.getBool('copyFileAttachments') ?? true,
    };
  }

  /// Saves user preferences to SharedPreferences
  /// Pass a map with any of the preference keys to update
  Future<void> savePreferences(Map<String, dynamic> preferences) async {
    final prefs = await SharedPreferences.getInstance();

    if (preferences.containsKey('sidebarVisible')) {
      await prefs.setBool('sidebarVisible', preferences['sidebarVisible']);
    }
    if (preferences.containsKey('systemPrompt')) {
      await prefs.setString('systemPrompt', preferences['systemPrompt']);
    }
    if (preferences.containsKey('temperature')) {
      await prefs.setDouble('temperature', preferences['temperature']);
    }
    if (preferences.containsKey('maxTokens')) {
      await prefs.setInt('maxTokens', preferences['maxTokens']);
    }
    if (preferences.containsKey('useSystemPrompt')) {
      await prefs.setBool('useSystemPrompt', preferences['useSystemPrompt']);
    }
    if (preferences.containsKey('monitorClipboard')) {
      await prefs.setBool('monitorClipboard', preferences['monitorClipboard']);
    }
    if (preferences.containsKey('copyFileAttachments')) {
      await prefs.setBool('copyFileAttachments', preferences['copyFileAttachments']);
    }
  }

  // ============= FILE ATTACHMENTS =============

  /// Handles file attachment based on user preference
  /// If copyFileAttachments is true: copies file to permanent storage
  /// If copyFileAttachments is false: returns original path (reference only)
  /// Returns the path to use for the attachment
  Future<String> saveAttachment(String tempFilePath, {bool? copyFile}) async {
    try {
      final sourceFile = File(tempFilePath);
      if (!await sourceFile.exists()) {
        throw Exception('Source file does not exist');
      }

      // Load user preference if not explicitly specified
      final shouldCopy = copyFile ?? await _shouldCopyFiles();

      if (!shouldCopy) {
        // Just return the original path (reference only)
        debugPrint('📌 Using file reference: $tempFilePath');
        return tempFilePath;
      }

      // Copy to permanent storage (original behavior)
      final directory = await getApplicationDocumentsDirectory();
      final attachmentsDir = Directory('${directory.path}/attachments');

      if (!await attachmentsDir.exists()) {
        await attachmentsDir.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = tempFilePath.substring(tempFilePath.lastIndexOf('.'));
      final permanentPath = '${attachmentsDir.path}/$timestamp$extension';

      await sourceFile.copy(permanentPath);
      debugPrint('✅ File copied to permanent storage: $permanentPath');

      return permanentPath;
    } catch (e) {
      debugPrint('❌ Error saving attachment: $e');
      rethrow;
    }
  }

  /// Helper to check user preference for copying files
  Future<bool> _shouldCopyFiles() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('copyFileAttachments') ?? true; // Default: copy files
  }

  /// Check if an attachment file exists and is accessible
  Future<bool> attachmentExists(String filePath) async {
    try {
      final file = File(filePath);
      return await file.exists();
    } catch (e) {
      return false;
    }
  }

  /// Validates all attachments and returns list of missing files
  /// Useful for showing warnings to users about missing referenced files
  Future<List<String>> getMissingAttachments(List<String> filePaths) async {
    final missing = <String>[];
    for (final path in filePaths) {
      if (!await attachmentExists(path)) {
        missing.add(path);
      }
    }
    return missing;
  }

  /// Cleanup: Removes orphaned attachment files that aren't referenced in any conversation
  /// Call this periodically or on app startup to free up space
  Future<int> cleanupOrphanedAttachments(List<Conversation> conversations) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final attachmentsDir = Directory('${directory.path}/attachments');

      if (!await attachmentsDir.exists()) {
        return 0;
      }

      // Collect all referenced file paths
      final referencedPaths = <String>{};
      for (final conv in conversations) {
        for (final msg in conv.messages) {
          if (msg.attachedFiles != null) {
            referencedPaths.addAll(msg.attachedFiles!);
          }
        }
      }

      // Find and delete orphaned files
      int deletedCount = 0;
      await for (final entity in attachmentsDir.list()) {
        if (entity is File) {
          if (!referencedPaths.contains(entity.path)) {
            await entity.delete();
            deletedCount++;
            debugPrint('🗑️ Deleted orphaned attachment: ${entity.path}');
          }
        }
      }

      debugPrint('✅ Cleanup complete: $deletedCount orphaned files deleted');
      return deletedCount;
    } catch (e) {
      debugPrint('❌ Error during cleanup: $e');
      return 0;
    }
  }

  // ============= CONVERSATIONS =============

  /// Loads all saved conversations from SharedPreferences
  /// Returns empty list if none exist
  Future<List<Conversation>> loadConversations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final conversationsJson = prefs.getStringList('conversations') ?? [];
      return conversationsJson
          .map((json) => Conversation.fromJson(jsonDecode(json)))
          .toList();
    } catch (e) {
      print('Error loading conversations: $e');
      return [];
    }
  }

  /// Saves all conversations to SharedPreferences
  /// Serializes each conversation to JSON string
  Future<void> saveConversations(List<Conversation> conversations) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final conversationsJson = conversations
          .map((conv) => jsonEncode(conv.toJson()))
          .toList();
      await prefs.setStringList('conversations', conversationsJson);
    } catch (e) {
      print('Error saving conversations: $e');
    }
  }

  /// Clears all conversations from storage
  /// Also runs cleanup to remove all orphaned attachments
  /// Returns true if successful, false otherwise
  Future<bool> clearAllConversations() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Clear conversations from SharedPreferences
      await prefs.remove('conversations');
      debugPrint('✅ All conversations cleared from storage');

      // Clean up all attachment files
      final directory = await getApplicationDocumentsDirectory();
      final attachmentsDir = Directory('${directory.path}/attachments');

      if (await attachmentsDir.exists()) {
        int deletedCount = 0;
        await for (final entity in attachmentsDir.list()) {
          if (entity is File) {
            await entity.delete();
            deletedCount++;
          }
        }
        debugPrint('✅ Deleted $deletedCount attachment files');
      }

      return true;
    } catch (e) {
      debugPrint('❌ Error clearing conversations: $e');
      return false;
    }
  }

  // ============= MINI MODE HISTORY =============

  Future<List<ChatMessage>> loadMiniMessages() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/mini_messages.json');

      if (!await file.exists()) {
        return [];
      }

      final jsonString = await file.readAsString();
      final List<dynamic> jsonList = json.decode(jsonString);

      return jsonList
          .map((json) => ChatMessage.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error loading mini messages: $e');
      return [];
    }
  }

  /// Save mini mode messages to storage
  Future<void> saveMiniMessages(List<ChatMessage> messages) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/mini_messages.json');

      final jsonList = messages.map((msg) => msg.toJson()).toList();
      final jsonString = json.encode(jsonList);

      await file.writeAsString(jsonString);
    } catch (e) {
      debugPrint('Error saving mini messages: $e');
    }
  }

  /// Load mini mode history (legacy - for backward compatibility)
  Future<List<String>> loadMiniHistory() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/mini_history.json');

      if (!await file.exists()) {
        return [];
      }

      final jsonString = await file.readAsString();
      final List<dynamic> jsonList = json.decode(jsonString);

      return jsonList.cast<String>();
    } catch (e) {
      debugPrint('Error loading mini history: $e');
      return [];
    }
  }

  /// Save mini mode history (legacy - for backward compatibility)
  Future<void> saveMiniHistory(List<String> history) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/mini_history.json');

      final jsonString = json.encode(history);
      await file.writeAsString(jsonString);
    } catch (e) {
      debugPrint('Error saving mini history: $e');
    }
  }

  // ============= QUICK PROMPTS =============

  /// Load quick prompts
  Future<List<String>> loadQuickPrompts() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/quick_prompts.json');

      if (!await file.exists()) {
        return [];
      }

      final jsonString = await file.readAsString();
      final List<dynamic> jsonList = json.decode(jsonString);

      return jsonList.cast<String>();
    } catch (e) {
      debugPrint('Error loading quick prompts: $e');
      return [];
    }
  }

  /// Save quick prompts
  Future<void> saveQuickPrompts(List<String> prompts) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/quick_prompts.json');

      final jsonString = json.encode(prompts);
      await file.writeAsString(jsonString);
    } catch (e) {
      debugPrint('Error saving quick prompts: $e');
    }
  }

  // ============= EXPORT FUNCTIONALITY =============

  /// Get or create the quick_llm export directory
  Future<Directory> _getExportDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${directory.path}/quick_llm');

    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }

    return exportDir;
  }

  /// Exports a single conversation to JSON file in quick_llm folder
  /// Returns the file path where it was saved
  Future<String> exportConversation(Conversation conversation) async {
    final exportDir = await _getExportDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${exportDir.path}/conversation_$timestamp.json');
    await file.writeAsString(jsonEncode(conversation.toJson()));
    return file.path;
  }

  /// Exports all conversations to a single JSON file in quick_llm folder
  /// Returns the file path where it was saved
  Future<String> exportAllConversations(List<Conversation> conversations) async {
    final exportDir = await _getExportDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${exportDir.path}/all_conversations_$timestamp.json');
    final data = conversations.map((c) => c.toJson()).toList();
    await file.writeAsString(jsonEncode(data));
    return file.path;
  }
}