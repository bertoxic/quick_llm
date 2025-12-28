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
  final bool useFullWidth; // New parameter for mini mode

  const MessageBubble({
    super.key,
    required this.message,
    required this.isDarkMode,
    this.onEdit,
    this.onRegenerate,
    this.useFullWidth = false, // Default to false for backward compatibility
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool _showThinking = false;

  @override
  Widget build(BuildContext context) {
    // If using full width, skip the Row wrapper and constraints
    if (widget.useFullWidth) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: _buildBubbleDecoration(),
          child: _buildBubbleContent(),
        ),
      );
    }

    // Original behavior for non-mini mode
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: widget.message.isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding: const EdgeInsets.all(12),
              decoration: _buildBubbleDecoration(),
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

  BoxDecoration _buildBubbleDecoration() {
    return BoxDecoration(
      color: widget.message.isUser
          ? (widget.isDarkMode ? const Color(0xFF1E3A8A) : const Color(0xFFDEEBFF))
          : (widget.isDarkMode ? const Color(0xFF2A2A2A) : Colors.grey[300]),
      borderRadius: BorderRadius.circular(12),
    );
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
    final textColor = isDarkMode ? Colors.white : Colors.black87;

    return MarkdownWidget(
      data: text,
      shrinkWrap: true,
      selectable: true,
      padding: EdgeInsets.zero,
      config: MarkdownConfig(
        configs: [
          const PConfig(textStyle: TextStyle(fontSize: 14, height: 1.5)),
          ..._buildHeadingConfigs(textColor),
          _buildCodeConfig(),
          _buildPreConfig(context),
          _buildBlockquoteConfig(),
          _buildLinkConfig(context),
          HrConfig(
            height: 1,
            color: isDarkMode ? Colors.grey.shade600 : Colors.grey.shade300,
          ),
          _buildImageConfig(),
          ListConfig(marker: (isOrdered, depth, index) => _buildListMarker(isOrdered, index, textColor)),
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

  CodeConfig _buildCodeConfig() {
    return CodeConfig(
      style: TextStyle(
        fontSize: 13,
        backgroundColor: isDarkMode ? const Color(0xFF2D2D2D) : const Color(0xFFF5F5F5),
        color: isDarkMode ? const Color(0xFFDD5353) : const Color(0xFF9E3B3B),
        fontFamily: 'monospace',
        fontWeight: FontWeight.w600,
        shadows: [
          Shadow(
            color: isDarkMode ? const Color(0xFF070707) : const Color(0xFFE0E0E0),
            blurRadius: 4,
            offset: const Offset(2, 3),
          ),
        ],
      ),
    );
  }

  PreConfig _buildPreConfig(BuildContext context) {
    return PreConfig(
      theme: isDarkMode ? atomOneDarkTheme : atomOneLightTheme,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[900] : Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDarkMode ? Colors.grey[700]! : Colors.grey[400]!,
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

  BlockquoteConfig _buildBlockquoteConfig() {
    return BlockquoteConfig(
      textColor: isDarkMode ? Colors.white70 : Colors.black54,
      sideColor: isDarkMode ? Colors.white60 : Colors.black45,
      sideWith: 4.0,
      padding: const EdgeInsets.fromLTRB(16, 2, 0, 2),
      margin: const EdgeInsets.fromLTRB(0, 8, 0, 8),
    );
  }

  LinkConfig _buildLinkConfig(BuildContext context) {
    return LinkConfig(
      style: TextStyle(
        color: isDarkMode ? Colors.blue[300] : Colors.blue[700],
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
      SnackBar(content: Text(message), backgroundColor: Colors.red[700]),
    );
  }

  ImgConfig _buildImageConfig() {
    return ImgConfig(
      builder: (url, attributes) => Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isDarkMode ? Colors.grey[700]! : Colors.grey[400]!),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            url,
            errorBuilder: (context, error, stackTrace) => _buildImageError(),
          ),
        ),
      ),
    );
  }

  Widget _buildImageError() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Icon(Icons.broken_image, color: Colors.grey[600]),
          const SizedBox(height: 8),
          Text('Failed to load image', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _copyCode,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: (widget.isDarkMode ? Colors.grey[800] : Colors.grey[200])!.withOpacity(0.9),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: widget.isDarkMode ? Colors.grey[700]! : Colors.grey[400]!),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _copied ? Icons.check : Icons.copy,
                size: 14,
                color: _copied ? Colors.green : (widget.isDarkMode ? Colors.grey[300] : Colors.grey[700]),
              ),
              const SizedBox(width: 4),
              Text(
                _copied ? 'Copied!' : 'Copy',
                style: TextStyle(
                  fontSize: 11,
                  color: _copied ? Colors.green : (widget.isDarkMode ? Colors.grey[300] : Colors.grey[700]),
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
      return _buildErrorPreview();
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
          errorBuilder: (context, error, stackTrace) => _buildErrorPreview(),
        ),
      ),
    );
  }

  Widget _buildErrorPreview() {
    return Container(
      width: 150,
      height: 150,
      decoration: BoxDecoration(
        color: Colors.red[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red[300]!),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 40, color: Colors.red[700]),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text('File not found', style: TextStyle(fontSize: 10), textAlign: TextAlign.center),
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
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[700] : Colors.grey[200],
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isDarkMode ? Colors.grey[600]! : Colors.grey[400]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_getFileIcon(extension), style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(fileName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[800] : Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDarkMode ? Colors.grey[700]! : Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onToggle,
            child: Row(
              children: [
                Icon(showThinking ? Icons.expand_less : Icons.expand_more, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  isThinking ? 'Thinking...' : 'View thinking process',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
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
                        color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
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
                color: isDarkMode ? Colors.grey[400] : Colors.grey[700],
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _formatTimestamp(timestamp),
          style: TextStyle(
            fontSize: 10,
            color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
        if (!isUser && modelName != null) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '• $modelName',
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
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