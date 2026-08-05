import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A desktop-friendly model chooser that only builds visible rows. This avoids
/// DropdownButton eagerly constructing and laying out every installed model.
class ModelPickerButton extends StatelessWidget {
  final String? selectedModel;
  final List<String> models;
  final ValueChanged<String> onSelected;
  final bool enabled;
  final bool compact;
  final Color? foregroundColor;
  final Color? backgroundColor;
  final String hintText;

  const ModelPickerButton({
    super.key,
    required this.selectedModel,
    required this.models,
    required this.onSelected,
    this.enabled = true,
    this.compact = false,
    this.foregroundColor,
    this.backgroundColor,
    this.hintText = 'Select model',
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = foregroundColor ?? colorScheme.onSurface;
    final label =
        selectedModel?.trim().isNotEmpty == true ? selectedModel! : hintText;

    return Material(
      color: backgroundColor ?? colorScheme.surface,
      borderRadius: BorderRadius.circular(compact ? 7 : 9),
      child: InkWell(
        borderRadius: BorderRadius.circular(compact ? 7 : 9),
        onTap: !enabled || models.isEmpty ? null : () => _openPicker(context),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 7 : 10,
            vertical: compact ? 4 : 8,
          ),
          child: Row(
            children: [
              Icon(
                Icons.memory_rounded,
                size: compact ? 14 : 16,
                color: foreground.withValues(alpha: enabled ? 0.82 : 0.4),
              ),
              SizedBox(width: compact ? 5 : 7),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground.withValues(
                      alpha: selectedModel == null ? 0.62 : 1,
                    ),
                    fontSize: compact ? 11 : 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.unfold_more_rounded,
                size: compact ? 15 : 17,
                color: foreground.withValues(alpha: enabled ? 0.68 : 0.35),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openPicker(BuildContext context) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final overlayBox =
        navigator.overlay?.context.findRenderObject() as RenderBox?;
    final buttonBox = context.findRenderObject() as RenderBox?;
    if (overlayBox == null || buttonBox == null || !buttonBox.hasSize) return;

    const margin = 12.0;
    const preferredWidth = 244.0;
    const preferredHeight = 430.0;
    final overlaySize = overlayBox.size;
    final availableWidth = overlaySize.width - (margin * 2);
    if (availableWidth <= 0) return;

    final popupWidth = math.min(preferredWidth, availableWidth);
    final anchor = buttonBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    final left = anchor.dx
        .clamp(margin, overlaySize.width - popupWidth - margin)
        .toDouble();
    final idealTop = anchor.dy + buttonBox.size.height + 8;
    final bottomSpace = overlaySize.height - idealTop - margin;
    final popupHeight = math.min(
      preferredHeight,
      bottomSpace < 220 ? overlaySize.height - (margin * 2) : bottomSpace,
    );
    final top = bottomSpace < 220
        ? math.max(margin, overlaySize.height - popupHeight - margin)
        : idealTop;

    final selection = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close model picker',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (context, animation, secondaryAnimation) => Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              width: popupWidth,
              height: popupHeight,
              child: _ModelPickerPopover(
                models: models,
                selectedModel: selectedModel,
              ),
            ),
          ],
        ),
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curve = CurvedAnimation(parent: animation, curve: Curves.easeOut);
        return FadeTransition(
          opacity: curve,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curve),
            alignment: Alignment.topLeft,
            child: child,
          ),
        );
      },
    );
    if (selection != null) onSelected(selection);
  }
}

class _ModelPickerPopover extends StatefulWidget {
  final List<String> models;
  final String? selectedModel;

  const _ModelPickerPopover({
    required this.models,
    required this.selectedModel,
  });

  @override
  State<_ModelPickerPopover> createState() => _ModelPickerPopoverState();
}

class _ModelPickerPopoverState extends State<_ModelPickerPopover> {
  final TextEditingController _filterController = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  List<String> get _filteredModels {
    final query = _filter.trim().toLowerCase();
    if (query.isEmpty) return widget.models;
    return widget.models
        .where((model) => model.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final models = _filteredModels;
    return Material(
      color: colorScheme.surface,
      elevation: 16,
      shadowColor: Colors.black.withValues(alpha: 0.22),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 7, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.memory_rounded, size: 17),
                  const SizedBox(width: 7),
                  const Expanded(
                    child: Text(
                      'Choose a model',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    '${widget.models.length}',
                    style: TextStyle(
                      color: colorScheme.onSurface.withValues(alpha: 0.62),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 17),
                    tooltip: 'Close',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _filterController,
                autofocus: true,
                onChanged: (value) => setState(() => _filter = value),
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Filter models',
                  hintStyle: const TextStyle(fontSize: 12),
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  suffixIcon: _filter.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 17),
                          onPressed: () => _filterController.clear(),
                          tooltip: 'Clear filter',
                        ),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 7),
              Expanded(
                child: models.isEmpty
                    ? Center(
                        child: Text(
                          'No models match "${_filter.trim()}"',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color:
                                colorScheme.onSurface.withValues(alpha: 0.65),
                            fontSize: 12,
                          ),
                        ),
                      )
                    : Scrollbar(
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: models.length,
                          itemExtent: 44,
                          itemBuilder: (context, index) {
                            final model = models[index];
                            final selected = model == widget.selectedModel;
                            return Material(
                              color: selected
                                  ? colorScheme.primary.withValues(alpha: 0.10)
                                  : Colors.transparent,
                              child: InkWell(
                                onTap: () => Navigator.pop(context, model),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        selected
                                            ? Icons.check_circle_rounded
                                            : Icons.memory_outlined,
                                        size: 17,
                                        color: selected
                                            ? colorScheme.primary
                                            : colorScheme.onSurface
                                                .withValues(alpha: 0.58),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          model,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
