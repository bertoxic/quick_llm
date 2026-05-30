import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/app_theme.dart';

class ChatHeader extends StatefulWidget {
  final bool isDarkMode;
  final bool isSidebarVisible;
  final String? selectedModel;
  final List<String> availableModels;
  final bool isAlwaysOnTop;
  final VoidCallback onToggleSidebar;
  final Function(String) onModelChanged;
  final VoidCallback onSettingsTap;
  final VoidCallback onMiniModeTap;
  final VoidCallback onToggleAlwaysOnTop;
  final VoidCallback onRefreshModels;

  const ChatHeader({
    super.key,
    required this.isDarkMode,
    required this.isSidebarVisible,
    required this.selectedModel,
    required this.availableModels,
    required this.isAlwaysOnTop,
    required this.onToggleSidebar,
    required this.onModelChanged,
    required this.onSettingsTap,
    required this.onMiniModeTap,
    required this.onToggleAlwaysOnTop,
    required this.onRefreshModels,
  });

  @override
  State<ChatHeader> createState() => _ChatHeaderState();
}

class _ChatHeaderState extends State<ChatHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _refreshController;
  final TextEditingController _searchController = TextEditingController();
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _refreshController = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _refreshController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _handleRefresh() {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    _refreshController.repeat();
    widget.onRefreshModels();

    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      _refreshController.stop();
      _refreshController.reset();
      setState(() => _isRefreshing = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          if (!widget.isSidebarVisible) ...[
            _HeaderIconButton(
              icon: Icons.menu_rounded,
              tooltip: 'Sidebar',
              onTap: widget.onToggleSidebar,
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: DragToMoveArea(
              child: SizedBox(
                height: double.infinity,
                child: Row(
                  children: [
                    _HeaderBrand(colorScheme: colorScheme),
                    const Spacer(),
                    _ModelStatusChip(model: widget.selectedModel),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260, minWidth: 170),
            child: SizedBox(
              height: 36,
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search',
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  suffixIcon: const Icon(Icons.filter_list_rounded, size: 17),
                  contentPadding: EdgeInsets.zero,
                  fillColor: colorScheme.surface,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: AppColors.teal, width: 1),
                  ),
                ),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _HeaderIconButton(
            icon: Icons.view_sidebar_rounded,
            tooltip: 'Always on top',
            isSelected: widget.isAlwaysOnTop,
            onTap: widget.onToggleAlwaysOnTop,
          ),
          _HeaderTextButton(
            icon: Icons.picture_in_picture_alt_rounded,
            label: 'Mini',
            onTap: widget.onMiniModeTap,
          ),
          _HeaderIconButton(
            icon: Icons.ios_share_rounded,
            tooltip: 'Refresh models',
            onTap: _handleRefresh,
            animated: _isRefreshing ? _refreshController : null,
          ),
          _HeaderIconButton(
            icon: Icons.more_horiz_rounded,
            tooltip: 'Settings',
            onTap: widget.onSettingsTap,
          ),
        ],
      ),
    );
  }
}

class _HeaderBrand extends StatelessWidget {
  final ColorScheme colorScheme;

  const _HeaderBrand({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppColors.ink,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.auto_awesome_rounded,
            size: 17,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'Creative Chat',
          style: TextStyle(
            color: colorScheme.onSurface,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _ModelStatusChip extends StatelessWidget {
  final String? model;

  const _ModelStatusChip({required this.model});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final label = model?.trim().isNotEmpty == true ? model! : 'No model';

    return Container(
      constraints: const BoxConstraints(maxWidth: 210),
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.memory_rounded, size: 15, color: colorScheme.secondary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isSelected;
  final Animation<double>? animated;

  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isSelected = false,
    this.animated,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final iconWidget = Icon(
      icon,
      size: 18,
      color: isSelected ? colorScheme.onInverseSurface : colorScheme.onSurface,
    );

    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      waitDuration: const Duration(milliseconds: 450),
      child: Padding(
        padding: const EdgeInsets.only(left: 5),
        child: Material(
          color: isSelected ? colorScheme.inverseSurface : colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 34,
              height: 34,
              child: Center(
                child: animated == null
                    ? iconWidget
                    : RotationTransition(
                        turns: animated!,
                        child: iconWidget,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderTextButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _HeaderTextButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      waitDuration: const Duration(milliseconds: 450),
      child: Padding(
        padding: const EdgeInsets.only(left: 5),
        child: Material(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 34,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    Icon(icon, size: 17, color: colorScheme.onSurface),
                    const SizedBox(width: 5),
                    Text(
                      label,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
