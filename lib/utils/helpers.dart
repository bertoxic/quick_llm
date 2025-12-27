import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/chat_message.dart';
import '../services/storage_service.dart';

class FileAttachmentHelper {
  static const List<String> supportedImageExtensions = [
    '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'
  ];

  static const List<String> supportedDocExtensions = [
    '.pdf', '.txt', '.doc', '.docx', '.md'
  ];

  final StorageService _storageService;

  FileAttachmentHelper(this._storageService);

  /// Pick files using file picker
  Future<List<File>> pickFiles({
    required BuildContext context,
    required bool copyFileAttachments,
  }) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: [
          'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp',
          'pdf', 'txt', 'doc', 'docx', 'md',
        ],
      );

      if (result == null || result.files.isEmpty) {
        return [];
      }

      List<File> filesToAttach = [];

      for (var file in result.files) {
        if (file.path != null) {
          try {
            final filePath = await _storageService.saveAttachment(
              file.path!,
              copyFile: copyFileAttachments,
            );
            filesToAttach.add(File(filePath));

            if (copyFileAttachments) {
              debugPrint('✅ File copied to: $filePath');
            } else {
              debugPrint('📌 File referenced at: $filePath');
            }
          } catch (e) {
            debugPrint('❌ Failed to process file: ${file.name}, error: $e');
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed to attach ${file.name}')),
              );
            }
          }
        }
      }

      if (filesToAttach.isNotEmpty) {
        debugPrint('📎 Total files attached: ${filesToAttach.length}');
      }

      return filesToAttach;
    } catch (e) {
      debugPrint('❌ Error picking files: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick files: $e')),
        );
      }
      return [];
    }
  }

  /// Separate attached files into images and documents
  static ({List<String>? images, List<String>? documents}) separateFileTypes(
      List<String>? attachedFiles,
      ) {
    if (attachedFiles == null || attachedFiles.isEmpty) {
      return (images: null, documents: null);
    }

    final images = <String>[];
    final documents = <String>[];

    for (final filePath in attachedFiles) {
      final extension = filePath.toLowerCase().substring(filePath.lastIndexOf('.'));

      if (supportedImageExtensions.contains(extension)) {
        images.add(filePath);
      } else if (supportedDocExtensions.contains(extension)) {
        documents.add(filePath);
      }
    }

    return (
    images: images.isNotEmpty ? images : null,
    documents: documents.isNotEmpty ? documents : null,
    );
  }

  /// Check for missing attachments and show dialog if any
  Future<void> checkMissingAttachments({
    required BuildContext context,
    required List<String> allFiles,
  }) async {
    if (allFiles.isEmpty) return;

    final missing = await _storageService.getMissingAttachments(allFiles);

    if (missing.isNotEmpty && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ ${missing.length} attached file(s) are missing'),
          action: SnackBarAction(
            label: 'Details',
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Missing Files'),
                  content: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: missing
                          .map((path) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('• ${getFileName(path)}'),
                      ))
                          .toList(),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            },
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  /// Get file icon based on extension
  static String getFileIcon(String path) {
    final extension = path.toLowerCase().substring(path.lastIndexOf('.'));

    if (supportedImageExtensions.contains(extension)) {
      return '🖼️';
    } else if (extension == '.pdf') {
      return '📄';
    } else if (['.doc', '.docx'].contains(extension)) {
      return '📝';
    } else if (extension == '.txt') {
      return '📃';
    } else if (extension == '.md') {
      return '📋';
    }
    return '📎';
  }

  /// Get file name from path
  static String getFileName(String path) {
    return path.split('/').last;
  }
}


class EmptyChatPlaceholder extends StatelessWidget {
  const EmptyChatPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Start a conversation',
            style: TextStyle(
              fontSize: 20,
              color: Colors.grey[400],
            ),
          ),
        ],
      ),
    );
  }
}


/// Handles building message arrays for Ollama API requests
class ChatMessageBuilder {
  /// Extract messages for context (excluding the last two: user message and empty assistant)
  static List<ChatMessage> extractContextMessages(List<ChatMessage> allMessages) {
    // I need at least 2 messages to have context
    if (allMessages.length < 2) {
      return <ChatMessage>[];
    }

    // I exclude the last 2 messages: newly added user message and empty assistant message
    return allMessages.sublist(0, allMessages.length - 2);
  }

  /// Build the messages array for Ollama chat endpoint
  static List<Map<String, String>> buildMessagesArray({
    required List<ChatMessage> contextMessages,
    required String currentMessageText,
  }) {
    final messagesArray = <Map<String, String>>[];

    // I add all previous messages from context
    for (final msg in contextMessages) {
      messagesArray.add({
        'role': msg.isUser ? 'user' : 'assistant',
        'content': msg.text,
      });
    }

    // I add the current user message
    messagesArray.add({
      'role': 'user',
      'content': currentMessageText,
    });

    return messagesArray;
  }
}


/// Manages auto-scrolling behavior for chat messages
class ScrollControllerHelper {
  final ScrollController _scrollController;

  bool _isAutoScrollEnabled = true;
  bool _userHasScrolled = false;
  bool _isProgrammaticScroll = false;

  ScrollControllerHelper(this._scrollController);

  bool get isAutoScrollEnabled => _isAutoScrollEnabled;
  bool get userHasScrolled => _userHasScrolled;

  /// Setup the scroll listener to detect user scrolling
  void setupListener({
    required VoidCallback onUserScrolledUp,
    required bool Function() isGenerating,
  }) {
    _scrollController.addListener(() {
      // I check if the controller is valid and mounted
      if (!_scrollController.hasClients) return;

      // I skip if this is a programmatic scroll
      if (_isProgrammaticScroll) return;

      // I only track user scrolling during generation
      if (isGenerating() && _isAutoScrollEnabled) {
        final isAtBottom = _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 50;

        if (!isAtBottom) {
          // I disable auto-scroll when user scrolls up
          _isAutoScrollEnabled = false;
          _userHasScrolled = true;
          debugPrint('🔒 Auto-scroll disabled - user scrolled up');
          onUserScrolledUp();
        }
      }
    });
  }

  /// Reset auto-scroll state (call when starting new generation)
  void resetAutoScroll() {
    _isAutoScrollEnabled = true;
    _userHasScrolled = false;
  }

  /// Scroll to bottom with animation
  void scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _isProgrammaticScroll = true;
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        ).then((_) {
          _isProgrammaticScroll = false;
        });
      }
    });
  }

  /// Clean up resources
  void dispose() {
    _scrollController.dispose();
  }
}


/// Complete input area with attach button, text field, and send/stop buttons
class ChatInputArea extends StatelessWidget {
  final TextEditingController controller;
  final bool isDarkMode;
  final bool isGenerating;
  final List<File> attachedFiles;
  final VoidCallback onSendMessage;
  final VoidCallback onStopGeneration;
  final VoidCallback onPickFiles;
  final void Function(int index) onRemoveFile;

  const ChatInputArea({
    super.key,
    required this.controller,
    required this.isDarkMode,
    required this.isGenerating,
    required this.attachedFiles,
    required this.onSendMessage,
    required this.onStopGeneration,
    required this.onPickFiles,
    required this.onRemoveFile,
  });

  // I extract the file icon based on extension
  String _getFileIcon(String path) {
    final extension = path.toLowerCase().substring(path.lastIndexOf('.'));

    const supportedImageExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'];

    if (supportedImageExtensions.contains(extension)) {
      return '🖼️';
    } else if (extension == '.pdf') {
      return '📄';
    } else if (['.doc', '.docx'].contains(extension)) {
      return '📝';
    } else if (extension == '.txt') {
      return '📃';
    } else if (extension == '.md') {
      return '📋';
    }
    return '📎';
  }

  // I extract just the filename from the full path
  String _getFileName(String path) {
    return path.split('/').last;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.3,
      ),
      decoration: BoxDecoration(
        color: isDarkMode
            ? const Color(0xFF2A2A2A)
            : Colors.grey[200],
        border: Border(
          top: BorderSide(
            color: isDarkMode
                ? Colors.grey[800]!
                : Colors.grey[300]!,
          ),
        ),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // I show file attachments preview if there are any
              if (attachedFiles.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDarkMode
                        ? Colors.grey[800]
                        : Colors.grey[300],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: attachedFiles
                        .asMap()
                        .entries
                        .map((entry) {
                      final index = entry.key;
                      final file = entry.value;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isDarkMode
                              ? Colors.grey[700]
                              : Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isDarkMode
                                ? Colors.grey[600]!
                                : Colors.grey[400]!,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _getFileIcon(file.path),
                              style: const TextStyle(fontSize: 16),
                            ),
                            const SizedBox(width: 6),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 150),
                              child: Text(
                                _getFileName(file.path),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () => onRemoveFile(index),
                              child: Icon(
                                Icons.close,
                                size: 16,
                                color: Colors.red[400],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),

              // I build the message input row
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Attach file button
                  IconButton(
                    icon: Icon(
                      Icons.attach_file,
                      color: attachedFiles.isNotEmpty
                          ? Colors.blue
                          : null,
                    ),
                    onPressed: isGenerating ? null : onPickFiles,
                    tooltip: 'Attach files (images, PDFs, documents)',
                  ),
                  const SizedBox(width: 4),

                  // Text input field
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxHeight: 150,
                      ),
                      child: TextField(
                        controller: controller,
                        decoration: const InputDecoration(
                          hintText: 'Type a message...',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        maxLines: null,
                        textInputAction: TextInputAction.newline,
                        onSubmitted: (_) => isGenerating ? null : onSendMessage(),
                        enabled: !isGenerating,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Send/Stop button - I switch based on generation state
                  if (isGenerating)
                    IconButton(
                      icon: const Icon(Icons.stop_circle),
                      onPressed: onStopGeneration,
                      iconSize: 28,
                      color: Colors.red,
                      tooltip: 'Stop generation',
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.send),
                      onPressed: onSendMessage,
                      iconSize: 28,
                      tooltip: 'Send message',
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}