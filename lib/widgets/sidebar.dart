import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../theme/app_theme.dart';
import '../utils/date_formatter.dart';
import 'typing_indicaator.dart';

class Sidebar extends StatefulWidget {
  final bool isDarkMode;
  final List<Conversation> conversations;
  final int? selectedConversationIndex;
  final int? generatingConversationIndex;
  final Set<int> generatingConversationIndices;
  final VoidCallback onNewChat;
  final Function(int) onLoadConversation;
  final Function(int) onDeleteConversation;
  final Function(Conversation) onExportConversation;
  final VoidCallback onExportAll;
  final VoidCallback onToggleTheme;
  final VoidCallback onToggleSidebar;
  final VoidCallback onClearAllConversations;
  final Function(int, int)? onEnableSplitMode;
  final bool isSplitMode;
  final String? selectedModel;
  final List<String> availableModels;
  final Function(String)? onModelChanged;
  final VoidCallback? onSettingsTap;
  final VoidCallback? onMiniModeTap;
  final VoidCallback? onToggleAlwaysOnTop;
  final VoidCallback? onRefreshModels;
  final bool isAlwaysOnTop;
  final bool isPanelVisible;

  const Sidebar({
    super.key,
    required this.isDarkMode,
    required this.conversations,
    required this.selectedConversationIndex,
    this.generatingConversationIndex,
    this.generatingConversationIndices = const {},
    required this.onNewChat,
    required this.onLoadConversation,
    required this.onDeleteConversation,
    required this.onExportConversation,
    required this.onExportAll,
    required this.onToggleTheme,
    required this.onToggleSidebar,
    required this.onClearAllConversations,
    this.onEnableSplitMode,
    this.isSplitMode = false,
    this.selectedModel,
    this.availableModels = const [],
    this.onModelChanged,
    this.onSettingsTap,
    this.onMiniModeTap,
    this.onToggleAlwaysOnTop,
    this.onRefreshModels,
    this.isAlwaysOnTop = false,
    this.isPanelVisible = true,
  });

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  List<Conversation> get _filteredConversations {
    if (_searchQuery.trim().isEmpty) return widget.conversations;
    final query = _searchQuery.toLowerCase();
    return widget.conversations
        .where(
            (conversation) => conversation.title.toLowerCase().contains(query))
        .toList();
  }

  String? get _modelValue {
    if (widget.selectedModel == null) return null;
    return widget.availableModels.contains(widget.selectedModel)
        ? widget.selectedModel
        : null;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.isPanelVisible ? 292 : 58,
      child: Row(
        children: [
          _buildRail(),
          if (widget.isPanelVisible) Expanded(child: _buildPanel()),
        ],
      ),
    );
  }

  Widget _buildRail() {
    return Container(
      width: 58,
      color: AppColors.rail,
      child: Column(
        children: [
          const SizedBox(height: 12),
          _RailButton(
            icon: widget.isPanelVisible
                ? Icons.menu_open_rounded
                : Icons.menu_rounded,
            tooltip:
                widget.isPanelVisible ? 'Collapse sidebar' : 'Expand sidebar',
            onTap: widget.onToggleSidebar,
          ),
          const SizedBox(height: 72),
          _RailButton(
            icon: Icons.add_rounded,
            tooltip: 'New chat',
            isActive: true,
            onTap: widget.onNewChat,
          ),
          _RailButton(
            icon: Icons.chat_bubble_outline_rounded,
            tooltip: 'Conversations',
            onTap: () {},
          ),
          _RailButton(
            icon: Icons.history_rounded,
            tooltip: 'Export all',
            onTap: widget.onExportAll,
          ),
          _RailButton(
            icon: Icons.crop_square_rounded,
            tooltip: 'Always on top',
            isActive: widget.isAlwaysOnTop,
            onTap: widget.onToggleAlwaysOnTop ?? () {},
          ),
          _RailButton(
            icon: Icons.picture_in_picture_alt_rounded,
            tooltip: 'Mini mode',
            onTap: widget.onMiniModeTap ?? () {},
          ),
          _RailButton(
            icon: Icons.settings_outlined,
            tooltip: 'Settings',
            onTap: widget.onSettingsTap ?? () {},
          ),
          const Spacer(),
          _RailButton(
            icon: widget.isDarkMode
                ? Icons.light_mode_rounded
                : Icons.dark_mode_rounded,
            tooltip: 'Theme',
            onTap: widget.onToggleTheme,
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildPanel() {
    return Container(
      color: AppColors.panel,
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildModelCard(),
          const SizedBox(height: 12),
          SizedBox(
            height: 42,
            child: FilledButton.icon(
              onPressed: widget.onNewChat,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('New Chat'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.orange,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 14),
          _buildConversationSection(),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: widget.onExportAll,
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: const Text('Export'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _showClearAllDialog,
                tooltip: 'Clear all conversations',
                icon: const Icon(Icons.delete_sweep_rounded),
                color: Colors.white70,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModelCard() {
    return Container(
      height: 54,
      padding: const EdgeInsets.fromLTRB(10, 7, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    _TinyBadge(label: 'Model'),
                    SizedBox(width: 5),
                    _TinyBadge(label: 'Free'),
                  ],
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _modelValue,
                      isExpanded: true,
                      dropdownColor: AppColors.panel,
                      borderRadius: BorderRadius.circular(8),
                      hint: const Text(
                        'Select model',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: Colors.white70,
                      ),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                      items: widget.availableModels
                          .map(
                            (model) => DropdownMenuItem(
                              value: model,
                              child:
                                  Text(model, overflow: TextOverflow.ellipsis),
                            ),
                          )
                          .toList(),
                      onChanged: widget.onModelChanged == null
                          ? null
                          : (model) {
                              if (model != null) widget.onModelChanged!(model);
                            },
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: widget.onRefreshModels,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            tooltip: 'Refresh models',
            color: Colors.white70,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationSection() {
    return Expanded(
      child: _PanelSection(
        title: 'Conversations',
        expandChild: true,
        child: Column(
          children: [
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: AppColors.panelSoft,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: Center(
                child: TextField(
                  onChanged: (value) => setState(() => _searchQuery = value),
                  maxLines: 1,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: const InputDecoration(
                    hintText: 'Search conversations',
                    hintStyle: TextStyle(color: Colors.white54, fontSize: 11),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 16,
                      color: Colors.white54,
                    ),
                    prefixIconConstraints:
                        BoxConstraints(minWidth: 26, minHeight: 26),
                    isCollapsed: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(child: _buildConversationList()),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationList() {
    final filtered = _filteredConversations;

    if (filtered.isEmpty) {
      return const Center(
        child: Text(
          'No conversations yet',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.zero,
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final actualIndex = widget.conversations.indexOf(filtered[index]);
        return _buildConversationTile(actualIndex, filtered[index]);
      },
    );
  }

  Widget _buildConversationTile(int index, Conversation conversation) {
    final isSelected = widget.selectedConversationIndex == index;
    final isGenerating = widget.generatingConversationIndex == index ||
        widget.generatingConversationIndices.contains(index);
    final tile = Dismissible(
      key: ValueKey('${conversation.timestamp.microsecondsSinceEpoch}-$index'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 14),
        margin: const EdgeInsets.only(bottom: 7),
        decoration: BoxDecoration(
          color: AppColors.orange,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      confirmDismiss: (_) => _confirmDelete(),
      onDismissed: (_) => widget.onDeleteConversation(index),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => widget.onLoadConversation(index),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            margin: const EdgeInsets.only(bottom: 7),
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.softOrange : AppColors.panelSoft,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isGenerating
                    ? AppColors.teal
                    : (isSelected ? AppColors.orange : Colors.white10),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isSelected
                          ? Icons.chat_bubble_rounded
                          : Icons.chat_bubble_outline_rounded,
                      size: 14,
                      color: isSelected ? AppColors.orange : Colors.white70,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        conversation.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isSelected ? AppColors.charcoal : Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    _buildConversationMenu(index, conversation, isSelected),
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        DateFormatter.formatTimestamp(conversation.timestamp),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isSelected
                              ? AppColors.charcoal.withOpacity(0.65)
                              : Colors.white54,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    Text(
                      '${conversation.messageCount}',
                      style: TextStyle(
                        color: isSelected ? AppColors.charcoal : Colors.white54,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                if (isGenerating)
                  GeneratingIndicator(isDarkMode: widget.isDarkMode),
              ],
            ),
          ),
        ),
      ),
    );

    if (widget.onEnableSplitMode == null) return tile;

    return LongPressDraggable<int>(
      data: index,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          width: 210,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.ink,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.orange),
          ),
          child: Text(
            conversation.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: tile),
      child: tile,
    );
  }

  Widget _buildConversationMenu(
    int index,
    Conversation conversation,
    bool isSelected,
  ) {
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      tooltip: 'Conversation actions',
      icon: Icon(
        Icons.more_horiz_rounded,
        size: 16,
        color: isSelected ? AppColors.charcoal : Colors.white70,
      ),
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onSelected: (value) {
        switch (value) {
          case 'export':
            widget.onExportConversation(conversation);
            break;
          case 'delete':
            widget.onDeleteConversation(index);
            break;
          case 'split':
            _showSplitModeDialog(index);
            break;
        }
      },
      itemBuilder: (context) => [
        if (widget.onEnableSplitMode != null && !widget.isSplitMode)
          const PopupMenuItem(
            value: 'split',
            child:
                _MenuRow(icon: Icons.splitscreen_rounded, label: 'Split view'),
          ),
        const PopupMenuItem(
          value: 'export',
          child: _MenuRow(icon: Icons.download_rounded, label: 'Export'),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: _MenuRow(icon: Icons.delete_outline_rounded, label: 'Delete'),
        ),
      ],
    );
  }

  Future<bool?> _confirmDelete() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Conversation'),
        content:
            const Text('Are you sure you want to delete this conversation?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _showClearAllDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear all conversations?'),
        content: Text(
          'This will permanently delete ${widget.conversations.length} '
          'conversation${widget.conversations.length == 1 ? '' : 's'}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      widget.onClearAllConversations();
    }
  }

  void _showSplitModeDialog(int draggedIndex) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Open Split View'),
        content: SizedBox(
          width: 340,
          height: 280,
          child: ListView.builder(
            itemCount: widget.conversations.length - 1,
            itemBuilder: (context, i) {
              final index = i >= draggedIndex ? i + 1 : i;
              final conversation = widget.conversations[index];
              return ListTile(
                leading: const Icon(Icons.splitscreen_rounded),
                title: Text(
                  conversation.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle:
                    Text(DateFormatter.formatTimestamp(conversation.timestamp)),
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onEnableSplitMode?.call(draggedIndex, index);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isActive;

  const _RailButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Material(
          color: isActive ? Colors.white : AppColors.ink,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 30,
              height: 30,
              child: Icon(
                icon,
                size: 17,
                color: isActive ? AppColors.ink : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelSection extends StatelessWidget {
  final String title;
  final Widget child;
  final bool expandChild;

  const _PanelSection({
    required this.title,
    required this.child,
    this.expandChild = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (expandChild) Expanded(child: child) else child,
      ],
    );
  }
}

class _TinyBadge extends StatelessWidget {
  final String label;

  const _TinyBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 8,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MenuRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 17, color: AppColors.charcoal),
        const SizedBox(width: 10),
        Text(label),
      ],
    );
  }
}
