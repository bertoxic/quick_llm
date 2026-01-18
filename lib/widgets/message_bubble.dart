import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import '../models/chat_message.dart';

// ============================================================================
// Main Message Bubble Widget
// ============================================================================

class MessageBubble extends StatefulWidget {
  final ChatMessage message;
  final bool isDarkMode;
  final VoidCallback? onEdit;
  final VoidCallback? onRegenerate;
  final bool useFullWidth;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isDarkMode,
    this.onEdit,
    this.onRegenerate,
    this.useFullWidth = false,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool _showThinking = false;

  @override
  Widget build(BuildContext context) {
    // Get theme colors
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;

    if (widget.useFullWidth) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: _buildBubbleDecoration(colorScheme),
          child: _buildBubbleContent(),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: widget.message.isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.center, // Center the assistant message
        children: [
          // For user messages, wrap content dynamically with max constraint
          // For assistant messages, use flexible width
          widget.message.isUser
              ? Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: screenWidth * 0.4,
              ),
              padding: const EdgeInsets.all(12),
              decoration: _buildBubbleDecoration(colorScheme),
              child: _buildBubbleContent(),
            ),
          )
              : Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: screenWidth * 0.9,
                minWidth: 100,
              ),
              padding: const EdgeInsets.all(12),
              decoration: _buildBubbleDecoration(colorScheme),
              child: _buildBubbleContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBubbleContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.message.attachedFiles?.isNotEmpty ?? false)
          FileAttachmentsWidget(
            files: widget.message.attachedFiles!,
            isDarkMode: widget.isDarkMode,
          ),
        if (!widget.message.isUser && widget.message.thinkingText != null)
          ThinkingSectionWidget(
            thinkingText: widget.message.thinkingText!,
            isThinking: widget.message.isThinking,
            isDarkMode: widget.isDarkMode,
            showThinking: _showThinking,
            onToggle: () => setState(() => _showThinking = !_showThinking),
          ),
        if (widget.message.text.isNotEmpty)
          MarkdownContentWidget(
            text: widget.message.text,
            isUser: widget.message.isUser,
            isDarkMode: widget.isDarkMode,
          ),
        const SizedBox(height: 4),
        MessageMetadataWidget(
          timestamp: widget.message.timestamp,
          modelName: widget.message.modelName,
          isUser: widget.message.isUser,
          isDarkMode: widget.isDarkMode,
        ),
        if (!widget.message.isUser || widget.onEdit != null)
          MessageActionButtons(
            text: widget.message.text,
            onEdit: widget.onEdit,
            onRegenerate: widget.onRegenerate,
          ),
      ],
    );
  }

  BoxDecoration _buildBubbleDecoration(ColorScheme colorScheme) {
    if (widget.message.isUser) {
      // User message - use primary color variants
      return BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      );
    } else {
      // AI message - use surface variants
      return BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.01),
        borderRadius: BorderRadius.circular(12),
      );
    }
  }
}

// ============================================================================
// Markdown Content Widget
// ============================================================================

class MarkdownContentWidget extends StatelessWidget {
  final String text;
  final bool isUser;
  final bool isDarkMode;

  const MarkdownContentWidget({
    super.key,
    required this.text,
    required this.isUser,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;

    return MarkdownWidget(
      data: text,
      shrinkWrap: true,
      selectable: true,
      padding: EdgeInsets.zero,
      config: MarkdownConfig(
        configs: [
          PConfig(
            textStyle: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: textColor,
            ),
          ),
          ..._buildHeadingConfigs(textColor),
          _buildCodeConfig(theme),
          _buildPreConfig(context, theme),
          _buildBlockquoteConfig(theme),
          _buildLinkConfig(context, theme),
          HrConfig(
            height: 1,
            color: theme.dividerColor,
          ),
          _buildImageConfig(theme),
          ListConfig(
            marker: (isOrdered, depth, index) =>
                _buildListMarker(isOrdered, index, textColor),
          ),
        ],
      ),
    );
  }

  List<WidgetConfig> _buildHeadingConfigs(Color textColor) {
    return [
      H1Config(style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textColor, height: 1.3)),
      H2Config(style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor, height: 1.3)),
      H3Config(style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor, height: 1.3)),
      H4Config(style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor, height: 1.3)),
      H5Config(style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textColor, height: 1.3)),
      H6Config(style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textColor, height: 1.3)),
    ];
  }

  CodeConfig _buildCodeConfig(ThemeData theme) {
    return CodeConfig(
      style: TextStyle(
        fontSize: 13,
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        color: theme.colorScheme.error,
        fontFamily: 'monospace',
        fontWeight: FontWeight.w600,
      ),
    );
  }

  PreConfig _buildPreConfig(BuildContext context, ThemeData theme) {
    return PreConfig(
      theme: isDarkMode ? atomOneDarkTheme : atomOneLightTheme,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.dividerColor,
          width: 1,
        ),
      ),
      textStyle: const TextStyle(fontSize: 13, fontFamily: 'monospace', height: 1.4),
      wrapper: (child, code, language) => CodeBlockWrapper(
        child: child,
        code: code,
        isDarkMode: isDarkMode,
      ),
    );
  }

  BlockquoteConfig _buildBlockquoteConfig(ThemeData theme) {
    return BlockquoteConfig(
      textColor: theme.colorScheme.onSurface.withOpacity(0.7),
      sideColor: theme.colorScheme.primary,
      sideWith: 4.0,
      padding: const EdgeInsets.fromLTRB(16, 2, 0, 2),
      margin: const EdgeInsets.fromLTRB(0, 8, 0, 8),
    );
  }

  LinkConfig _buildLinkConfig(BuildContext context, ThemeData theme) {
    return LinkConfig(
      style: TextStyle(
        color: theme.colorScheme.primary,
        decoration: TextDecoration.underline,
        fontSize: 14,
      ),
      onTap: (url) => _handleLinkTap(url, context),
    );
  }

  Future<void> _handleLinkTap(String url, BuildContext context) async {
    try {
      String finalUrl = url.startsWith('http') ? url : 'https://$url';
      final uri = Uri.parse(finalUrl);

      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);

      if (!launched && context.mounted) {
        _showSnackBar(context, 'Could not open link: $url');
      }
    } catch (e) {
      if (context.mounted) {
        _showSnackBar(context, 'Error opening link: $e');
      }
    }
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  ImgConfig _buildImageConfig(ThemeData theme) {
    return ImgConfig(
      builder: (url, attributes) => Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.dividerColor),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            url,
            errorBuilder: (context, error, stackTrace) => _buildImageError(theme),
          ),
        ),
      ),
    );
  }

  Widget _buildImageError(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Icon(Icons.broken_image, color: theme.colorScheme.error),
          const SizedBox(height: 8),
          Text(
            'Failed to load image',
            style: TextStyle(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListMarker(bool isOrdered, int index, Color textColor) {
    return Text(
      isOrdered ? '${index + 1}. ' : '• ',
      style: TextStyle(color: textColor, fontSize: 14),
    );
  }
}

// ============================================================================
// Code Block Wrapper with Copy Button
// ============================================================================

class CodeBlockWrapper extends StatelessWidget {
  final Widget child;
  final String code;
  final bool isDarkMode;

  const CodeBlockWrapper({
    super.key,
    required this.child,
    required this.code,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Stack(
        children: [
          child,
          Positioned(
            top: 8,
            right: 8,
            child: CopyCodeButton(code: code, isDarkMode: isDarkMode),
          ),
        ],
      ),
    );
  }
}

class CopyCodeButton extends StatefulWidget {
  final String code;
  final bool isDarkMode;

  const CopyCodeButton({super.key, required this.code, required this.isDarkMode});

  @override
  State<CopyCodeButton> createState() => _CopyCodeButtonState();
}

class _CopyCodeButtonState extends State<CopyCodeButton> {
  bool _copied = false;

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: widget.code));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _copyCode,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withOpacity(0.9),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: theme.dividerColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _copied ? Icons.check : Icons.copy,
                size: 14,
                color: _copied ? colorScheme.primary : colorScheme.onSurface,
              ),
              const SizedBox(width: 4),
              Text(
                _copied ? 'Copied!' : 'Copy',
                style: TextStyle(
                  fontSize: 11,
                  color: _copied ? colorScheme.primary : colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// File Attachments Widget
// ============================================================================

class FileAttachmentsWidget extends StatelessWidget {
  final List<String> files;
  final bool isDarkMode;

  const FileAttachmentsWidget({
    super.key,
    required this.files,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: files.map((path) => FilePreviewWidget(filePath: path, isDarkMode: isDarkMode)).toList(),
      ),
    );
  }
}

class FilePreviewWidget extends StatelessWidget {
  final String filePath;
  final bool isDarkMode;

  const FilePreviewWidget({
    super.key,
    required this.filePath,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    final fileName = filePath.split('/').last;
    final extension = filePath.toLowerCase().substring(filePath.lastIndexOf('.'));
    final isImage = ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'].contains(extension);

    return isImage
        ? ImagePreviewWidget(filePath: filePath, fileName: fileName)
        : DocumentPreviewWidget(fileName: fileName, extension: extension, isDarkMode: isDarkMode);
  }
}

class ImagePreviewWidget extends StatelessWidget {
  final String filePath;
  final String fileName;

  const ImagePreviewWidget({
    super.key,
    required this.filePath,
    required this.fileName,
  });

  @override
  Widget build(BuildContext context) {
    final file = File(filePath);

    if (!file.existsSync()) {
      return _buildErrorPreview(context);
    }

    return GestureDetector(
      onTap: () => _showFullImage(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          file,
          width: 150,
          height: 150,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _buildErrorPreview(context),
        ),
      ),
    );
  }

  Widget _buildErrorPreview(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 150,
      height: 150,
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.error),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 40, color: colorScheme.error),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              'File not found',
              style: TextStyle(fontSize: 10, color: colorScheme.onErrorContainer),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  void _showFullImage(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: InteractiveViewer(child: Image.file(File(filePath))),
      ),
    );
  }
}

class DocumentPreviewWidget extends StatelessWidget {
  final String fileName;
  final String extension;
  final bool isDarkMode;

  const DocumentPreviewWidget({
    super.key,
    required this.fileName,
    required this.extension,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_getFileIcon(extension), style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(
              fileName,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: colorScheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  String _getFileIcon(String ext) {
    if (ext == '.pdf') return '📄';
    if (['.doc', '.docx'].contains(ext)) return '📝';
    if (ext == '.txt') return '📃';
    if (ext == '.md') return '📋';
    return '📄';
  }
}

// ============================================================================
// Thinking Section Widget
// ============================================================================

class ThinkingSectionWidget extends StatelessWidget {
  final String thinkingText;
  final bool isThinking;
  final bool isDarkMode;
  final bool showThinking;
  final VoidCallback onToggle;

  const ThinkingSectionWidget({
    super.key,
    required this.thinkingText,
    required this.isThinking,
    required this.isDarkMode,
    required this.showThinking,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onToggle,
            child: Row(
              children: [
                Icon(
                  showThinking ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: colorScheme.onSurface.withOpacity(0.6),
                ),
                const SizedBox(width: 4),
                Text(
                  isThinking ? 'Thinking...' : 'View thinking process',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurface.withOpacity(0.6),
                    fontStyle: FontStyle.italic,
                  ),
                ),
                if (isThinking)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (showThinking) ...[
            const SizedBox(height: 8),
            SelectableText(
              thinkingText,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurface.withOpacity(0.7),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================================
// Message Metadata Widget
// ============================================================================

class MessageMetadataWidget extends StatelessWidget {
  final DateTime timestamp;
  final String? modelName;
  final bool isUser;
  final bool isDarkMode;

  const MessageMetadataWidget({
    super.key,
    required this.timestamp,
    this.modelName,
    required this.isUser,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface.withOpacity(0.6);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _formatTimestamp(timestamp),
          style: TextStyle(
            fontSize: 10,
            color: textColor,
          ),
        ),
        if (!isUser && modelName != null) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '• $modelName',
              style: TextStyle(fontSize: 10, color: textColor),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final difference = DateTime.now().difference(timestamp);
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inHours < 1) return '${difference.inMinutes}m ago';
    if (difference.inDays < 1) return '${difference.inHours}h ago';
    return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
  }
}

// ============================================================================
// Message Action Buttons
// ============================================================================

class MessageActionButtons extends StatelessWidget {
  final String text;
  final VoidCallback? onEdit;
  final VoidCallback? onRegenerate;

  const MessageActionButtons({
    super.key,
    required this.text,
    this.onEdit,
    this.onRegenerate,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ActionButton(
            icon: Icons.copy,
            tooltip: 'Copy',
            onPressed: () => _copyToClipboard(context),
          ),
          if (onEdit != null) ...[
            const SizedBox(width: 8),
            _ActionButton(icon: Icons.edit, tooltip: 'Edit', onPressed: onEdit!),
          ],
          if (onRegenerate != null) ...[
            const SizedBox(width: 8),
            _ActionButton(icon: Icons.refresh, tooltip: 'Regenerate', onPressed: onRegenerate!),
          ],
        ],
      ),
    );
  }

  void _copyToClipboard(BuildContext context) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard'), duration: Duration(seconds: 1)),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 16),
      onPressed: onPressed,
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
    );
  }
}