import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:markdown/markdown.dart' as markdown;
import 'package:syntax_highlight/syntax_highlight.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/chat_message.dart';
import '../theme/app_theme.dart';
import '../utils/helpers.dart';
import '../utils/search_highlight.dart';

part 'tool_activity_panel.dart';

enum MessageDownloadFormat { audio, pdf }

class MessageBubble extends StatefulWidget {
  final ChatMessage message;
  final bool isDarkMode;
  final ValueChanged<String>? onEdit;
  final VoidCallback? onRegenerate;
  final VoidCallback? onSpeak;
  final ValueChanged<MessageDownloadFormat>? onDownload;
  final bool isAudioProcessing;
  final String? audioStatus;
  final bool isPdfExporting;
  final String? pdfStatus;
  final bool isActiveAudio;
  final bool isActiveAudioPlaying;
  final Duration audioPosition;
  final Duration? audioDuration;
  final ValueChanged<Duration>? onSeekAudio;
  final bool useFullWidth;
  final String searchQuery;
  final bool isActiveSearchMatch;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isDarkMode,
    this.onEdit,
    this.onRegenerate,
    this.onSpeak,
    this.onDownload,
    this.isAudioProcessing = false,
    this.audioStatus,
    this.isPdfExporting = false,
    this.pdfStatus,
    this.isActiveAudio = false,
    this.isActiveAudioPlaying = false,
    this.audioPosition = Duration.zero,
    this.audioDuration,
    this.onSeekAudio,
    this.useFullWidth = false,
    this.searchQuery = '',
    this.isActiveSearchMatch = false,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  late final TextEditingController _editController;
  final FocusNode _editFocusNode = FocusNode();
  final GlobalKey _messageContentKey = GlobalKey();
  bool _showThinking = false;
  bool _showDetails = false;
  bool _isEditing = false;
  double? _toolActivitySideHeight;

  static const double _initialToolActivitySideHeight = 180;
  static const double _minimumToolActivitySideHeight = 180;

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
    final hasSearchMatch = _hasSearchMatch(widget.message.text);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.orange,
        borderRadius: BorderRadius.circular(8),
        border: hasSearchMatch
            ? Border.all(
                color: widget.isActiveSearchMatch
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.65),
                width: widget.isActiveSearchMatch ? 2 : 1,
              )
            : null,
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
              searchQuery: widget.searchQuery,
              isActiveSearchMatch: widget.isActiveSearchMatch,
            ),
    );
  }

  bool _hasSearchMatch(String text) {
    final query = widget.searchQuery.trim();
    return query.isNotEmpty && text.toLowerCase().contains(query.toLowerCase());
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

  void _scheduleToolActivitySideMeasurement() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final renderBox =
          _messageContentKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null || !renderBox.hasSize) return;

      final nextHeight = math.max(
        _minimumToolActivitySideHeight,
        renderBox.size.height,
      );
      if (_toolActivitySideHeight != null &&
          (_toolActivitySideHeight! - nextHeight).abs() < 1) {
        return;
      }

      setState(() => _toolActivitySideHeight = nextHeight);
    });
  }

  Widget _buildAssistantMessage(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final maxWidth = widget.useFullWidth ? width * 0.92 : width * 0.70;
    final toolActivities = _ToolActivityData.fromMessage(widget.message);
    final messageContent = KeyedSubtree(
      key: _messageContentKey,
      child: Column(
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
              searchQuery: widget.searchQuery,
              isActiveSearchMatch: widget.isActiveSearchMatch,
              showThinking: _showThinking ||
                  _hasSearchMatch(widget.message.thinkingText!),
              onToggle: () => setState(() => _showThinking = !_showThinking),
            ),
          if (widget.message.text.isNotEmpty)
            MarkdownContentWidget(
              text: widget.message.text,
              isUser: false,
              isDarkMode: widget.isDarkMode,
              searchQuery: widget.searchQuery,
              isActiveSearchMatch: widget.isActiveSearchMatch,
            ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final metadata = MessageMetadataWidget(
                timestamp: widget.message.timestamp,
                modelName: widget.message.modelName,
                isUser: false,
                isDarkMode: widget.isDarkMode,
              );
              final actions = MessageActionButtons(
                text: widget.message.text,
                onRegenerate: widget.onRegenerate,
                onSpeak: widget.onSpeak,
                onDownload: widget.onDownload,
                isAudioProcessing: widget.isAudioProcessing,
                audioStatus: widget.audioStatus,
                isPdfExporting: widget.isPdfExporting,
                pdfStatus: widget.pdfStatus,
                isActiveAudio: widget.isActiveAudio,
                isActiveAudioPlaying: widget.isActiveAudioPlaying,
              );

              if (constraints.maxWidth < 240) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: constraints.maxWidth, child: metadata),
                    const SizedBox(height: 4),
                    actions,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: metadata),
                  actions,
                ],
              );
            },
          ),
          if (widget.isActiveAudio)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: _AudioSeekBar(
                position: widget.audioPosition,
                duration: widget.audioDuration,
                onSeek: widget.onSeekAudio,
              ),
            ),
          MessageDetailsDisclosure(
            message: widget.message,
            isExpanded: _showDetails,
            onToggle: () => setState(() => _showDetails = !_showDetails),
          ),
        ],
      ),
    );

    final hasSearchMatch = _hasSearchMatch(widget.message.text) ||
        _hasSearchMatch(widget.message.thinkingText ?? '');
    final framedMessageContent = hasSearchMatch
        ? AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: widget.isActiveSearchMatch
                  ? AppColors.teal.withValues(alpha: 0.10)
                  : AppColors.teal.withValues(alpha: 0.045),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.teal.withValues(
                  alpha: widget.isActiveSearchMatch ? 0.95 : 0.45,
                ),
                width: widget.isActiveSearchMatch ? 1.5 : 1,
              ),
            ),
            child: messageContent,
          )
        : messageContent;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (toolActivities.isEmpty) return framedMessageContent;

              if (constraints.maxWidth >= 640) {
                _scheduleToolActivitySideMeasurement();
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 236,
                      child: _ToolActivitySideList(
                        activities: toolActivities,
                        isDarkMode: widget.isDarkMode,
                        height: _toolActivitySideHeight ??
                            _initialToolActivitySideHeight,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: framedMessageContent),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  framedMessageContent,
                  const SizedBox(height: 10),
                  _ToolActivitySummaryBar(
                    activities: toolActivities,
                    isDarkMode: widget.isDarkMode,
                  ),
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
  final bool isSelectable;
  final String searchQuery;
  final bool isActiveSearchMatch;

  const MarkdownContentWidget({
    super.key,
    required this.text,
    required this.isUser,
    required this.isDarkMode,
    this.isSelectable = true,
    this.searchQuery = '',
    this.isActiveSearchMatch = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = isUser ? Colors.white : theme.colorScheme.onSurface;
    final blockSurface =
        isDark ? theme.colorScheme.surfaceContainerHigh : Colors.white;
    final lineColor = theme.colorScheme.outlineVariant;

    final style = _markdownStyle(theme, textColor, blockSurface, lineColor);
    final segments = _splitMarkdownVisualBlocks(text)
        .map(
          (segment) => segment.isVisual
              ? segment
              : _MarkdownVisualBlock.text(
                  markSearchMatches(segment.source, searchQuery),
                ),
        )
        .toList();

    if (segments.length == 1 && !segments.single.isVisual) {
      return _markdownBody(context, segments.single.source, style);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final segment in segments)
          if (segment.isVisual)
            CodeBlockWrapper(
              code: segment.source,
              language: segment.language,
              isDarkMode: isDarkMode,
              isSelectable: isSelectable,
              child: _CodeBlockSurface(
                code: segment.source,
                language: segment.language ?? '',
                blockSurface: blockSurface,
                lineColor: lineColor,
                isSelectable: isSelectable,
              ),
            )
          else if (segment.source.trim().isNotEmpty)
            _markdownBody(context, segment.source, style),
      ],
    );
  }

  MarkdownStyleSheet _markdownStyle(
    ThemeData theme,
    Color textColor,
    Color blockSurface,
    Color lineColor,
  ) {
    final textStyle = TextStyle(fontSize: 13, height: 1.45, color: textColor);
    return MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: textStyle,
      a: textStyle.copyWith(
        color: AppColors.teal,
        decoration: TextDecoration.underline,
      ),
      h1: textStyle.copyWith(
        fontSize: 23,
        height: 1.25,
        fontWeight: FontWeight.w800,
      ),
      h2: textStyle.copyWith(
        fontSize: 19,
        height: 1.3,
        fontWeight: FontWeight.w800,
      ),
      h3: textStyle.copyWith(
        fontSize: 16,
        height: 1.35,
        fontWeight: FontWeight.w800,
      ),
      h4: textStyle.copyWith(fontSize: 14, fontWeight: FontWeight.w800),
      h5: textStyle.copyWith(fontWeight: FontWeight.w800),
      h6: textStyle.copyWith(fontWeight: FontWeight.w800),
      code: textStyle.copyWith(
        fontFamily: 'monospace',
        fontSize: 12,
        backgroundColor: blockSurface,
      ),
      blockSpacing: 9,
      tableBorder: TableBorder.all(color: lineColor),
      tableCellsPadding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      tableHead: textStyle.copyWith(fontWeight: FontWeight.w800),
      tableBody: textStyle,
      blockquote: textStyle,
      blockquotePadding: const EdgeInsets.all(10),
      blockquoteDecoration: BoxDecoration(
        color: AppColors.teal.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(6),
        border: Border(left: BorderSide(color: AppColors.teal, width: 3)),
      ),
    );
  }

  Widget _markdownBody(
    BuildContext context,
    String source,
    MarkdownStyleSheet style,
  ) {
    return MarkdownBody(
      data: source,
      selectable: isSelectable,
      styleSheet: style,
      onTapLink: (_, url, __) {
        if (url != null) _handleLinkTap(url, context);
      },
      imageBuilder: (url, _, __) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          url.toString(),
          errorBuilder: (context, error, stackTrace) => Container(
            height: 110,
            color: AppColors.softOrange,
            child: const Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: AppColors.orange,
              ),
            ),
          ),
        ),
      ),
      inlineSyntaxes: [_SearchHighlightInlineSyntax()],
      builders: {
        _searchHighlightTag: _SearchHighlightMarkdownBuilder(
          isUser: isUser,
          isDarkMode: isDarkMode,
          isActive: isActiveSearchMatch,
        ),
      },
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

const _searchHighlightTag = 'quick-llm-search-highlight';

class _SearchHighlightInlineSyntax extends markdown.InlineSyntax {
  _SearchHighlightInlineSyntax()
      : super(
          '${RegExp.escape(searchHighlightOpenMarker)}([\\s\\S]*?)${RegExp.escape(searchHighlightCloseMarker)}',
          startCharacter: searchHighlightOpenMarker.codeUnitAt(0),
        );

  @override
  bool onMatch(markdown.InlineParser parser, Match match) {
    parser.addNode(
      markdown.Element(
        _searchHighlightTag,
        <markdown.Node>[markdown.Text(match.group(1) ?? '')],
      ),
    );
    return true;
  }
}

class _SearchHighlightMarkdownBuilder extends MarkdownElementBuilder {
  final bool isUser;
  final bool isDarkMode;
  final bool isActive;

  _SearchHighlightMarkdownBuilder({
    required this.isUser,
    required this.isDarkMode,
    required this.isActive,
  });

  @override
  Widget? visitElementAfter(
    markdown.Element element,
    TextStyle? preferredStyle,
  ) {
    final highlightColor = isUser
        ? Colors.white.withValues(alpha: isActive ? 0.42 : 0.30)
        : (isDarkMode
            ? AppColors.teal.withValues(alpha: isActive ? 0.68 : 0.46)
            : const Color(0xFFFFD166).withValues(
                alpha: isActive ? 0.82 : 0.62,
              ));

    return Text.rich(
      TextSpan(
        text: element.textContent,
        style: (preferredStyle ?? const TextStyle()).copyWith(
          fontWeight: FontWeight.w800,
          background: Paint()
            ..color = highlightColor
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        ),
      ),
    );
  }
}

class _MarkdownVisualBlock {
  final String source;
  final String? language;
  final bool isVisual;

  const _MarkdownVisualBlock.text(this.source)
      : language = null,
        isVisual = false;

  const _MarkdownVisualBlock.code(this.source, this.language) : isVisual = true;
}

List<_MarkdownVisualBlock> _splitMarkdownVisualBlocks(String source) {
  final fencedCode = RegExp(
    r'^```([^\r\n]*)\r?\n([\s\S]*?)^```[ \t]*$',
    multiLine: true,
  );
  final rawSvg = RegExp(r'<svg\b[\s\S]*?</svg>', caseSensitive: false);
  final blocks = <_MarkdownVisualBlock>[];
  var cursor = 0;

  while (cursor < source.length) {
    final fence = _firstMatchAtOrAfter(fencedCode, source, cursor);
    final svg = _firstMatchAtOrAfter(rawSvg, source, cursor);
    final Match? next;
    if (fence == null) {
      next = svg;
    } else if (svg == null) {
      next = fence;
    } else {
      next = fence.start <= svg.start ? fence : svg;
    }

    if (next == null) {
      blocks.add(_MarkdownVisualBlock.text(source.substring(cursor)));
      break;
    }
    if (next.start > cursor) {
      blocks
          .add(_MarkdownVisualBlock.text(source.substring(cursor, next.start)));
    }

    if (identical(next, fence)) {
      final language = fence!.group(1)?.trim() ?? '';
      blocks.add(_MarkdownVisualBlock.code(fence.group(2) ?? '', language));
    } else {
      blocks.add(_MarkdownVisualBlock.code(next.group(0)!, 'svg'));
    }
    cursor = next.end;
  }

  return blocks.isEmpty
      ? <_MarkdownVisualBlock>[const _MarkdownVisualBlock.text('')]
      : blocks;
}

Match? _firstMatchAtOrAfter(RegExp expression, String source, int start) {
  for (final match in expression.allMatches(source)) {
    if (match.start >= start) return match;
  }
  return null;
}

class CodeBlockWrapper extends StatelessWidget {
  final Widget child;
  final String code;
  final String? language;
  final bool isDarkMode;
  final bool isSelectable;

  const CodeBlockWrapper({
    super.key,
    required this.child,
    required this.code,
    required this.language,
    required this.isDarkMode,
    this.isSelectable = true,
  });

  @override
  Widget build(BuildContext context) {
    final isSvg = _isSvgBlock(code, language);
    final isMermaid = _isMermaidBlock(code, language);
    if (isMermaid) return MermaidPreview(source: code);
    if (isSvg) return SvgSketchPreview(svg: _extractSvg(code));

    return Stack(
      children: [
        child,
        Positioned(
          top: 8,
          right: 8,
          child: CopyCodeButton(code: code, isDarkMode: isDarkMode),
        ),
      ],
    );
  }

  bool _isSvgBlock(String source, String? language) {
    final lang = language?.trim().toLowerCase();
    return lang == 'svg' ||
        RegExp(r'<svg\b', caseSensitive: false).hasMatch(source);
  }

  bool _isMermaidBlock(String source, String? language) {
    final lang = language?.trim().toLowerCase();
    final trimmed = source.trimLeft().toLowerCase();
    return lang == 'mermaid' ||
        trimmed.startsWith('flowchart') ||
        trimmed.startsWith('graph ') ||
        trimmed.startsWith('mindmap') ||
        trimmed.startsWith('sequencediagram') ||
        trimmed.startsWith('classdiagram') ||
        trimmed.startsWith('statediagram') ||
        trimmed.startsWith('erdiagram') ||
        trimmed.startsWith('pie') ||
        trimmed.startsWith('xychart');
  }

  String _extractSvg(String source) {
    final match = RegExp(r'<svg\b[\s\S]*?</svg>', caseSensitive: false)
        .firstMatch(source);
    return match?.group(0) ?? source.trim();
  }
}

class _CodeBlockSurface extends StatelessWidget {
  final String code;
  final String language;
  final Color blockSurface;
  final Color lineColor;
  final bool isSelectable;

  const _CodeBlockSurface({
    required this.code,
    required this.language,
    required this.blockSurface,
    required this.lineColor,
    this.isSelectable = true,
  });

  @override
  Widget build(BuildContext context) {
    final codeColor = Theme.of(context).colorScheme.onSurface;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: blockSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: lineColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (language.trim().isNotEmpty) ...[
            Text(
              language.trim(),
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
          ],
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: _HighlightedCodeText(
              code,
              language: language,
              isSelectable: isSelectable,
              fallbackStyle: TextStyle(
                color: codeColor,
                fontSize: 12,
                fontFamily: 'monospace',
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HighlightedCodeText extends StatelessWidget {
  final String code;
  final String language;
  final TextStyle fallbackStyle;
  final bool isSelectable;

  const _HighlightedCodeText(
    this.code, {
    required this.language,
    required this.fallbackStyle,
    this.isSelectable = true,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedLanguage = _highlightLanguage(language);
    if (normalizedLanguage == null) {
      return isSelectable
          ? SelectableText(code, style: fallbackStyle)
          : Text(code, style: fallbackStyle);
    }

    return FutureBuilder<TextSpan>(
      future: _SyntaxHighlightCache.highlight(
        code: code,
        language: normalizedLanguage,
        brightness: Theme.of(context).brightness,
        fallbackStyle: fallbackStyle,
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return isSelectable
              ? SelectableText(code, style: fallbackStyle)
              : Text(code, style: fallbackStyle);
        }
        return isSelectable
            ? SelectableText.rich(snapshot.data!)
            : RichText(text: snapshot.data!);
      },
    );
  }

  String? _highlightLanguage(String rawLanguage) {
    final normalized = rawLanguage.trim().toLowerCase();
    if (normalized == 'dart') return 'dart';
    if (normalized == 'yaml' || normalized == 'yml') return 'yaml';
    return null;
  }
}

class _SyntaxHighlightCache {
  static final Map<String, Future<void>> _initializers = {};
  static final Map<Brightness, Future<HighlighterTheme>> _themes = {};

  static Future<TextSpan> highlight({
    required String code,
    required String language,
    required Brightness brightness,
    required TextStyle fallbackStyle,
  }) async {
    await _initializers.putIfAbsent(
      language,
      () => Highlighter.initialize([language]),
    );
    final theme = await _themes.putIfAbsent(
      brightness,
      () => HighlighterTheme.loadForBrightness(brightness),
    );
    final span = Highlighter(language: language, theme: theme).highlight(code);
    return TextSpan(style: fallbackStyle, children: [span]);
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
      color: Colors.white.withValues(alpha: 0.16),
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
  final bool isSelectable;
  final bool showThinking;
  final VoidCallback onToggle;
  final String searchQuery;
  final bool isActiveSearchMatch;

  const ThinkingSectionWidget({
    super.key,
    required this.thinkingText,
    required this.isThinking,
    required this.isDarkMode,
    this.isSelectable = true,
    required this.showThinking,
    required this.onToggle,
    this.searchQuery = '',
    this.isActiveSearchMatch = false,
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
                isSelectable: isSelectable,
                searchQuery: searchQuery,
                isActiveSearchMatch: isActiveSearchMatch,
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
        rows.add(
          _DetailRow(
            label,
            value.isEmpty ? 'No items' : '${value.length} items',
          ),
        );
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
    final label = Text(
      row.label,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: AppColors.muted,
        fontSize: 10,
        fontWeight: FontWeight.w800,
      ),
    );
    final value = SelectableText(
      row.value,
      style: const TextStyle(
        color: AppColors.charcoal,
        fontSize: 10,
        height: 1.35,
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 240) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                label,
                const SizedBox(height: 2),
                value,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 150, child: label),
              const SizedBox(width: 8),
              Expanded(child: value),
            ],
          );
        },
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
  final VoidCallback? onSpeak;
  final ValueChanged<MessageDownloadFormat>? onDownload;
  final bool isAudioProcessing;
  final String? audioStatus;
  final bool isPdfExporting;
  final String? pdfStatus;
  final bool isActiveAudio;
  final bool isActiveAudioPlaying;

  const MessageActionButtons({
    super.key,
    required this.text,
    this.onEdit,
    this.onRegenerate,
    this.onSpeak,
    this.onDownload,
    this.isAudioProcessing = false,
    this.audioStatus,
    this.isPdfExporting = false,
    this.pdfStatus,
    this.isActiveAudio = false,
    this.isActiveAudioPlaying = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
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
            if (onSpeak != null)
              _ActionButton(
                icon: isActiveAudioPlaying
                    ? Icons.stop_rounded
                    : Icons.play_arrow_rounded,
                tooltip: isAudioProcessing
                    ? 'Generating audio'
                    : isActiveAudioPlaying
                        ? 'Stop audio'
                        : isActiveAudio
                            ? 'Play audio'
                            : 'Generate and play audio',
                onPressed: isAudioProcessing ? null : onSpeak,
                isLoading: isAudioProcessing,
              ),
            if (onDownload != null)
              _DownloadMenuButton(
                onSelected: onDownload!,
                isLoading: isPdfExporting,
              ),
          ],
        ),
        if (pdfStatus != null)
          Padding(
            padding: const EdgeInsets.only(top: 3, right: 2),
            child: _PdfStatus(label: pdfStatus!),
          )
        else if (audioStatus != null)
          Padding(
            padding: const EdgeInsets.only(top: 3, right: 2),
            child: _AudioStatus(
              label: audioStatus!,
              isLoading: isAudioProcessing,
            ),
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
  final VoidCallback? onPressed;
  final bool isLoading;

  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      waitDuration: const Duration(milliseconds: 450),
      child: IconButton(
        icon: isLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon, size: 16, color: AppColors.muted),
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      ),
    );
  }
}

class _DownloadMenuButton extends StatelessWidget {
  final ValueChanged<MessageDownloadFormat> onSelected;
  final bool isLoading;

  const _DownloadMenuButton({
    required this.onSelected,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: PopupMenuButton<MessageDownloadFormat>(
        tooltip: isLoading ? 'Creating PDF' : 'Download',
        enabled: !isLoading,
        icon: isLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(
                Icons.download_outlined,
                size: 16,
                color: AppColors.muted,
              ),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 174),
        offset: const Offset(0, 28),
        onSelected: onSelected,
        itemBuilder: (context) => const [
          PopupMenuItem(
            value: MessageDownloadFormat.audio,
            child: _DownloadMenuItem(
              icon: Icons.audiotrack_outlined,
              label: 'Download audio',
            ),
          ),
          PopupMenuItem(
            value: MessageDownloadFormat.pdf,
            child: _DownloadMenuItem(
              icon: Icons.picture_as_pdf_outlined,
              label: 'Download PDF',
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _DownloadMenuItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: AppColors.teal),
        const SizedBox(width: 9),
        Text(label),
      ],
    );
  }
}

class _AudioStatus extends StatelessWidget {
  final String label;
  final bool isLoading;

  const _AudioStatus({required this.label, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    final color = isLoading ? AppColors.muted : AppColors.teal;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isLoading ? Icons.graphic_eq_rounded : Icons.check_circle_outline,
          size: 12,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _PdfStatus extends StatelessWidget {
  final String label;

  const _PdfStatus({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 1.8),
        ),
        const SizedBox(width: 5),
        Text(
          '$label...',
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _AudioSeekBar extends StatelessWidget {
  final Duration position;
  final Duration? duration;
  final ValueChanged<Duration>? onSeek;

  const _AudioSeekBar({
    required this.position,
    required this.duration,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    final durationMilliseconds = duration?.inMilliseconds ?? 0;
    final maximum =
        durationMilliseconds > 0 ? durationMilliseconds.toDouble() : 1.0;
    final value =
        position.inMilliseconds.toDouble().clamp(0, maximum).toDouble();
    final isReady = durationMilliseconds > 0 && onSeek != null;
    final colorScheme = Theme.of(context).colorScheme;

    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 2,
        activeTrackColor: AppColors.teal,
        inactiveTrackColor: colorScheme.outlineVariant,
        thumbColor: AppColors.teal,
        disabledActiveTrackColor: AppColors.teal.withValues(alpha: 0.25),
        disabledInactiveTrackColor: colorScheme.outlineVariant,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
      ),
      child: SizedBox(
        height: 22,
        child: Slider(
          value: value,
          min: 0,
          max: maximum,
          onChanged: isReady
              ? (next) => onSeek!(Duration(milliseconds: next.round()))
              : null,
        ),
      ),
    );
  }
}
