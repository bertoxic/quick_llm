part of 'message_bubble.dart';

class SvgSketchPreview extends StatelessWidget {
  final String svg;

  const SvgSketchPreview({super.key, required this.svg});

  @override
  Widget build(BuildContext context) {
    final trimmed = svg.trim();
    if (trimmed.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 300,
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4,
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
      ),
    );
  }
}

class MermaidPreview extends StatelessWidget {
  final String source;

  const MermaidPreview({super.key, required this.source});

  @override
  Widget build(BuildContext context) {
    final repairedSource = _MermaidSourceRepair.normalize(source);
    final parsed = _ParsedMermaidPreview.from(repairedSource);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
      ),
      child: switch (parsed.type) {
        _MermaidPreviewType.flowchart =>
          _MermaidFlowPreview(nodes: parsed.nodes),
        _MermaidPreviewType.mindmap => _MermaidMindMapPreview(
            root: parsed.title,
            branches: parsed.branches,
          ),
        _MermaidPreviewType.chart => _MermaidChartPreview(
            title: parsed.title,
            entries: parsed.entries,
          ),
        _MermaidPreviewType.unknown =>
          _MermaidGenericPreview(source: repairedSource),
      },
    );
  }
}

class _MermaidFlowPreview extends StatelessWidget {
  final List<String> nodes;

  const _MermaidFlowPreview({required this.nodes});

  @override
  Widget build(BuildContext context) {
    final visibleNodes = nodes.isEmpty ? const ['Start', 'Finish'] : nodes;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < visibleNodes.length; i++) ...[
            _PreviewNode(label: visibleNodes[i]),
            if (i < visibleNodes.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward_rounded,
                    size: 20, color: AppColors.teal),
              ),
          ],
        ],
      ),
    );
  }
}

/// A readable visual fallback for Mermaid syntaxes that do not have a custom
/// preview yet, such as sequence, class, state, and entity-relationship
/// diagrams. This deliberately shows the diagram structure instead of its raw
/// Mermaid source.
class _MermaidGenericPreview extends StatelessWidget {
  final String source;

  const _MermaidGenericPreview({required this.source});

  @override
  Widget build(BuildContext context) {
    final nodes = _extractNodes(source);
    final title = _titleFor(source);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.account_tree_outlined,
              size: 16,
              color: AppColors.teal,
            ),
            const SizedBox(width: 7),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.charcoal,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          runSpacing: 10,
          children: [
            for (var index = 0; index < nodes.length; index++) ...[
              _PreviewNode(label: nodes[index], filled: index == 0),
              if (index < nodes.length - 1)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 2),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: AppColors.teal,
                  ),
                ),
            ],
          ],
        ),
      ],
    );
  }

  static List<String> _extractNodes(String source) {
    final nodes = <String>[];
    void add(String? value) {
      final label = (value ?? '')
          .replaceAll(RegExp(r'^[\[\("\s]+|[\]\)"\s]+$'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (label.isNotEmpty && !nodes.contains(label) && nodes.length < 8) {
        nodes.add(label);
      }
    }

    for (final line in source.split(RegExp(r'[\r\n]+'))) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('%%')) continue;
      if (RegExp(
        r'^(?:sequenceDiagram|classDiagram|stateDiagram(?:-v2)?|erDiagram|journey|gantt|timeline|requirementDiagram)\b',
        caseSensitive: false,
      ).hasMatch(trimmed)) {
        continue;
      }

      final declared = RegExp(
        r'^(?:participant|actor|class)\s+([^\s{]+)(?:\s+as\s+(.+))?',
        caseSensitive: false,
      ).firstMatch(trimmed);
      if (declared != null) {
        add(declared.group(2) ?? declared.group(1));
        continue;
      }

      final edge = RegExp(
        r'^([A-Za-z0-9_*]+)\s*(?:-->|->>|-->>|--|==>|<--|[|}{o]+--[|}{o]+)\s*([A-Za-z0-9_*]+)',
      ).firstMatch(trimmed);
      if (edge != null) {
        add(edge.group(1));
        add(edge.group(2));
        continue;
      }

      final labeledNode = RegExp(
        r'([A-Za-z0-9_]+)\s*(?:\["([^"\]]+)"\]|\[([^\]]+)\]|\(\(([^)]+)\)\)|\(([^)]+)\))',
      ).firstMatch(trimmed);
      if (labeledNode != null) {
        add(labeledNode.group(2) ??
            labeledNode.group(3) ??
            labeledNode.group(4) ??
            labeledNode.group(5) ??
            labeledNode.group(1));
      }
    }

    return nodes.isEmpty ? const ['Diagram'] : nodes;
  }

  static String _titleFor(String source) {
    final firstLine = source
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    final name = firstLine
        .replaceFirst(RegExp(r'-v2$', caseSensitive: false), '')
        .replaceAllMapped(
          RegExp(r'([a-z])([A-Z])'),
          (match) => '${match.group(1)} ${match.group(2)}',
        )
        .trim();
    return name.isEmpty ? 'Diagram preview' : '$name preview';
  }
}

class _MermaidMindMapPreview extends StatelessWidget {
  final String root;
  final List<_MindBranchPreview> branches;

  const _MermaidMindMapPreview({
    required this.root,
    required this.branches,
  });

  @override
  Widget build(BuildContext context) {
    final visibleBranches = branches.isEmpty
        ? const [_MindBranchPreview(label: 'Ideas')]
        : branches.take(8).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _PreviewNode(label: root.isEmpty ? 'Mind map' : root, filled: true),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: visibleBranches
              .map(
                (branch) => ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 210),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.arrow_forward_rounded,
                          size: 18, color: AppColors.teal),
                      const SizedBox(width: 6),
                      Flexible(
                        child: _PreviewNode(
                          label: branch.label,
                          subtitle: branch.children.take(2).join(' / '),
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _MermaidChartPreview extends StatelessWidget {
  final String title;
  final List<_PreviewChartEntry> entries;

  const _MermaidChartPreview({
    required this.title,
    required this.entries,
  });

  @override
  Widget build(BuildContext context) {
    final visibleEntries = entries.isEmpty
        ? const [_PreviewChartEntry('Value', 1)]
        : entries.take(8).toList();
    final maxValue = visibleEntries
        .map((entry) => entry.value.abs())
        .fold<double>(0, (max, value) => value > max ? value : max);
    final safeMax = maxValue == 0 ? 1 : maxValue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.charcoal,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        SizedBox(
          height: 150,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: visibleEntries
                .map(
                  (entry) => Expanded(
                    child: LayoutBuilder(builder: (context, constraints) {
                      // Reserve enough vertical room for both text labels and
                      // their spacing. The previous 30 px reservation could
                      // overflow a 150 px chart preview on desktop.
                      final barAreaHeight = (constraints.maxHeight - 40)
                          .clamp(8.0, double.infinity);
                      final barHeight =
                          (entry.value.abs() / safeMax).clamp(0.06, 1.0) *
                              barAreaHeight;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              _formatPreviewNumber(entry.value),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.charcoal,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            SizedBox(
                              height: barHeight,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.orange,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              entry.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _PreviewNode extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool filled;

  const _PreviewNode({
    required this.label,
    this.subtitle = '',
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 88, maxWidth: 170),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: filled ? AppColors.teal : AppColors.softTeal,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.teal.withValues(alpha: 0.35)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: filled ? Colors.white : AppColors.charcoal,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              height: 1.15,
            ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 9,
                height: 1.15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ToolArtifactPreview extends StatelessWidget {
  final _ToolArtifactData artifact;

  const _ToolArtifactPreview({required this.artifact});

  @override
  Widget build(BuildContext context) {
    if (artifact.type == 'svg' && artifact.content.trim().isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ArtifactHeader(artifact: artifact),
          const SizedBox(height: 6),
          SvgSketchPreview(svg: artifact.content),
        ],
      );
    }

    if (artifact.type == 'mermaid' && artifact.content.trim().isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ArtifactHeader(artifact: artifact),
          const SizedBox(height: 6),
          MermaidPreview(source: artifact.content),
        ],
      );
    }

    if (artifact.isDocument && artifact.content.trim().isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ArtifactHeader(artifact: artifact),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.softTeal.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.teal.withValues(alpha: 0.22)),
            ),
            child: Row(
              children: [
                Icon(
                  artifact.type == 'pdf'
                      ? Icons.picture_as_pdf_outlined
                      : Icons.description_outlined,
                  size: 16,
                  color: AppColors.teal,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    artifact.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.charcoal,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }
}

class _ArtifactHeader extends StatelessWidget {
  final _ToolArtifactData artifact;

  const _ArtifactHeader({required this.artifact});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            artifact.label,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        TextButton.icon(
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () => _saveArtifact(context),
          icon: const Icon(Icons.save_alt_rounded, size: 13),
          label: const Text(
            'Save',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }

  Future<void> _saveArtifact(BuildContext context) async {
    try {
      final extension = artifact.extension;
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save ${artifact.label}',
        fileName: artifact.fileName,
        type: FileType.custom,
        allowedExtensions: [extension],
      );
      if (savePath == null) return;

      final normalizedPath = savePath.toLowerCase().endsWith('.$extension')
          ? savePath
          : '$savePath.$extension';
      final file = File(normalizedPath);
      await file.parent.create(recursive: true);
      if (artifact.encoding == 'base64') {
        await file.writeAsBytes(base64Decode(artifact.content));
      } else {
        await file.writeAsString(artifact.content);
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved ${artifact.fileName}')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save artifact: $error')),
        );
      }
    }
  }
}

enum _MermaidPreviewType { flowchart, mindmap, chart, unknown }

class _MermaidSourceRepair {
  static String normalize(String source) {
    var repaired = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    repaired = _normalizeXyChartLists(repaired);
    repaired = _normalizeFlowchartArrows(repaired);
    return repaired.trim();
  }

  static String _normalizeXyChartLists(String source) {
    return source.replaceAllMapped(
      RegExp(r'\b(x-axis|bar|line)\s*\[([\s\S]*?)\]', caseSensitive: false),
      (match) {
        final key = match.group(1) ?? '';
        final body = (match.group(2) ?? '')
            .replaceAll(RegExp(r'[\n\r]+'), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        return '$key [$body]';
      },
    );
  }

  static String _normalizeFlowchartArrows(String source) {
    var repaired = source;
    repaired = repaired.replaceAllMapped(
      RegExp(
        r'--\s*"([^"\n\r]+)"\s*-+>',
        caseSensitive: false,
      ),
      (match) => '-->|${_escapeEdgeLabel(match.group(1) ?? '')}|',
    );
    repaired = repaired.replaceAllMapped(
      RegExp(
        r'--\s*([A-Za-z0-9][^-.\n\r]*?)\s*-+>',
        caseSensitive: false,
      ),
      (match) => '-->|${_escapeEdgeLabel(match.group(1) ?? '')}|',
    );
    repaired = repaired.replaceAllMapped(
      RegExp(r'-{3,}>'),
      (_) => '-->',
    );
    return repaired;
  }

  static String _escapeEdgeLabel(String label) {
    return label.replaceAll('|', '/').replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

class _ParsedMermaidPreview {
  final _MermaidPreviewType type;
  final String title;
  final List<String> nodes;
  final List<_MindBranchPreview> branches;
  final List<_PreviewChartEntry> entries;

  const _ParsedMermaidPreview({
    required this.type,
    this.title = '',
    this.nodes = const [],
    this.branches = const [],
    this.entries = const [],
  });

  factory _ParsedMermaidPreview.from(String source) {
    final trimmed = _MermaidSourceRepair.normalize(source).trim();
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('mindmap')) return _parseMindMap(trimmed);
    if (lower.startsWith('flowchart') || lower.startsWith('graph ')) {
      return _parseFlowchart(trimmed);
    }
    if (lower.startsWith('xychart-beta') || lower.startsWith('pie')) {
      return _parseChart(trimmed);
    }
    return const _ParsedMermaidPreview(type: _MermaidPreviewType.unknown);
  }

  static _ParsedMermaidPreview _parseFlowchart(String source) {
    final labels = <String, String>{};
    final nodeRegex = RegExp(
      r'([A-Za-z0-9_]+)\s*(?:\["([^"]+)"\]|\[([^\]]+)\]|\("([^"]+)"\)|\(([^)]+)\))',
    );
    for (final match in nodeRegex.allMatches(source)) {
      labels[match.group(1)!] = (match.group(2) ??
              match.group(3) ??
              match.group(4) ??
              match.group(5) ??
              '')
          .trim();
    }

    final edgeRegex = RegExp(
      r'([A-Za-z0-9_]+)\s*(?:-->(?:\|[^|]+\|)?|-\.\->|==>)\s*([A-Za-z0-9_]+)',
    );
    final orderedIds = <String>[];
    for (final match in edgeRegex.allMatches(source)) {
      final from = match.group(1)!;
      final to = match.group(2)!;
      if (!orderedIds.contains(from)) orderedIds.add(from);
      if (!orderedIds.contains(to)) orderedIds.add(to);
    }
    if (orderedIds.isEmpty) orderedIds.addAll(labels.keys);

    return _ParsedMermaidPreview(
      type: _MermaidPreviewType.flowchart,
      nodes: orderedIds
          .map((id) => _cleanMermaidLabel(labels[id] ?? id))
          .where((label) => label.isNotEmpty)
          .take(8)
          .toList(),
    );
  }

  static _ParsedMermaidPreview _parseMindMap(String source) {
    final lines = source
        .split(RegExp(r'[\n\r]+'))
        .where((line) => line.trim().isNotEmpty)
        .toList();
    var root = 'Mind map';
    final branches = <_MindBranchPreview>[];
    _MindBranchPreview? activeBranch;

    for (final line in lines.skip(1)) {
      final indent = line.length - line.trimLeft().length;
      final label = _cleanMermaidLabel(line);
      if (label.isEmpty) continue;
      if (label.toLowerCase() == 'root') continue;
      if (indent <= 2 && root == 'Mind map') {
        root = label;
        continue;
      }
      if (indent <= 4) {
        activeBranch = _MindBranchPreview(label: label, children: <String>[]);
        branches.add(activeBranch);
      } else if (activeBranch != null) {
        activeBranch.children.add(label);
      }
    }

    if (branches.isNotEmpty &&
        (root == 'Mind map' || root.toLowerCase() == 'root')) {
      final rootMatch = RegExp(r'root\s*\(\((.*?)\)\)').firstMatch(source);
      if (rootMatch != null) root = _cleanMermaidLabel(rootMatch.group(1)!);
    }

    return _ParsedMermaidPreview(
      type: _MermaidPreviewType.mindmap,
      title: root,
      branches: branches,
    );
  }

  static _ParsedMermaidPreview _parseChart(String source) {
    final titleMatch = RegExp(r'title\s+"?([^"\n\r]+)"?').firstMatch(source);
    final title = titleMatch == null ? 'Chart' : titleMatch.group(1)!.trim();
    final labelsMatch = RegExp(r'x-axis\s*\[([\s\S]*?)\]').firstMatch(source);
    final valuesMatch =
        RegExp(r'(?:bar|line)\s*\[([\s\S]*?)\]').firstMatch(source);
    if (labelsMatch != null && valuesMatch != null) {
      final labels = labelsMatch
          .group(1)!
          .split(',')
          .map((label) => _cleanMermaidLabel(label))
          .toList();
      final values = valuesMatch
          .group(1)!
          .split(',')
          .map((value) => double.tryParse(value.trim()))
          .toList();
      return _ParsedMermaidPreview(
        type: _MermaidPreviewType.chart,
        title: title,
        entries: [
          for (var i = 0; i < labels.length && i < values.length; i++)
            if (values[i] != null) _PreviewChartEntry(labels[i], values[i]!)
        ],
      );
    }

    final pieEntries = RegExp(r'"([^"]+)"\s*:\s*(-?\d+(?:\.\d+)?)')
        .allMatches(source)
        .map((match) => _PreviewChartEntry(
              match.group(1)!,
              double.parse(match.group(2)!),
            ))
        .toList();
    return _ParsedMermaidPreview(
      type: _MermaidPreviewType.chart,
      title: title,
      entries: pieEntries,
    );
  }

  static String _cleanMermaidLabel(String text) {
    final trimmed = text.trim();
    final quotedNode =
        RegExp(r'^[A-Za-z0-9_]+\s*\["([^"]+)"\]').firstMatch(trimmed);
    if (quotedNode != null) return quotedNode.group(1)!.trim();

    final rootNode =
        RegExp(r'^[A-Za-z0-9_]+\s*\(\((.*?)\)\)').firstMatch(trimmed);
    if (rootNode != null) return rootNode.group(1)!.trim();

    return trimmed
        .replaceAll(RegExp(r'[\[\]()]'), '')
        .replaceAll('"', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

class _MindBranchPreview {
  final String label;
  final List<String> children;

  const _MindBranchPreview({
    required this.label,
    this.children = const [],
  });
}

class _PreviewChartEntry {
  final String label;
  final double value;

  const _PreviewChartEntry(this.label, this.value);
}

String _formatPreviewNumber(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
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

class _ToolActivitySideList extends StatelessWidget {
  final List<_ToolActivityData> activities;
  final bool isDarkMode;
  final double height;

  const _ToolActivitySideList({
    required this.activities,
    required this.isDarkMode,
    required this.height,
  });

  void _showActivityDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_awesome_mosaic_outlined, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Tool activity',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    _ToolCountBadge(count: activities.length),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Close',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView.builder(
                    itemCount: activities.length,
                    itemBuilder: (context, index) =>
                        _ToolActivityTile(activity: activities[index]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (activities.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final surface =
        isDarkMode ? colorScheme.surfaceContainerHigh : Colors.white;
    final accent = activities.any((item) => item.status != 'complete')
        ? AppColors.orange
        : AppColors.teal;
    final hasMore = activities.isNotEmpty;

    return SizedBox(
      height: height,
      child: Material(
        color: surface,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.auto_awesome_mosaic_outlined,
                        size: 16,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 8),
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
                const SizedBox(height: 8),

                // ✅ FIX — in _ToolActivitySideList.build
                Expanded(
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: activities
                          .map((activity) =>
                              _ToolActivityTile(activity: activity))
                          .toList(),
                    ),
                  ),
                ),

                if (hasMore) ...[
                  const SizedBox(height: 4),
                  TextButton.icon(
                    onPressed: () => _showActivityDialog(context),
                    icon: const Icon(
                      Icons.unfold_more_rounded,
                      size: 15,
                    ),
                    label: Text('Show more (${activities.length})'),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: accent,
                      textStyle: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolActivitySummaryBar extends StatelessWidget {
  final List<_ToolActivityData> activities;
  final bool isDarkMode;

  const _ToolActivitySummaryBar({
    required this.activities,
    required this.isDarkMode,
  });

  void _showActivityDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_awesome_mosaic_outlined, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Tool activity',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    _ToolCountBadge(count: activities.length),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Close',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView.builder(
                    itemCount: activities.length,
                    itemBuilder: (context, index) =>
                        _ToolActivityTile(activity: activities[index]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (activities.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final surface =
        isDarkMode ? colorScheme.surfaceContainerHigh : Colors.white;
    final accent = activities.any((item) => item.status == 'failed')
        ? AppColors.orange
        : activities.any((item) => item.status != 'complete')
            ? AppColors.orange
            : AppColors.teal;
    final label = activities.length == 1
        ? activities.first.title
        : '${activities.length} tool activities';
    final status = _summaryStatusLabel(activities);

    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => _showActivityDialog(context),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.auto_awesome_mosaic_outlined,
                  size: 16,
                  color: accent,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Tool activity',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$label · $status',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.66),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _ToolCountBadge(count: activities.length),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: colorScheme.onSurface.withValues(alpha: 0.56),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _summaryStatusLabel(List<_ToolActivityData> activities) {
    if (activities.any((item) => item.status == 'failed')) return 'failed';
    if (activities.any((item) => item.status == 'unavailable')) {
      return 'unavailable';
    }
    if (activities.every((item) => item.status == 'ready')) return 'ready';
    if (activities.any((item) => item.status != 'complete')) {
      return 'running';
    }
    return 'complete';
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _showDetails(context),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: activity.isWorking
                    ? accent.withValues(alpha: 0.45)
                    : colorScheme.outlineVariant,
              ),
              boxShadow: activity.isWorking
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.10),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AnimatedToolStatusIcon(
                      activity: activity,
                      accent: accent,
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
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _MiniToolBadge(
                                label: _statusLabel(activity.status),
                                color: _statusColor(activity.status),
                              ),
                              if (activity.isWorking)
                                _TypingDots(
                                    color: _statusColor(activity.status)),
                              _MiniToolBadge(
                                label: activity.uiSurface,
                                color: AppColors.teal,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.open_in_full_rounded,
                      size: 13,
                      color: colorScheme.onSurface.withValues(alpha: 0.45),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                activity.isWorking
                    ? _TypewriterToolText(
                        text: activity.summary,
                        style: TextStyle(
                          color: colorScheme.onSurface.withValues(alpha: 0.74),
                          fontSize: 10,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : Text(
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
                    icon: activity.isComplete
                        ? Icons.verified_rounded
                        : Icons.done_rounded,
                    label: activity.output!,
                    color: AppColors.teal,
                  ),
                ],
                if (activity.artifact != null) ...[
                  const SizedBox(height: 8),
                  _ToolArtifactPreview(artifact: activity.artifact!),
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
                                  activity.isComplete
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
                                    color: colorScheme.onSurface
                                        .withValues(alpha: 0.68),
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
          ),
        ),
      ),
    );
  }

  void _showDetails(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => _ToolActivityDetailsDialog(activity: activity),
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
      case 'tool_router':
        return Icons.alt_route_rounded;
      case 'mind_map_generator':
      case 'mind_map_tool':
        return Icons.hub_rounded;
      case 'simulation_tool':
        return Icons.science_outlined;
      case 'web_search':
        return Icons.public_rounded;
      case 'deep_research':
        return Icons.travel_explore_rounded;
      case 'brainstorm':
        return Icons.tips_and_updates_outlined;
      case 'note_saver':
        return Icons.sticky_note_2_outlined;
      case 'web_scraper_reader':
      case 'webpage_reader':
        return Icons.article_outlined;
      case 'local_document_search':
        return Icons.manage_search_rounded;
      case 'code_executor':
        return Icons.data_object_rounded;
      case 'document_generator':
        return Icons.description_outlined;
      case 'chart_diagram_generator':
        return Icons.insert_chart_outlined_rounded;
      case 'ci_cli_runner':
        return Icons.task_alt_rounded;
      case 'workflow_automation':
        return Icons.schema_rounded;
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
      case 'deep_research':
      case 'local_document_search':
      case 'web_scraper_reader':
      case 'webpage_reader':
      case 'mind_map_generator':
      case 'chart_diagram_generator':
      case 'workflow_automation':
        return AppColors.teal;
      case 'calculator':
      case 'code_executor':
      case 'simulation_tool':
      case 'document_generator':
      case 'ci_cli_runner':
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

class _AnimatedToolStatusIcon extends StatefulWidget {
  final _ToolActivityData activity;
  final Color accent;

  const _AnimatedToolStatusIcon({
    required this.activity,
    required this.accent,
  });

  @override
  State<_AnimatedToolStatusIcon> createState() =>
      _AnimatedToolStatusIconState();
}

class _AnimatedToolStatusIconState extends State<_AnimatedToolStatusIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.activity.isWorking) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _AnimatedToolStatusIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activity.isWorking && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.activity.isWorking && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statusIcon = widget.activity.isComplete
        ? Icons.check_circle_rounded
        : widget.activity.isProblem
            ? Icons.warning_rounded
            : null;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final pulse = widget.activity.isWorking
            ? 0.10 + math.sin(_controller.value * math.pi * 2).abs() * 0.10
            : 0.12;
        return Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: widget.accent.withValues(alpha: pulse),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.accent.withValues(
                alpha: widget.activity.isWorking ? 0.38 : 0.18,
              ),
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (widget.activity.isWorking)
                SizedBox(
                  width: 25,
                  height: 25,
                  child: CircularProgressIndicator(
                    value: null,
                    strokeWidth: 1.8,
                    color: widget.accent.withValues(alpha: 0.72),
                  ),
                ),
              Icon(
                _ToolActivityTile._iconFor(widget.activity.id),
                size: 15,
                color: widget.accent,
              ),
              if (statusIcon != null)
                Positioned(
                  right: 1,
                  bottom: 1,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.75, end: 1),
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutBack,
                    builder: (context, scale, child) {
                      return Transform.scale(scale: scale, child: child);
                    },
                    child: Icon(
                      statusIcon,
                      size: 12,
                      color: widget.activity.isProblem
                          ? AppColors.orange
                          : AppColors.teal,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _TypewriterToolText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const _TypewriterToolText({
    required this.text,
    required this.style,
  });

  @override
  State<_TypewriterToolText> createState() => _TypewriterToolTextState();
}

class _TypewriterToolTextState extends State<_TypewriterToolText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant _TypewriterToolText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _controller.forward(from: 0);
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.text.isEmpty) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final length = widget.text.length;
        final visible = math.max(1, (_controller.value * length).ceil());
        return Text(
          widget.text.substring(0, math.min(length, visible)),
          style: widget.style,
        );
      },
    );
  }
}

class _TypingDots extends StatefulWidget {
  final Color color;

  const _TypingDots({required this.color});

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final phase = (_controller.value + index / 3) % 1;
            final opacity = 0.35 + math.sin(phase * math.pi).abs() * 0.65;
            return Container(
              width: 4,
              height: 4,
              margin: EdgeInsets.only(right: index == 2 ? 0 : 3),
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: opacity),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}

class _ToolActivityDetailsDialog extends StatelessWidget {
  final _ToolActivityData activity;

  const _ToolActivityDetailsDialog({required this.activity});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = _ToolActivityTile._accentFor(activity.id);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AnimatedToolStatusIcon(activity: activity, accent: accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          activity.title,
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _MiniToolBadge(
                              label: _ToolActivityTile._statusLabel(
                                  activity.status),
                              color: _ToolActivityTile._statusColor(
                                  activity.status),
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
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ToolDetailSection(
                      title: 'Summary',
                      child: Text(
                        activity.summary,
                        style: TextStyle(
                          color: colorScheme.onSurface.withValues(alpha: 0.76),
                          fontSize: 12,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (activity.artifact != null)
                      _ToolDetailSection(
                        title: activity.artifact!.label,
                        child:
                            _ToolArtifactPreview(artifact: activity.artifact!),
                      ),
                    if (activity.steps.isNotEmpty)
                      _ToolDetailSection(
                        title: 'Steps',
                        child: Column(
                          children: activity.steps
                              .asMap()
                              .entries
                              .map(
                                (entry) => _ToolDetailStep(
                                  index: entry.key + 1,
                                  text: entry.value,
                                  accent: accent,
                                  done: activity.isComplete,
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    if (activity.output?.isNotEmpty == true)
                      _ToolDetailSection(
                        title: 'Output',
                        child: SelectableText(
                          activity.output!,
                          style: const TextStyle(
                            color: AppColors.teal,
                            fontSize: 12,
                            height: 1.35,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    if (activity.error?.isNotEmpty == true)
                      _ToolDetailSection(
                        title: 'Error',
                        child: SelectableText(
                          activity.error!,
                          style: const TextStyle(
                            color: AppColors.orange,
                            fontSize: 12,
                            height: 1.35,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    if (activity.sources.isNotEmpty)
                      _ToolDetailSection(
                        title: 'Sources',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: activity.sources
                              .map(
                                (source) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: SelectableText(
                                    '${source.title}\n${source.url}',
                                    style: TextStyle(
                                      color: colorScheme.onSurface
                                          .withValues(alpha: 0.72),
                                      fontSize: 11,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
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

class _ToolDetailSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _ToolDetailSection({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.charcoal,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          child,
        ],
      ),
    );
  }
}

class _ToolDetailStep extends StatelessWidget {
  final int index;
  final String text;
  final Color accent;
  final bool done;

  const _ToolDetailStep({
    required this.index,
    required this.text,
    required this.accent,
    required this.done,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: done
                ? Icon(Icons.check_rounded, size: 13, color: accent)
                : Text(
                    '$index',
                    style: TextStyle(
                      color: accent,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.74),
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
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
  final _ToolArtifactData? artifact;

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
    this.artifact,
  });

  bool get isComplete => status == 'complete';
  bool get isProblem => status == 'failed' || status == 'unavailable';
  bool get isWorking =>
      status == 'queued' ||
      status == 'running' ||
      status == 'in_progress' ||
      status == 'tool_calling';

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
      artifact: map['artifact'] is Map
          ? _ToolArtifactData.fromMap(map['artifact'] as Map)
          : null,
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

class _ToolArtifactData {
  final String type;
  final String content;
  final String label;
  final String fileName;
  final String? encoding;

  const _ToolArtifactData({
    required this.type,
    required this.content,
    required this.label,
    required this.fileName,
    this.encoding,
  });

  factory _ToolArtifactData.fromMap(Map<dynamic, dynamic> map) {
    final type = '${map['type'] ?? ''}'.trim().toLowerCase();
    final fileName = '${map['file_name'] ?? ''}'.trim();
    return _ToolArtifactData(
      type: type,
      content: '${map['content'] ?? ''}',
      label: '${map['label'] ?? 'Preview'}',
      fileName: fileName.isEmpty ? _defaultArtifactFileName(type) : fileName,
      encoding: map['encoding'] == null ? null : '${map['encoding']}',
    );
  }

  bool get isDocument =>
      type == 'pdf' ||
      type == 'markdown' ||
      type == 'html' ||
      type == 'text' ||
      type == 'txt' ||
      type == 'md';

  String get extension {
    final dot = fileName.lastIndexOf('.');
    if (dot != -1 && dot < fileName.length - 1) {
      return fileName.substring(dot + 1).toLowerCase();
    }
    switch (type) {
      case 'markdown':
      case 'md':
        return 'md';
      case 'html':
        return 'html';
      case 'text':
      case 'txt':
        return 'txt';
      case 'pdf':
        return 'pdf';
      case 'mermaid':
        return 'mmd';
      case 'svg':
      default:
        return 'svg';
    }
  }

  static String _defaultArtifactFileName(String type) {
    switch (type) {
      case 'markdown':
      case 'md':
        return 'quick_llm_document.md';
      case 'html':
        return 'quick_llm_document.html';
      case 'text':
      case 'txt':
        return 'quick_llm_document.txt';
      case 'pdf':
        return 'quick_llm_document.pdf';
      case 'mermaid':
        return 'quick_llm_diagram.mmd';
      case 'svg':
      default:
        return 'quick_llm_artifact.svg';
    }
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
