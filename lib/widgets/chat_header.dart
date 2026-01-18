import 'package:flutter/material.dart';

/// Enhanced chat header with theme-based colors
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

class _ChatHeaderState extends State<ChatHeader> with SingleTickerProviderStateMixin {
  late AnimationController _refreshController;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _refreshController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _refreshController.dispose();
    super.dispose();
  }

  void _handleRefresh() {
    if (!_isRefreshing) {
      setState(() => _isRefreshing = true);
      _refreshController.repeat();
      widget.onRefreshModels();

      // Stop animation after 1 second
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) {
          _refreshController.stop();
          _refreshController.reset();
          setState(() => _isRefreshing = false);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant,
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            _buildSidebarToggle(),
            const SizedBox(width: 8),
            Expanded(
              child: _buildModelSelector(),
            ),
            const SizedBox(width: 8),
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  /// Enhanced sidebar toggle with animation
  Widget _buildSidebarToggle() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: widget.isSidebarVisible
              ? colorScheme.primary
              : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: widget.onToggleSidebar,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: AnimatedRotation(
              turns: widget.isSidebarVisible ? 0 : 0.5,
              duration: const Duration(milliseconds: 300),
              child: Icon(
                Icons.menu_rounded,
                size: 22,
                color: widget.isSidebarVisible
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Modern model selector with custom styling
  Widget _buildModelSelector() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      constraints: const BoxConstraints(
        maxWidth: 280,
        minWidth: 100,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outline,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.psychology_rounded,
              size: 18,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButton<String>(
              value: widget.selectedModel,
              isExpanded: true,
              isDense: true,
              underline: const SizedBox(),
              icon: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: colorScheme.onSurfaceVariant,
                size: 20,
              ),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
              dropdownColor: colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
              items: widget.availableModels.map((model) {
                return DropdownMenuItem(
                  value: model,
                  child: Text(
                    model,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  widget.onModelChanged(value);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Enhanced action buttons with modern styling
  Widget _buildActionButtons() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildActionButton(
          icon: Icons.refresh_rounded,
          tooltip: 'Refresh models',
          onTap: _handleRefresh,
          isActive: _isRefreshing,
          useAnimation: true,
        ),
        const SizedBox(width: 4),
        _buildActionButton(
          icon: widget.isAlwaysOnTop ? Icons.push_pin_rounded : Icons.push_pin_outlined,
          tooltip: 'Always on top',
          onTap: widget.onToggleAlwaysOnTop,
          isActive: widget.isAlwaysOnTop,
          activeColor: Colors.amber,
        ),
        const SizedBox(width: 4),
        _buildActionButton(
          icon: Icons.picture_in_picture_alt_rounded,
          tooltip: 'Mini mode',
          onTap: widget.onMiniModeTap,
        ),
        const SizedBox(width: 4),
        _buildActionButton(
          icon: Icons.tune_rounded,
          tooltip: 'Settings',
          onTap: widget.onSettingsTap,
        ),
      ],
    );
  }

  /// Reusable action button with consistent styling
  Widget _buildActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool isActive = false,
    bool useAnimation = false,
    Color? activeColor,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final color = isActive
        ? (activeColor ?? colorScheme.primary)
        : colorScheme.onSurfaceVariant;

    final backgroundColor = isActive
        ? (activeColor != null
        ? activeColor.withOpacity(0.15)
        : colorScheme.primaryContainer)
        : colorScheme.surfaceContainerHighest;

    final borderColor = isActive
        ? (activeColor ?? colorScheme.primary)
        : Colors.transparent;

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: Container(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: borderColor,
            width: 1.5,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: useAnimation && _isRefreshing
                  ? RotationTransition(
                turns: _refreshController,
                child: Icon(icon, size: 20, color: color),
              )
                  : Icon(icon, size: 20, color: color),
            ),
          ),
        ),
      ),
    );
  }
}