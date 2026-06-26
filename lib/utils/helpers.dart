import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/chat_message.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

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
    return Center(
      child: Container(
        width: 360,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Creative Chat',
              style: TextStyle(
                color: AppColors.charcoal,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Start with a prompt, attach files, or pick an older conversation from the panel.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
        ),
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
  bool _isDisposed = false;

  ScrollControllerHelper(this._scrollController);

  bool get isAutoScrollEnabled => _isAutoScrollEnabled;
  bool get userHasScrolled => _userHasScrolled;

  void setupListener({
    required VoidCallback onUserScrolledUp,
    required bool Function() isGenerating,
  }) {
    _scrollController.addListener(() {
      if (_isDisposed) return;
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
    if (_isDisposed) return;
    _isAutoScrollEnabled = true;
    _userHasScrolled = false;
  }

  void scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isDisposed) return;
      if (_scrollController.hasClients) {
        _isProgrammaticScroll = true;
        _scrollController
            .animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
        )
            .then((_) {
          if (_isDisposed) return;
          _isProgrammaticScroll = false;
        }).catchError((_) {
          if (_isDisposed) return;
          _isProgrammaticScroll = false;
        });
      }
    });
  }

  void dispose() {
    _isDisposed = true;
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
        maxHeight: MediaQuery.of(context).size.height * 0.38,
      ),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _QuickActionRow(controller: controller),
              const SizedBox(height: 9),
              if (attachedFiles.isNotEmpty)
                _AttachmentPreviewStrip(
                  attachedFiles: attachedFiles,
                  onRemoveFile: onRemoveFile,
                ),
              Container(
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Tooltip(
                      message: 'Attach files',
                      child: IconButton(
                        icon: Icon(
                          Icons.attach_file_rounded,
                          color: attachedFiles.isNotEmpty
                              ? AppColors.orange
                              : AppColors.muted,
                        ),
                        onPressed: isGenerating ? null : onPickFiles,
                      ),
                    ),
                    Expanded(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 132),
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
                            style: TextStyle(color: colorScheme.onSurface),
                            decoration: const InputDecoration(
                              hintText: 'Ask anything...',
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              contentPadding:
                                  EdgeInsets.symmetric(vertical: 14),
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
                    Padding(
                      padding: const EdgeInsets.only(right: 7, bottom: 7),
                      child: Material(
                        color: isGenerating ? AppColors.orange : AppColors.ink,
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          onTap:
                              isGenerating ? onStopGeneration : onSendMessage,
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 36,
                            height: 36,
                            child: Icon(
                              isGenerating
                                  ? Icons.stop_rounded
                                  : Icons.graphic_eq_rounded,
                              color: Colors.white,
                              size: 19,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionRow extends StatelessWidget {
  final TextEditingController controller;

  const _QuickActionRow({required this.controller});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _QuickActionChip(
            icon: Icons.tips_and_updates_outlined,
            label: 'Brainstorm',
            onTap: () => _insertPrompt('Brainstorm ideas for '),
          ),
          _QuickActionChip(
            icon: Icons.public_rounded,
            label: 'Web search',
            onTap: () => _insertPrompt('Web search: '),
          ),
          _QuickActionChip(
            icon: Icons.terminal_rounded,
            label: 'Shell',
            onTap: () => _insertPrompt('Use the shell command runner for: '),
          ),
          _QuickActionChip(
            icon: Icons.folder_open_rounded,
            label: 'Files',
            onTap: () => _insertPrompt('Read or write local files for: '),
          ),
          _QuickActionChip(
            icon: Icons.account_tree_rounded,
            label: 'Planner',
            onTap: () => _insertPrompt('Create a multi-step plan for: '),
          ),
          _QuickActionChip(
            icon: Icons.sticky_note_2_outlined,
            label: 'Notes',
            onTap: () => _insertPrompt('Save a note: '),
          ),
          _QuickActionChip(
            icon: Icons.article_outlined,
            label: 'Scrape URL',
            onTap: () => _insertPrompt('Read this URL: '),
          ),
          _QuickActionChip(
            icon: Icons.manage_search_rounded,
            label: 'RAG',
            onTap: () => _insertPrompt('Search my local documents for: '),
          ),
          _QuickActionChip(
            icon: Icons.code_rounded,
            label: 'Run code',
            onTap: () => _insertPrompt('Run code to analyze: '),
          ),
          const SizedBox(width: 22),
          _QuickActionChip(
            icon: Icons.casino_outlined,
            label: 'Random hints',
            onTap: () => _insertPrompt('Give me a useful hint about '),
          ),
        ],
      ),
    );
  }

  void _insertPrompt(String text) {
    final selection = controller.selection;
    final base = controller.text;
    if (!selection.isValid) {
      controller.text = '$base$text';
      controller.selection =
          TextSelection.collapsed(offset: controller.text.length);
      return;
    }

    final updated = base.replaceRange(selection.start, selection.end, text);
    controller.text = updated;
    controller.selection =
        TextSelection.collapsed(offset: selection.start + text.length);
  }
}

class _QuickActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: Material(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              children: [
                Icon(icon, size: 14, color: AppColors.orange),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: attachedFiles.asMap().entries.map((entry) {
            final index = entry.key;
            final file = entry.value;
            final extension = FileAttachmentHelper.extensionForPath(file.path);
            final isImage = FileAttachmentHelper.supportedImageExtensions
                .contains(extension);

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: isImage
                  ? _ImageAttachmentTile(
                      file: file,
                      onRemove: () => onRemoveFile(index),
                    )
                  : _DocumentAttachmentTile(
                      file: file,
                      onRemove: () => onRemoveFile(index),
                    ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _ImageAttachmentTile extends StatelessWidget {
  final File file;
  final VoidCallback onRemove;

  const _ImageAttachmentTile({
    required this.file,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              file,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return const Center(
                  child: Icon(Icons.broken_image_outlined,
                      color: AppColors.orange),
                );
              },
            ),
          ),
        ),
        Positioned(
          top: 5,
          right: 5,
          child: _RemoveAttachmentButton(onTap: onRemove),
        ),
      ],
    );
  }
}

class _DocumentAttachmentTile extends StatelessWidget {
  final File file;
  final VoidCallback onRemove;

  const _DocumentAttachmentTile({
    required this.file,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final fileName = FileAttachmentHelper.getFileName(file.path);
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 210,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(
            FileAttachmentHelper.getFileIconData(file.path),
            size: 18,
            color: AppColors.teal,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 6),
          _RemoveAttachmentButton(onTap: onRemove),
        ],
      ),
    );
  }
}

class _RemoveAttachmentButton extends StatelessWidget {
  final VoidCallback onTap;

  const _RemoveAttachmentButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.ink.withOpacity(0.78),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: const SizedBox(
          width: 22,
          height: 22,
          child: Icon(Icons.close_rounded, color: Colors.white, size: 14),
        ),
      ),
    );
  }
}
