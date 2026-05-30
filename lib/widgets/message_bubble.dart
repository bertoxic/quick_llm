import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/chat_message.dart';
import '../theme/app_theme.dart';
import '../utils/helpers.dart';

class MessageBubble extends StatefulWidget {
  final ChatMessage message;
  final bool isDarkMode;
  final ValueChanged<String>? onEdit;
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
  late final TextEditingController _editController;
  final FocusNode _editFocusNode = FocusNode();
  bool _showThinking = false;
  bool _showDetails = false;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _editController = TextEditingController(text: widget.message.text);
  }

  @override
  void didUpdateWidget(covariant MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isEditing && oldWidget.message.text != widget.message.text) {
      _editController.text = widget.message.text;
    }
  }

  @override
  void dispose() {
    _editController.dispose();
    _editFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.message.isUser) {
      return _buildUserMessage(context);
    }
    return _buildAssistantMessage(context);
  }

  Widget _buildUserMessage(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final maxWidth = width * 0.70;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (widget.message.attachedFiles?.isNotEmpty ?? false)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: FileAttachmentsWidget(
                        files: widget.message.attachedFiles!,
                        isDarkMode: widget.isDarkMode,
                        alignEnd: true,
                      ),
                    ),
                  _buildUserTextBubble(context),
                  const SizedBox(height: 5),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MessageMetadataWidget(
                        timestamp: widget.message.timestamp,
                        isUser: true,
                        isDarkMode: widget.isDarkMode,
                      ),
                      if (widget.onEdit != null && !_isEditing) ...[
                        const SizedBox(width: 8),
                        MessageActionButtons(
                          text: widget.message.text,
                          onEdit: _startEditing,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: AppColors.ink,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: Colors.white, width: 2),
            ),
            child:
                const Icon(Icons.person_rounded, size: 15, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildUserTextBubble(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.orange,
        borderRadius: BorderRadius.circular(8),
      ),
      child: _isEditing
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _editController,
                  focusNode: _editFocusNode,
                  minLines: 1,
                  maxLines: null,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                  cursorColor: Colors.white,
                  decoration: const InputDecoration(
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _InlineEditButton(
                      label: 'Cancel',
                      icon: Icons.close_rounded,
                      onTap: _cancelEditing,
                    ),
                    const SizedBox(width: 8),
                    _InlineEditButton(
                      label: 'Save',
                      icon: Icons.check_rounded,
                      onTap: _saveEditing,
                    ),
                  ],
                ),
              ],
            )
          : MarkdownContentWidget(
              text: widget.message.text,
              isUser: true,
              isDarkMode: widget.isDarkMode,
            ),
    );
  }

  void _startEditing() {
    setState(() {
      _isEditing = true;
      _editController.text = widget.message.text;
      _editController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _editController.text.length,
      );
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _editFocusNode.requestFocus();
    });
  }

  void _cancelEditing() {
    setState(() {
      _isEditing = false;
      _editController.text = widget.message.text;
    });
  }

  void _saveEditing() {
    final nextText = _editController.text.trim();
    if (nextText.isEmpty) return;

    setState(() => _isEditing = false);
    if (nextText != widget.message.text) {
      widget.onEdit?.call(nextText);
    }
  }

  Widget _buildAssistantMessage(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final maxWidth = widget.useFullWidth ? width * 0.92 : width * 0.70;
    final toolActivities = _ToolActivityData.fromMessage(widget.message);
    final messageContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.message.attachedFiles?.isNotEmpty ?? false)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: FileAttachmentsWidget(
              files: widget.message.attachedFiles!,
              isDarkMode: widget.isDarkMode,
            ),
          ),
        if (widget.message.thinkingText != null)
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
            isUser: false,
            isDarkMode: widget.isDarkMode,
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            MessageMetadataWidget(
              timestamp: widget.message.timestamp,
              modelName: widget.message.modelName,
              isUser: false,
              isDarkMode: widget.isDarkMode,
            ),
            const Spacer(),
            MessageActionButtons(
              text: widget.message.text,
              onRegenerate: widget.onRegenerate,
            ),
          ],
        ),
        MessageDetailsDisclosure(
          message: widget.message,
          isExpanded: _showDetails,
          onToggle: () => setState(() => _showDetails = !_showDetails),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (toolActivities.isEmpty) return messageContent;

              final sidebar = _ToolActivitySidebar(
                activities: toolActivities,
                isDarkMode: widget.isDarkMode,
              );

              if (constraints.maxWidth >= 640) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 236, child: sidebar),
                    const SizedBox(width: 14),
                    Expanded(child: messageContent),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  sidebar,
                  const SizedBox(height: 10),
                  messageContent,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

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
    final isDark = theme.brightness == Brightness.dark;
    final textColor = isUser ? Colors.white : theme.colorScheme.onSurface;
    final blockSurface =
        isDark ? theme.colorScheme.surfaceContainerHigh : Colors.white;
    final inlineCodeBackground =
        isUser ? Colors.white24 : theme.colorScheme.surfaceContainerHighest;
    final lineColor = theme.colorScheme.outlineVariant;

    return MarkdownWidget(
      data: text,
      shrinkWrap: true,
      selectable: true,
      padding: EdgeInsets.zero,
      config: MarkdownConfig(
        configs: [
          PConfig(
            textStyle: TextStyle(fontSize: 13, height: 1.45, color: textColor),
          ),
          H1Config(style: _headingStyle(22, textColor)),
          H2Config(style: _headingStyle(19, textColor)),
          H3Config(style: _headingStyle(17, textColor)),
          H4Config(style: _headingStyle(15, textColor)),
          H5Config(style: _headingStyle(14, textColor)),
          H6Config(style: _headingStyle(13, textColor)),
          CodeConfig(
            style: TextStyle(
              fontSize: 12,
              backgroundColor: inlineCodeBackground,
              color: isUser ? Colors.white : AppColors.orange,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
            ),
          ),
          PreConfig(
            theme: atomOneLightTheme,
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: blockSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: lineColor),
            ),
            textStyle: const TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              height: 1.45,
            ),
            wrapper: (child, code, language) => CodeBlockWrapper(
              child: child,
              code: code,
              language: language,
              isDarkMode: isDarkMode,
            ),
          ),
          BlockquoteConfig(
            textColor: textColor.withOpacity(0.74),
            sideColor: isUser ? Colors.white : AppColors.teal,
            sideWith: 3,
            padding: const EdgeInsets.fromLTRB(14, 2, 0, 2),
            margin: const EdgeInsets.symmetric(vertical: 8),
          ),
          LinkConfig(
            style: TextStyle(
              color: isUser ? Colors.white : AppColors.orange,
              decoration: TextDecoration.underline,
              fontSize: 13,
            ),
            onTap: (url) => _handleLinkTap(url, context),
          ),
          HrConfig(height: 1, color: isUser ? Colors.white38 : lineColor),
          ImgConfig(
            builder: (url, attributes) => ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                url,
                errorBuilder: (context, error, stackTrace) => Container(
                  height: 110,
                  color: AppColors.softOrange,
                  child: const Center(
                    child: Icon(Icons.broken_image_outlined,
                        color: AppColors.orange),
                  ),
                ),
              ),
            ),
          ),
          ListConfig(
            marker: (isOrdered, depth, index) => Text(
              isOrdered ? '${index + 1}. ' : '- ',
              style: TextStyle(color: textColor, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _headingStyle(double size, Color color) {
    return TextStyle(
      fontSize: size,
      height: 1.25,
      color: color,
      fontWeight: FontWeight.w800,
    );
  }

  Future<void> _handleLinkTap(String url, BuildContext context) async {
    try {
      final uri = Uri.parse(url.startsWith('http') ? url : 'https://$url');
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open link: $url')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening link: $e')),
        );
      }
    }
  }
}

class CodeBlockWrapper extends StatelessWidget {
  final Widget child;
  final String code;
  final String? language;
  final bool isDarkMode;

  const CodeBlockWrapper({
    super.key,
    required this.child,
    required this.code,
    required this.language,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    final isSvg = _isSvgBlock(code, language);
    final codeBlock = Stack(
      children: [
        child,
        Positioned(
          top: 8,
          right: 8,
          child: CopyCodeButton(code: code, isDarkMode: isDarkMode),
        ),
      ],
    );

    if (!isSvg) return codeBlock;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SvgSketchPreview(svg: code),
        codeBlock,
      ],
    );
  }

  bool _isSvgBlock(String source, String? language) {
    final lang = language?.trim().toLowerCase();
    return lang == 'svg' || source.trimLeft().startsWith('<svg');
  }
}

/// Renders an SVG string inline as a preview above its code block.
/// Falls back to an error card if the SVG is malformed or empty.
class SvgSketchPreview extends StatelessWidget {
  final String svg;

  const SvgSketchPreview({super.key, required this.svg});

  @override
  Widget build(BuildContext context) {
    final trimmed = svg.trim();
    if (trimmed.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 400),
        child: SvgPicture.string(
          trimmed,
          fit: BoxFit.contain,
          placeholderBuilder: (context) => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineEditButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _InlineEditButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.16),
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: Colors.white),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CopyCodeButton extends StatefulWidget {
  final String code;
  final bool isDarkMode;

  const CopyCodeButton({
    super.key,
    required this.code,
    required this.isDarkMode,
  });

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
      color: Colors.white,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        onTap: _copyCode,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _copied ? Icons.check_rounded : Icons.copy_rounded,
                size: 13,
                color: _copied ? AppColors.teal : AppColors.muted,
              ),
              const SizedBox(width: 4),
              Text(
                _copied ? 'Copied' : 'Copy code',
                style: TextStyle(
                  fontSize: 10,
                  color: _copied ? AppColors.teal : AppColors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FileAttachmentsWidget extends StatelessWidget {
  final List<String> files;
  final bool isDarkMode;
  final bool alignEnd;

  const FileAttachmentsWidget({
    super.key,
    required this.files,
    required this.isDarkMode,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: alignEnd ? WrapAlignment.end : WrapAlignment.start,
      spacing: 8,
      runSpacing: 8,
      children: files
          .map((path) =>
              FilePreviewWidget(filePath: path, isDarkMode: isDarkMode))
          .toList(),
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
    final fileName = FileAttachmentHelper.getFileName(filePath);
    final extension = FileAttachmentHelper.extensionForPath(filePath);
    final isImage =
        FileAttachmentHelper.supportedImageExtensions.contains(extension);

    return isImage
        ? ImagePreviewWidget(filePath: filePath, fileName: fileName)
        : DocumentPreviewWidget(fileName: fileName, extension: extension);
  }
}

class _ToolActivitySidebar extends StatelessWidget {
  final List<_ToolActivityData> activities;
  final bool isDarkMode;

  const _ToolActivitySidebar({
    required this.activities,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    if (activities.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final surface =
        isDarkMode ? colorScheme.surfaceContainerHigh : Colors.white;
    final activeAccent = activities.any((item) => item.id == 'web_search')
        ? AppColors.teal
        : AppColors.orange;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: activeAccent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.auto_awesome_mosaic_outlined,
                          size: 16,
                          color: activeAccent,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Tool activity',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        _ToolCountBadge(count: activities.length),
                      ],
                    ),
                    const SizedBox(height: 9),
                    ...activities.map(
                      (activity) => _ToolActivityTile(activity: activity),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolCountBadge extends StatelessWidget {
  final int count;

  const _ToolCountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.softTeal,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: AppColors.charcoal,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ToolActivityTile extends StatelessWidget {
  final _ToolActivityData activity;

  const _ToolActivityTile({required this.activity});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = _accentFor(activity.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(_iconFor(activity.id), size: 16, color: accent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activity.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 11,
                        height: 1.15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      children: [
                        _MiniToolBadge(
                          label: _statusLabel(activity.status),
                          color: _statusColor(activity.status),
                        ),
                        _MiniToolBadge(
                          label: activity.uiSurface,
                          color: AppColors.teal,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            activity.summary,
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.74),
              fontSize: 10,
              height: 1.3,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (activity.output?.isNotEmpty == true) ...[
            const SizedBox(height: 7),
            _ToolOutputPill(
              icon: Icons.done_rounded,
              label: activity.output!,
              color: AppColors.teal,
            ),
          ],
          if (activity.error?.isNotEmpty == true) ...[
            const SizedBox(height: 7),
            _ToolOutputPill(
              icon: Icons.error_outline_rounded,
              label: activity.error!,
              color: AppColors.orange,
            ),
          ],
          if (activity.steps.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...activity.steps.take(3).map(
                  (step) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(
                            activity.status == 'complete'
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_checked_rounded,
                            size: 10,
                            color: accent,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            step,
                            style: TextStyle(
                              color:
                                  colorScheme.onSurface.withValues(alpha: 0.68),
                              fontSize: 10,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
          if (activity.sources.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...activity.sources.take(3).map(
                  (source) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.link_rounded,
                          size: 10,
                          color: AppColors.teal,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            source.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.68,
                              ),
                              fontSize: 10,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }

  static IconData _iconFor(String id) {
    switch (id) {
      case 'shell_command_runner':
        return Icons.terminal_rounded;
      case 'file_reader_writer':
        return Icons.folder_open_rounded;
      case 'multi_step_planner':
        return Icons.account_tree_rounded;
      case 'web_search':
        return Icons.public_rounded;
      case 'note_saver':
        return Icons.sticky_note_2_outlined;
      case 'web_scraper_reader':
        return Icons.article_outlined;
      case 'local_document_search':
        return Icons.manage_search_rounded;
      case 'code_executor':
        return Icons.data_object_rounded;
      case 'calculator':
        return Icons.calculate_outlined;
      case 'svg_sketch':
        return Icons.polyline_outlined;
      default:
        return Icons.extension_rounded;
    }
  }

  static Color _accentFor(String id) {
    switch (id) {
      case 'web_search':
      case 'local_document_search':
      case 'web_scraper_reader':
        return AppColors.teal;
      case 'calculator':
      case 'code_executor':
        return AppColors.orange;
      default:
        return AppColors.charcoal;
    }
  }

  static Color _statusColor(String status) {
    switch (status) {
      case 'complete':
        return AppColors.teal;
      case 'failed':
      case 'unavailable':
        return AppColors.orange;
      case 'ready':
        return AppColors.orange;
      default:
        return AppColors.muted;
    }
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'complete':
        return 'Complete';
      case 'failed':
        return 'Failed';
      case 'unavailable':
        return 'Unavailable';
      case 'ready':
        return 'Ready';
      default:
        return 'Queued';
    }
  }
}

class _ToolOutputPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _ToolOutputPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 10,
                height: 1.25,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniToolBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _MiniToolBadge({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 9,
          height: 1,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ToolActivityData {
  final String id;
  final String title;
  final String status;
  final String summary;
  final String uiSurface;
  final List<String> steps;
  final String? output;
  final String? error;
  final List<_ToolSourceData> sources;

  const _ToolActivityData({
    required this.id,
    required this.title,
    required this.status,
    required this.summary,
    required this.uiSurface,
    required this.steps,
    this.output,
    this.error,
    this.sources = const [],
  });

  static List<_ToolActivityData> fromMessage(ChatMessage message) {
    final tools = _extractToolDetails(message.details);
    if (tools == null) return const [];

    final rawActivity = tools['activity'];
    if (rawActivity is! List) return const [];

    return rawActivity
        .whereType<Map>()
        .map((item) => _ToolActivityData.fromMap(item))
        .where((item) => item.title.isNotEmpty)
        .toList();
  }

  factory _ToolActivityData.fromMap(Map<dynamic, dynamic> map) {
    final rawSteps = map['steps'];
    return _ToolActivityData(
      id: '${map['id'] ?? ''}',
      title: '${map['title'] ?? ''}',
      status: '${map['status'] ?? 'queued'}',
      summary: '${map['summary'] ?? ''}',
      uiSurface: '${map['ui_surface'] ?? 'Activity sidebar'}',
      steps: rawSteps is List
          ? rawSteps
              .map((step) => '$step')
              .where((step) => step.isNotEmpty)
              .toList()
          : const [],
      output: map['output'] == null ? null : '${map['output']}',
      error: map['error'] == null ? null : '${map['error']}',
      sources: map['sources'] is List
          ? (map['sources'] as List)
              .whereType<Map>()
              .map((source) => _ToolSourceData.fromMap(source))
              .toList()
          : const [],
    );
  }

  static Map<String, dynamic>? _extractToolDetails(
    Map<String, dynamic>? details,
  ) {
    if (details == null) return null;

    final topLevelTools = details['tools'];
    if (topLevelTools is Map) {
      return Map<String, dynamic>.from(topLevelTools);
    }

    final request = details['request'];
    if (request is Map) {
      final requestTools = request['tools'];
      if (requestTools is Map) {
        return Map<String, dynamic>.from(requestTools);
      }
    }

    return null;
  }
}

class _ToolSourceData {
  final String title;
  final String url;

  const _ToolSourceData({
    required this.title,
    required this.url,
  });

  factory _ToolSourceData.fromMap(Map<dynamic, dynamic> map) {
    return _ToolSourceData(
      title: '${map['title'] ?? map['url'] ?? 'Source'}',
      url: '${map['url'] ?? ''}',
    );
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

    return GestureDetector(
      onTap: file.existsSync() ? () => _showFullImage(context) : null,
      child: Container(
        width: 138,
        height: 138,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.line),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: file.existsSync()
              ? Image.file(
                  file,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      _buildMissingPreview(),
                )
              : _buildMissingPreview(),
        ),
      ),
    );
  }

  Widget _buildMissingPreview() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.broken_image_outlined, color: AppColors.orange),
          SizedBox(height: 6),
          Text(
            'File not found',
            style: TextStyle(color: AppColors.muted, fontSize: 10),
          ),
        ],
      ),
    );
  }

  void _showFullImage(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: InteractiveViewer(child: Image.file(File(filePath))),
        ),
      ),
    );
  }
}

class DocumentPreviewWidget extends StatelessWidget {
  final String fileName;
  final String extension;

  const DocumentPreviewWidget({
    super.key,
    required this.fileName,
    required this.extension,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 210),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            FileAttachmentHelper.getFileIconData(extension),
            size: 17,
            color: AppColors.teal,
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              fileName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.charcoal,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    showThinking
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_right_rounded,
                    size: 16,
                    color: AppColors.muted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isThinking ? 'Thinking...' : 'View thinking',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (isThinking) ...[
                    const SizedBox(width: 8),
                    const SizedBox(
                      width: 11,
                      height: 11,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (showThinking)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: MarkdownContentWidget(
                text: thinkingText,
                isUser: false,
                isDarkMode: isDarkMode,
              ),
            ),
        ],
      ),
    );
  }
}

class MessageDetailsDisclosure extends StatelessWidget {
  final ChatMessage message;
  final bool isExpanded;
  final VoidCallback onToggle;

  const MessageDetailsDisclosure({
    super.key,
    required this.message,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_right_rounded,
                    size: 17,
                    color: AppColors.muted,
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Details',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${message.estimatedTokenCount} est. tokens',
                    style:
                        const TextStyle(color: AppColors.muted, fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _MessageDetailsPanel(message: message),
            ),
        ],
      ),
    );
  }
}

class _MessageDetailsPanel extends StatelessWidget {
  final ChatMessage message;

  const _MessageDetailsPanel({required this.message});

  @override
  Widget build(BuildContext context) {
    final details = <_DetailRow>[
      _DetailRow('Role', message.isUser ? 'user' : 'assistant'),
      _DetailRow('Created', message.timestamp.toLocal().toIso8601String()),
      _DetailRow('Characters', message.text.length.toString()),
      _DetailRow('Estimated tokens', message.estimatedTokenCount.toString()),
      if (message.modelName != null) _DetailRow('Model', message.modelName!),
      if (message.thinkingText?.isNotEmpty == true)
        _DetailRow(
            'Thinking characters', message.thinkingText!.length.toString()),
      if (message.attachedFiles?.isNotEmpty == true)
        _DetailRow('Attachments', message.attachedFiles!.length.toString()),
    ];

    final customDetails = message.details;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...details.map((row) => _DetailLine(row: row)),
        if (message.attachedFiles?.isNotEmpty == true) ...[
          const SizedBox(height: 8),
          const _DetailSectionTitle(title: 'Attached files'),
          ...message.attachedFiles!.map(
            (path) => _DetailLine(
              row: _DetailRow(
                FileAttachmentHelper.getFileIcon(path),
                FileAttachmentHelper.getFileName(path),
              ),
            ),
          ),
        ],
        if (customDetails != null && customDetails.isNotEmpty) ...[
          const SizedBox(height: 8),
          const _DetailSectionTitle(title: 'Ollama and request data'),
          ..._flattenDetails(customDetails).map((row) => _DetailLine(row: row)),
        ],
      ],
    );
  }

  List<_DetailRow> _flattenDetails(
    Map<String, dynamic> source, [
    String prefix = '',
  ]) {
    final rows = <_DetailRow>[];

    source.forEach((key, value) {
      final label = prefix.isEmpty ? key : '$prefix.$key';
      if (value is Map) {
        rows.addAll(_flattenDetails(Map<String, dynamic>.from(value), label));
      } else if (value is List) {
        rows.add(_DetailRow(label, value.map((item) => '$item').join(', ')));
      } else {
        rows.add(_DetailRow(label, '$value'));
      }
    });

    return rows;
  }
}

class _DetailRow {
  final String label;
  final String value;

  const _DetailRow(this.label, this.value);
}

class _DetailLine extends StatelessWidget {
  final _DetailRow row;

  const _DetailLine({required this.row});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              row.label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              row.value,
              style: const TextStyle(
                color: AppColors.charcoal,
                fontSize: 10,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailSectionTitle extends StatelessWidget {
  final String title;

  const _DetailSectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: AppColors.orange,
        fontSize: 11,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

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
          style: const TextStyle(color: AppColors.muted, fontSize: 10),
        ),
        if (!isUser && modelName != null) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              modelName!,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.muted, fontSize: 10),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionButton(
          icon: Icons.copy_rounded,
          tooltip: 'Copy',
          onPressed: () => _copyToClipboard(context),
        ),
        if (onEdit != null)
          _ActionButton(
            icon: Icons.edit_outlined,
            tooltip: 'Edit',
            onPressed: onEdit!,
          ),
        if (onRegenerate != null)
          _ActionButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Regenerate',
            onPressed: onRegenerate!,
          ),
      ],
    );
  }

  void _copyToClipboard(BuildContext context) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(seconds: 1),
      ),
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
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      waitDuration: const Duration(milliseconds: 450),
      child: IconButton(
        icon: Icon(icon, size: 16, color: AppColors.muted),
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      ),
    );
  }
}
