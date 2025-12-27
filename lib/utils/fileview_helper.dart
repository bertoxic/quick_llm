import 'dart:io';
import 'package:flutter/material.dart';
import '../utils/helpers.dart';

class FileAttachmentPreview extends StatelessWidget {
  final List<File> attachedFiles;
  final bool isDarkMode;
  final void Function(int index) onRemoveFile;

  const FileAttachmentPreview({
    super.key,
    required this.attachedFiles,
    required this.isDarkMode,
    required this.onRemoveFile,
  });

  @override
  Widget build(BuildContext context) {
    if (attachedFiles.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[800] : Colors.grey[300],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: attachedFiles.asMap().entries.map((entry) {
          final index = entry.key;
          final file = entry.value;
          return _FileChip(
            filePath: file.path,
            isDarkMode: isDarkMode,
            onRemove: () => onRemoveFile(index),
          );
        }).toList(),
      ),
    );
  }
}

class _FileChip extends StatelessWidget {
  final String filePath;
  final bool isDarkMode;
  final VoidCallback onRemove;

  const _FileChip({
    required this.filePath,
    required this.isDarkMode,
    required this.onRemove,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[700] : Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDarkMode ? Colors.grey[600]! : Colors.grey[400]!,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            FileAttachmentHelper.getFileIcon(filePath),
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              FileAttachmentHelper.getFileName(filePath),
              style: TextStyle(
                fontSize: 14,
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onRemove,
            child: Icon(
              Icons.close,
              size: 18,
              color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}