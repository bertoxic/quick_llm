import 'package:flutter/material.dart';
import 'package:quick_llm/widgets/typing_indicaator.dart';
import '../models/conversation.dart';
import '../utils/date_formatter.dart';

/// Enhanced sidebar with theme-based colors
class Sidebar extends StatefulWidget {
  final bool isDarkMode;
  final List<Conversation> conversations;
  final int? selectedConversationIndex;
  final int? generatingConversationIndex;
  final VoidCallback onNewChat;
  final Function(int) onLoadConversation;
  final Function(int) onDeleteConversation;
  final Function(Conversation) onExportConversation;
  final VoidCallback onExportAll;
  final VoidCallback onToggleTheme;
  final VoidCallback onClearAllConversations;
  final Function(int, int)? onEnableSplitMode;
  final bool isSplitMode;

  const Sidebar({
    super.key,
    required this.isDarkMode,
    required this.conversations,
    required this.selectedConversationIndex,
    this.generatingConversationIndex,
    required this.onNewChat,
    required this.onLoadConversation,
    required this.onDeleteConversation,
    required this.onExportConversation,
    required this.onExportAll,
    required this.onToggleTheme,
    required this.onClearAllConversations,
    this.onEnableSplitMode,
    this.isSplitMode = false,
  });

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';
  bool _isConversationsExpanded = true;
  bool _isSettingsExpanded = true;
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _toggleConversations() {
    setState(() => _isConversationsExpanded = !_isConversationsExpanded);
  }

  void _toggleSettings() {
    setState(() => _isSettingsExpanded = !_isSettingsExpanded);
  }

  void _showAboutDialog() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.info_outline, color: colorScheme.onPrimaryContainer, size: 24),
            ),
            const SizedBox(width: 12),
            const Text('About Quick LLM'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Version 1.0.0',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'A fast and efficient LLM chat interface built with Flutter.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Divider(color: colorScheme.outlineVariant),
            const SizedBox(height: 12),
            ...[
              (Icons.code, 'Built with Flutter'),
              (Icons.chat_bubble_outline, 'AI-Powered Conversations'),
              (Icons.security, 'Privacy-Focused'),
              (Icons.splitscreen, 'Split Screen Support'),
            ].map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(item.$1, size: 16, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text(item.$2, style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface,
                  )),
                ],
              ),
            )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showClearAllDialog() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.warning_amber_rounded, color: colorScheme.error, size: 24),
            ),
            const SizedBox(width: 12),
            const Text('Clear All Conversations?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will permanently delete all ${widget.conversations.length} conversation${widget.conversations.length != 1 ? 's' : ''}.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colorScheme.error),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This action cannot be undone.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.error,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onClearAllConversations();
            },
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }

  void _showSplitModeDialog(int draggedIndex) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.splitscreen, color: colorScheme.onPrimaryContainer, size: 24),
            ),
            const SizedBox(width: 12),
            const Text('Enable Split Mode'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose a conversation to compare with:',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.maxFinite,
              height: 300,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.conversations.length - 1,
                itemBuilder: (context, i) {
                  final index = i >= draggedIndex ? i + 1 : i;
                  final conv = widget.conversations[index];
                  return ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.chat_bubble_outline,
                        size: 20,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    title: Text(
                      conv.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    subtitle: Text(
                      DateFormatter.formatTimestamp(conv.timestamp),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      widget.onEnableSplitMode?.call(draggedIndex, index);
                    },
                  );
                },
              ),
            ),
          ],
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

  List<Conversation> get _filteredConversations {
    if (_searchQuery.isEmpty) return widget.conversations;
    final query = _searchQuery.toLowerCase();
    return widget.conversations.where((conv) => conv.title.toLowerCase().contains(query)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(right: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Column(
        children: [
          _buildHeader(),
          _buildConversationsSection(),
          _buildSettingsSection(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withOpacity(0.3),
      ),
      child: Column(
        children: [
          ElevatedButton.icon(
            onPressed: widget.onNewChat,
            icon: const Icon(Icons.add_rounded, size: 22),
            label: const Text('New Chat', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              foregroundColor: colorScheme.onPrimary,
              backgroundColor: colorScheme.primary,
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          if (widget.isSplitMode)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.tertiary),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.splitscreen, size: 16, color: colorScheme.onTertiaryContainer),
                    const SizedBox(width: 8),
                    Text(
                      'Split Mode Active',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onTertiaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildConversationsSection() {
    return Expanded(
      child: Column(
        children: [
          _buildSectionHeader(
            title: 'Conversations',
            icon: Icons.chat_bubble_outline_rounded,
            count: widget.conversations.length,
            isExpanded: _isConversationsExpanded,
            onToggle: _toggleConversations,
          ),
          if (_isConversationsExpanded)
            Expanded(
              child: Column(
                children: [
                  if (widget.conversations.length > 5) _buildSearchBar(),
                  if (widget.onEnableSplitMode != null && !widget.isSplitMode)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 14,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Long press & drag to split screen',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Expanded(
                    child: _buildConversationList(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required IconData icon,
    required int count,
    required bool isExpanded,
    required VoidCallback onToggle,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 18, color: colorScheme.primary),
              const SizedBox(width: 10),
              Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const Spacer(),
              AnimatedRotation(
                turns: isExpanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 300),
                child: Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: TextField(
        onChanged: (value) => setState(() => _searchQuery = value),
        decoration: InputDecoration(
          hintText: 'Search conversations...',
          hintStyle: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          prefixIcon: Icon(Icons.search, size: 20, color: colorScheme.onSurfaceVariant),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
            icon: Icon(Icons.clear, size: 18, color: colorScheme.onSurfaceVariant),
            onPressed: () => setState(() => _searchQuery = ''),
            padding: EdgeInsets.zero,
          )
              : null,
          filled: true,
          fillColor: colorScheme.surfaceContainerHighest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          isDense: true,
        ),
        style: theme.textTheme.bodyMedium,
      ),
    );
  }

  Widget _buildConversationList() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final filtered = _filteredConversations;

    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            'No conversations found',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      itemCount: filtered.length,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      itemBuilder: (context, index) {
        final actualIndex = widget.conversations.indexOf(filtered[index]);
        return _buildConversationTile(actualIndex, filtered[index]);
      },
    );
  }

  Widget _buildConversationTile(int index, Conversation conv) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSelected = widget.selectedConversationIndex == index;
    final isGenerating = widget.generatingConversationIndex == index;
    final canDrag = widget.onEnableSplitMode != null && !widget.isSplitMode;

    Widget tile = Dismissible(
      key: ValueKey(conv.timestamp),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: colorScheme.error,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.delete_outline, color: colorScheme.onError, size: 24),
      ),
      confirmDismiss: (direction) => _confirmDelete(),
      onDismissed: (_) => widget.onDeleteConversation(index),
      child: _buildTileContent(index, conv, isSelected, isGenerating, canDrag),
    );

    if (canDrag) {
      return LongPressDraggable<int>(
        data: index,
        feedback: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 240,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.primary, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.primary.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.splitscreen, size: 18, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      conv.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: tile),
        onDragEnd: (details) => _showSplitModeDialog(index),
        child: tile,
      );
    }

    return tile;
  }

  Future<bool?> _confirmDelete() {
    final colorScheme = Theme.of(context).colorScheme;

    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Conversation'),
        content: const Text('Are you sure you want to delete this conversation?'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildTileContent(int index, Conversation conv, bool isSelected, bool isGenerating, bool showDragHandle) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => widget.onLoadConversation(index),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected
                  ? colorScheme.primaryContainer
                  : colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isGenerating
                    ? colorScheme.tertiary
                    : (isSelected ? colorScheme.primary : Colors.transparent),
                width: isGenerating ? 2.0 : 1.5,
              ),
              boxShadow: isSelected || isGenerating
                  ? [
                BoxShadow(
                  color: (isGenerating ? colorScheme.tertiary : colorScheme.primary).withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                )
              ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (showDragHandle)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(Icons.drag_indicator, size: 18, color: colorScheme.onSurfaceVariant),
                      ),
                    Expanded(
                      child: Text(
                        conv.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          height: 1.3,
                          color: isSelected ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
                        ),
                      ),
                    ),
                    _buildQuickActions(index, conv),
                  ],
                ),
                const SizedBox(height: 8),
                _buildMetadata(conv),
                if (isGenerating) GeneratingIndicator(isDarkMode: widget.isDarkMode),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetadata(Conversation conv) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Icon(Icons.schedule_rounded, size: 12, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            DateFormatter.formatTimestamp(conv.timestamp),
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.chat_bubble_rounded, size: 10, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                '${conv.messageCount}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActions(int index, Conversation conv) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded, size: 18, color: colorScheme.onSurfaceVariant),
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      offset: const Offset(-10, 30),
      onSelected: (value) {
        switch (value) {
          case 'export':
            widget.onExportConversation(conv);
            break;
          case 'delete':
            widget.onDeleteConversation(index);
            break;
          case 'split':
            if (widget.onEnableSplitMode != null) {
              _showSplitModeDialog(index);
            }
            break;
        }
      },
      itemBuilder: (context) => [
        if (widget.onEnableSplitMode != null && !widget.isSplitMode)
          PopupMenuItem(
            value: 'split',
            child: Row(
              children: [
                Icon(Icons.splitscreen, size: 18, color: colorScheme.primary),
                const SizedBox(width: 12),
                const Text('Open in Split View', style: TextStyle(fontSize: 14)),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'export',
          child: Row(
            children: [
              Icon(Icons.download_rounded, size: 18, color: colorScheme.tertiary),
              const SizedBox(width: 12),
              const Text('Export', style: TextStyle(fontSize: 14)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_rounded, size: 18, color: colorScheme.error),
              const SizedBox(width: 12),
              Text('Delete', style: TextStyle(fontSize: 14, color: colorScheme.error)),
            ],
          ),
        ),
      ],
    );
  }


  Widget _buildSettingsSection() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        _buildSectionHeader(
          title: 'Settings',
          icon: Icons.settings_rounded,
          count: 0,
          isExpanded: _isSettingsExpanded,
          onToggle: _toggleSettings,
        ),
        if (_isSettingsExpanded)
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
              border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
            ),
            child: Column(
              children: [
                _buildSettingTile(
                  icon: widget.isDarkMode ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                  iconColor: colorScheme.secondary,
                  title: 'Dark Mode',
                  trailing: Switch(
                    value: widget.isDarkMode,
                    onChanged: (_) => widget.onToggleTheme(),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onTap: widget.onToggleTheme,
                ),
                const SizedBox(height: 4),
                _buildSettingTile(
                  icon: Icons.cloud_download_rounded,
                  iconColor: colorScheme.primary,
                  title: 'Export All',
      trailing: Icon(Icons.chevron_right_rounded, size: 20, color: Colors.grey[600]),
      onTap: widget.onExportAll,
    ),
      const SizedBox(height: 4),
      _buildSettingTile(
        icon: Icons.delete_sweep_rounded,
        iconColor: widget.isDarkMode ? Colors.red[300]! : Colors.red[700]!,
        title: 'Clear All',
        trailing: Icon(Icons.chevron_right_rounded, size: 20, color: Colors.grey[600]),
        onTap: _showClearAllDialog,
      ),
      const SizedBox(height: 4),
      _buildSettingTile(
        icon: Icons.info_outline_rounded,
        iconColor: widget.isDarkMode ? Colors.purple[300]! : Colors.purple[700]!,
        title: 'About',
        trailing: Icon(Icons.chevron_right_rounded, size: 20, color: Colors.grey[600]),
        onTap: _showAboutDialog,
      ),
    ],
    ),
    ),
      ],
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Widget trailing,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}