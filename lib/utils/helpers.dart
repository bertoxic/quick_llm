import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/chat_message.dart';
import '../services/storage_service.dart';

class FileAttachmentHelper {
  static const List<String> supportedImageExtensions = [
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.bmp',
    '.webp',
  ];

  static const List<String> supportedDocExtensions = [
    '.pdf',
    '.txt',
    '.doc',
    '.docx',
    '.md',
    '.csv',
    '.tsv',
    '.json',
    '.yaml',
    '.yml',
    '.xml',
    '.html',
    '.htm',
    '.log',
    '.rtf',
  ];

  static const List<String> supportedAudioExtensions = [
    '.mp3',
    '.wav',
    '.m4a',
    '.aac',
    '.flac',
    '.ogg',
    '.opus',
    '.wma',
  ];

  static const List<String> supportedVideoExtensions = [
    '.mp4',
    '.mov',
    '.avi',
    '.mkv',
    '.webm',
    '.m4v',
    '.wmv',
  ];

  final StorageService _storageService;

  FileAttachmentHelper(this._storageService);

  Future<List<File>> pickFiles({
    required BuildContext context,
    required bool copyFileAttachments,
  }) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );

      if (result == null || result.files.isEmpty) {
        return [];
      }

      final filesToAttach = <File>[];

      for (final file in result.files) {
        if (file.path == null) continue;

        try {
          final filePath = await _storageService.saveAttachment(
            file.path!,
            copyFile: copyFileAttachments,
          );
          filesToAttach.add(File(filePath));
        } catch (e) {
          debugPrint('Failed to process file ${file.name}: $e');
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to attach ${file.name}')),
            );
          }
        }
      }

      return filesToAttach;
    } catch (e) {
      debugPrint('Error picking files: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick files: $e')),
        );
      }
      return [];
    }
  }

  static ({
    List<String>? images,
    List<String>? documents,
    List<String>? audio,
    List<String>? videos,
    List<String>? otherFiles,
  }) separateFileTypes(List<String>? attachedFiles) {
    if (attachedFiles == null || attachedFiles.isEmpty) {
      return (
        images: null,
        documents: null,
        audio: null,
        videos: null,
        otherFiles: null,
      );
    }

    final images = <String>[];
    final documents = <String>[];
    final audio = <String>[];
    final videos = <String>[];
    final otherFiles = <String>[];

    for (final filePath in attachedFiles) {
      final extension = extensionForPath(filePath);

      if (supportedImageExtensions.contains(extension)) {
        images.add(filePath);
      } else if (supportedDocExtensions.contains(extension)) {
        documents.add(filePath);
      } else if (supportedAudioExtensions.contains(extension)) {
        audio.add(filePath);
      } else if (supportedVideoExtensions.contains(extension)) {
        videos.add(filePath);
      } else {
        otherFiles.add(filePath);
      }
    }

    return (
      images: images.isNotEmpty ? images : null,
      documents: documents.isNotEmpty ? documents : null,
      audio: audio.isNotEmpty ? audio : null,
      videos: videos.isNotEmpty ? videos : null,
      otherFiles: otherFiles.isNotEmpty ? otherFiles : null,
    );
  }

  Future<void> checkMissingAttachments({
    required BuildContext context,
    required List<String> allFiles,
  }) async {
    if (allFiles.isEmpty) return;

    final missing = await _storageService.getMissingAttachments(allFiles);

    if (missing.isNotEmpty && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${missing.length} attached file(s) are missing'),
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
                                child: Text('- ${getFileName(path)}'),
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

  static String getFileIcon(String path) {
    final extension = extensionForPath(path);

    if (supportedImageExtensions.contains(extension)) return 'IMG';
    if (supportedAudioExtensions.contains(extension)) return 'AUD';
    if (supportedVideoExtensions.contains(extension)) return 'VID';
    if (extension == '.pdf') return 'PDF';
    if (['.doc', '.docx'].contains(extension)) return 'DOC';
    if (extension == '.txt') return 'TXT';
    if (extension == '.md') return 'MD';
    return 'FILE';
  }

  static IconData getFileIconData(String path) {
    final extension = extensionForPath(path);

    if (supportedImageExtensions.contains(extension)) {
      return Icons.image_outlined;
    }
    if (supportedAudioExtensions.contains(extension)) {
      return Icons.audiotrack_outlined;
    }
    if (supportedVideoExtensions.contains(extension)) {
      return Icons.movie_outlined;
    }
    if (supportedDocExtensions.contains(extension)) {
      return Icons.description_outlined;
    }
    return Icons.attach_file;
  }

  static String getFileName(String path) => path.split(RegExp(r'[\\/]')).last;

  static String extensionForPath(String path) {
    final dotIndex = path.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == path.length - 1) return '';
    return path.substring(dotIndex).toLowerCase();
  }
}

class EmptyChatPlaceholder extends StatelessWidget {
  const EmptyChatPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 56,
            color: colorScheme.onSurfaceVariant.withOpacity(0.55),
          ),
          const SizedBox(height: 14),
          Text(
            'Start a conversation',
            style: TextStyle(
              fontSize: 18,
              color: colorScheme.onSurfaceVariant.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }
}

class ChatMessageBuilder {
  static List<ChatMessage> extractContextMessages(
      List<ChatMessage> allMessages) {
    if (allMessages.length < 2) {
      return <ChatMessage>[];
    }

    return allMessages.sublist(0, allMessages.length - 2);
  }

  static List<Map<String, String>> buildMessagesArray({
    required List<ChatMessage> contextMessages,
    required String currentMessageText,
  }) {
    final messagesArray = <Map<String, String>>[];

    for (final msg in contextMessages) {
      messagesArray.add({
        'role': msg.isUser ? 'user' : 'assistant',
        'content': msg.text,
      });
    }

    messagesArray.add({
      'role': 'user',
      'content': currentMessageText,
    });

    return messagesArray;
  }
}

class ScrollControllerHelper {
  final ScrollController _scrollController;

  bool _isAutoScrollEnabled = true;
  bool _userHasScrolled = false;
  bool _isProgrammaticScroll = false;

  ScrollControllerHelper(this._scrollController);

  bool get isAutoScrollEnabled => _isAutoScrollEnabled;
  bool get userHasScrolled => _userHasScrolled;

  void setupListener({
    required VoidCallback onUserScrolledUp,
    required bool Function() isGenerating,
  }) {
    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;
      if (_isProgrammaticScroll) return;

      if (isGenerating() && _isAutoScrollEnabled) {
        final isAtBottom = _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 50;

        if (!isAtBottom) {
          _isAutoScrollEnabled = false;
          _userHasScrolled = true;
          onUserScrolledUp();
        }
      }
    });
  }

  void resetAutoScroll() {
    _isAutoScrollEnabled = true;
    _userHasScrolled = false;
  }

  void scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _isProgrammaticScroll = true;
        _scrollController
            .animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
        )
            .then((_) {
          _isProgrammaticScroll = false;
        });
      }
    });
  }

  void dispose() {
    _scrollController.dispose();
  }
}

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.34,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (attachedFiles.isNotEmpty)
                _AttachmentPreviewStrip(
                  attachedFiles: attachedFiles,
                  onRemoveFile: onRemoveFile,
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.attach_file,
                      color:
                          attachedFiles.isNotEmpty ? colorScheme.primary : null,
                    ),
                    onPressed: isGenerating ? null : onPickFiles,
                    tooltip: 'Attach files',
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 150),
                      child: Focus(
                        onKeyEvent: (node, event) {
                          final isEnter =
                              event.logicalKey == LogicalKeyboardKey.enter ||
                                  event.logicalKey ==
                                      LogicalKeyboardKey.numpadEnter;
                          final shiftPressed =
                              HardwareKeyboard.instance.isShiftPressed;

                          if (event is KeyDownEvent &&
                              isEnter &&
                              !shiftPressed) {
                            if (!isGenerating) onSendMessage();
                            return KeyEventResult.handled;
                          }

                          return KeyEventResult.ignored;
                        },
                        child: TextField(
                          controller: controller,
                          decoration: InputDecoration(
                            hintText: 'Message or attach files...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                          maxLines: null,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) =>
                              isGenerating ? null : onSendMessage(),
                          enabled: !isGenerating,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    icon: Icon(
                        isGenerating ? Icons.stop_rounded : Icons.send_rounded),
                    onPressed: isGenerating ? onStopGeneration : onSendMessage,
                    tooltip: isGenerating ? 'Stop generation' : 'Send message',
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

class _AttachmentPreviewStrip extends StatelessWidget {
  final List<File> attachedFiles;
  final void Function(int index) onRemoveFile;

  const _AttachmentPreviewStrip({
    required this.attachedFiles,
    required this.onRemoveFile,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: attachedFiles.asMap().entries.map((entry) {
          final index = entry.key;
          final file = entry.value;
          final fileName = FileAttachmentHelper.getFileName(file.path);

          return Container(
            constraints: const BoxConstraints(maxWidth: 220),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  FileAttachmentHelper.getFileIconData(file.path),
                  size: 18,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    fileName,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => onRemoveFile(index),
                  borderRadius: BorderRadius.circular(8),
                  child: Icon(
                    Icons.close,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
