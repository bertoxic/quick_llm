import 'package:flutter/material.dart';

/// Enhanced chat header with modern design and better UX
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
    return Container(
      height: 64,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: widget.isDarkMode
              ? [
            const Color(0xFF1E1E1E),
            const Color(0xFF252525),
          ]
              : [
            Colors.white,
            Colors.grey[50]!,
          ],
        ),
        border: Border(
          bottom: BorderSide(
            color: _getBorderColor(),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: widget.isDarkMode
                ? Colors.black.withOpacity(0.3)
                : Colors.black.withOpacity(0.05),
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
    return Container(
      decoration: BoxDecoration(
        color: widget.isDarkMode
            ? Colors.grey[850]!.withOpacity(0.5)
            : Colors.grey[200],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: widget.isSidebarVisible
              ? (widget.isDarkMode ? Colors.blue[700]! : Colors.blue[300]!)
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
                    ? (widget.isDarkMode ? Colors.blue[300] : Colors.blue[700])
                    : (widget.isDarkMode ? Colors.grey[400] : Colors.grey[700]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Modern model selector with custom styling (FIXED FOR OVERFLOW)
  Widget _buildModelSelector() {
    return Container(
      constraints: const BoxConstraints(
        maxWidth: 280,
        minWidth: 100,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: widget.isDarkMode
            ? Colors.grey[850]!.withOpacity(0.6)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.isDarkMode ? Colors.grey[800]! : Colors.grey[300]!,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: widget.isDarkMode
                ? Colors.black.withOpacity(0.2)
                : Colors.black.withOpacity(0.03),
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
              color: widget.isDarkMode
                  ? Colors.blue[900]!.withOpacity(0.3)
                  : Colors.blue[50],
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.psychology_rounded,
              size: 18,
              color: widget.isDarkMode ? Colors.blue[300] : Colors.blue[700],
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
                color: widget.isDarkMode ? Colors.grey[400] : Colors.grey[700],
                size: 20,
              ),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: widget.isDarkMode ? Colors.white : Colors.black87,
              ),
              dropdownColor: widget.isDarkMode ? Colors.grey[850] : Colors.white,
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
    final color = isActive
        ? (activeColor ?? (widget.isDarkMode ? Colors.blue[300] : Colors.blue[700]))
        : (widget.isDarkMode ? Colors.grey[400] : Colors.grey[700]);

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: Container(
        decoration: BoxDecoration(
          color: isActive
              ? (widget.isDarkMode
              ? (activeColor ?? Colors.blue[900])!.withOpacity(0.3)
              : (activeColor ?? Colors.blue[50]))
              : (widget.isDarkMode
              ? Colors.grey[850]!.withOpacity(0.5)
              : Colors.grey[100]),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive
                ? (activeColor ?? (widget.isDarkMode ? Colors.blue[700]! : Colors.blue[300]!))
                : Colors.transparent,
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

  Color _getBorderColor() {
    return widget.isDarkMode ? Colors.grey[850]! : Colors.grey[300]!;
  }
}