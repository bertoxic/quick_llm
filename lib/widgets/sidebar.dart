import 'package:flutter/material.dart';
import 'package:quick_llm/widgets/typing_indicaator.dart';
import '../models/conversation.dart';
import '../utils/date_formatter.dart';

/// Enhanced sidebar with split screen drag-and-drop support
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

class _SidebarState extends State<Sidebar> with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';
  bool _isSearching = false;
  bool _isConversationsExpanded = true;
  bool _isSettingsExpanded = true;
  late AnimationController _conversationsAnimController;
  late AnimationController _settingsAnimController;
  int? _draggedIndex;

  @override
  void initState() {
    super.initState();
    _conversationsAnimController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
      value: 1.0,
    );
    _settingsAnimController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _conversationsAnimController.dispose();
    _settingsAnimController.dispose();
    super.dispose();
  }

  void _toggleConversations() {
    setState(() {
      _isConversationsExpanded = !_isConversationsExpanded;
      if (_isConversationsExpanded) {
        _conversationsAnimController.forward();
      } else {
        _conversationsAnimController.reverse();
      }
    });
  }

  void _toggleSettings() {
    setState(() {
      _isSettingsExpanded = !_isSettingsExpanded;
      if (_isSettingsExpanded) {
        _settingsAnimController.forward();
      } else {
        _settingsAnimController.reverse();
      }
    });
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue[400]!, Colors.purple[400]!],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.info_outline, color: Colors.white, size: 24),
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
                color: widget.isDarkMode ? Colors.blue[300] : Colors.blue[700],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'A fast and efficient LLM chat interface built with Flutter.',
              style: TextStyle(fontSize: 14, color: Colors.grey[600], height: 1.5),
            ),
            const SizedBox(height: 16),
            Divider(color: Colors.grey[300]),
            const SizedBox(height: 12),
            _buildAboutRow(Icons.code, 'Built with Flutter'),
            const SizedBox(height: 8),
            _buildAboutRow(Icons.chat_bubble_outline, 'AI-Powered Conversations'),
            const SizedBox(height: 8),
            _buildAboutRow(Icons.security, 'Privacy-Focused'),
            const SizedBox(height: 8),
            _buildAboutRow(Icons.splitscreen, 'Split Screen Support'),
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
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.warning_amber_rounded, color: Colors.red[700], size: 24),
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
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: widget.isDarkMode ? Colors.red[900]!.withOpacity(0.2) : Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: widget.isDarkMode ? Colors.red[800]! : Colors.red[200]!,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.red[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This action cannot be undone.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red[700],
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
              backgroundColor: Colors.red[600],
              foregroundColor: Colors.white,
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }

  void _showSplitModeDialog(int draggedIndex) {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue[400]!, Colors.purple[400]!],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.splitscreen, color: Colors.white, size: 24),
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
              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
            ),
            const SizedBox(height: 16),
            Container(
              constraints: const BoxConstraints(maxHeight: 300),
              child: SingleChildScrollView(
                child: Column(
                  children: widget.conversations.asMap().entries.where((entry) {
                    return entry.key != draggedIndex;
                  }).map((entry) {
                    final index = entry.key;
                    final conv = entry.value;
                    return ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: widget.isDarkMode ? Colors.blue[900]!.withOpacity(0.3) : Colors.blue[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.chat_bubble_outline,
                          size: 20,
                          color: widget.isDarkMode ? Colors.blue[300] : Colors.blue[700],
                        ),
                      ),
                      title: Text(
                        conv.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14),
                      ),
                      subtitle: Text(
                        DateFormatter.formatTimestamp(conv.timestamp),
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                      onTap: () {
                        Navigator.of(context).pop();
                        widget.onEnableSplitMode?.call(draggedIndex, index);
                      },
                    );
                  }).toList(),
                ),
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

  Widget _buildAboutRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(fontSize: 13, color: Colors.grey[700]),
        ),
      ],
    );
  }

  List<Conversation> get _filteredConversations {
    if (_searchQuery.isEmpty) return widget.conversations;
    return widget.conversations
        .where((conv) => conv.title.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: _getBackgroundColor(),
        border: Border(
          right: BorderSide(
            color: _getBorderColor(),
            width: 1,
          ),
        ),
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

  /// Enhanced header with gradient and new chat button
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: widget.isDarkMode
              ? [Colors.blue[900]!.withOpacity(0.3), Colors.purple[900]!.withOpacity(0.2)]
              : [Colors.blue[50]!, Colors.purple[50]!],
        ),
      ),
      child: Column(
        children: [
          ElevatedButton.icon(
            onPressed: widget.onNewChat,
            icon: const Icon(Icons.add_rounded, size: 22),
            label: const Text(
              'New Chat',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              foregroundColor: Colors.white,
              backgroundColor: widget.isDarkMode ? Colors.blue[700] : Colors.blue[600],
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              elevation: 2,
              shadowColor: Colors.blue.withOpacity(0.4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          if (widget.isSplitMode)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: widget.isDarkMode ? Colors.green[900]!.withOpacity(0.3) : Colors.green[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: widget.isDarkMode ? Colors.green[700]! : Colors.green[300]!,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.splitscreen,
                      size: 16,
                      color: widget.isDarkMode ? Colors.green[300] : Colors.green[700],
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Split Mode Active',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: widget.isDarkMode ? Colors.green[300] : Colors.green[700],
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

  /// Collapsible conversations section
  Widget _buildConversationsSection() {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.conversations.length > 5) _buildSearchBar(),
                  // Drag hint
                  if (widget.onEnableSplitMode != null && !widget.isSplitMode)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: widget.isDarkMode
                              ? Colors.blue[900]!.withOpacity(0.2)
                              : Colors.blue[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: widget.isDarkMode ? Colors.blue[700]! : Colors.blue[200]!,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 14,
                              color: widget.isDarkMode ? Colors.blue[300] : Colors.blue[700],
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Long press & drag to split screen',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: widget.isDarkMode ? Colors.blue[300] : Colors.blue[700],
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

  /// Section header with expand/collapse functionality
  Widget _buildSectionHeader({
    required String title,
    required IconData icon,
    required int count,
    required bool isExpanded,
    required VoidCallback onToggle,
  }) {
    return Material(
      color: widget.isDarkMode ? Colors.grey[850]!.withOpacity(0.5) : Colors.grey[100],
      child: InkWell(
        onTap: onToggle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 18, color: widget.isDarkMode ? Colors.blue[300] : Colors.blue[700]),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: widget.isDarkMode ? Colors.blue[900]!.withOpacity(0.3) : Colors.blue[100],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: widget.isDarkMode ? Colors.blue[300] : Colors.blue[700],
                  ),
                ),
              ),
              const Spacer(),
              AnimatedRotation(
                turns: isExpanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 300),
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Search bar for filtering conversations
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: TextField(
        onChanged: (value) => setState(() => _searchQuery = value),
        decoration: InputDecoration(
          hintText: 'Search conversations...',
          hintStyle: TextStyle(fontSize: 13, color: Colors.grey[500]),
          prefixIcon: Icon(Icons.search, size: 20, color: Colors.grey[600]),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
            icon: Icon(Icons.clear, size: 18, color: Colors.grey[600]),
            onPressed: () => setState(() => _searchQuery = ''),
            padding: EdgeInsets.zero,
          )
              : null,
          filled: true,
          fillColor: widget.isDarkMode ? Colors.grey[850] : Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          isDense: true,
        ),
        style: const TextStyle(fontSize: 14),
      ),
    );
  }

  /// Optimized conversation list with drag-and-drop
  Widget _buildConversationList() {
    final filtered = _filteredConversations;

    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            'No conversations found',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
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
        return _buildDraggableConversationTile(actualIndex, filtered[index]);
      },
    );
  }

  /// Enhanced draggable conversation tile
  Widget _buildDraggableConversationTile(int index, Conversation conv) {
    final isSelected = widget.selectedConversationIndex == index;
    final isGenerating = widget.generatingConversationIndex == index;

    Widget tileContent = _buildConversationTileContent(index, conv, isSelected, isGenerating);

    // Add drag functionality if split mode is available
    if (widget.onEnableSplitMode != null && !widget.isSplitMode) {
      return LongPressDraggable<int>(
        data: index,
        feedback: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 240,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: widget.isDarkMode ? Colors.grey[800] : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(Icons.splitscreen, size: 18, color: Colors.blue[400]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    conv.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
        childWhenDragging: Opacity(
          opacity: 0.3,
          child: tileContent,
        ),
        onDragStarted: () {
          setState(() => _draggedIndex = index);
        },
        onDragEnd: (details) {
          setState(() => _draggedIndex = null);
          // Always show the split mode dialog when drag ends
          // This removes the dependency on wasAccepted or velocity checks
          _showSplitModeDialog(index);
        },
        child: tileContent,
      );
    }

    return tileContent;
  }

  /// Build the actual conversation tile content
  Widget _buildConversationTileContent(int index, Conversation conv, bool isSelected, bool isGenerating) {
    return Dismissible(
      key: ValueKey(conv.timestamp),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.red[400]!, Colors.red[600]!],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 24),
      ),
      confirmDismiss: (direction) async {
        return await showDialog(
          context: context,
          builder: (BuildContext context) => AlertDialog(
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
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) => widget.onDeleteConversation(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 6),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => widget.onLoadConversation(index),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: isSelected
                    ? (widget.isDarkMode ? Colors.blue[800]!.withOpacity(0.4) : Colors.blue[100])
                    : (widget.isDarkMode ? Colors.grey[850]!.withOpacity(0.5) : Colors.white),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isGenerating
                      ? Colors.green.withOpacity(0.5)
                      : (isSelected
                      ? (widget.isDarkMode ? Colors.blue[600]! : Colors.blue[300]!)
                      : Colors.transparent),
                  width: isGenerating ? 2.0 : 1.5,
                ),
                boxShadow: isSelected || isGenerating
                    ? [
                  BoxShadow(
                    color: isGenerating
                        ? Colors.green.withOpacity(0.2)
                        : Colors.blue.withOpacity(0.2),
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
                      if (widget.onEnableSplitMode != null && !widget.isSplitMode)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Icon(
                            Icons.drag_indicator,
                            size: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                      Expanded(
                        child: Text(
                          conv.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                            height: 1.3,
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
      ),
    );
  }

  /// Compact metadata row
  Widget _buildMetadata(Conversation conv) {
    return Row(
      children: [
        Icon(Icons.schedule_rounded, size: 12, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            DateFormatter.formatTimestamp(conv.timestamp),
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: widget.isDarkMode ? Colors.grey[800] : Colors.grey[200],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.chat_bubble_rounded, size: 10, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(
                '${conv.messageCount}',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Quick action buttons
  Widget _buildQuickActions(int index, Conversation conv) {
    return PopupMenuButton<String>(
        icon: Icon(Icons.more_vert_rounded, size: 18, color: Colors.grey[600]),
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        offset: const Offset(-10, 30),
        onSelected: (value) {
          if (value == 'export') {
            widget.onExportConversation(conv);
          } else if (value == 'delete') {
            widget.onDeleteConversation(index);
          } else if (value == 'split' && widget.onEnableSplitMode != null) {
            _showSplitModeDialog(index);
          }
        },
        itemBuilder: (context) => [
        if (widget.onEnableSplitMode != null && !widget.isSplitMode)
    PopupMenuItem(
      value: 'split',
      child: Row(
        children: [
          Icon(Icons.splitscreen, size: 18, color: Colors.blue[700]),
          const SizedBox(width: 12),
          const Text('Open in Split View', style: TextStyle(fontSize: 14)),
        ],
      ),
    ),

        PopupMenuItem(
          value: 'exportxx',
          child: Row(
            children: [
              Icon(Icons.download_rounded, size: 18, color: Colors.green[700]),
              const SizedBox(width: 12),
              const Text('Exportx', style: TextStyle(fontSize: 14)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_rounded, size: 18, color: Colors.red[700]),
              const SizedBox(width: 12),
              const Text('Delete', style: TextStyle(fontSize: 14, color: Colors.red)),
            ],
          ),
        ),
      ],
    );
  }
  /// Collapsible settings section
  Widget _buildSettingsSection() {
    return Column(
      mainAxisSize: MainAxisSize.min,
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
              color: widget.isDarkMode ? Colors.grey[900]!.withOpacity(0.5) : Colors.grey[50],
              border: Border(top: BorderSide(color: _getBorderColor(), width: 1)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSettingTile(
                  icon: widget.isDarkMode ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                  iconColor: widget.isDarkMode ? Colors.amber[300]! : Colors.orange[700]!,
                  title: 'Dark Mode',
                  trailing: Switch(
                    value: widget.isDarkMode,
                    onChanged: (_) => widget.onToggleTheme(),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    activeColor: widget.isDarkMode ? Colors.blue[400] : Colors.blue[600],
                  ),
                  onTap: widget.onToggleTheme,
                ),
                const SizedBox(height: 4),
                _buildSettingTile(
                  icon: Icons.cloud_download_rounded,
                  iconColor: widget.isDarkMode ? Colors.blue[300]! : Colors.blue[700]!,
                  title: 'Export All',
                  trailing: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey[600]),
                  onTap: widget.onExportAll,
                ),
                const SizedBox(height: 4),
                _buildSettingTile(
                  icon: Icons.delete_sweep_rounded,
                  iconColor: widget.isDarkMode ? Colors.red[300]! : Colors.red[700]!,
                  title: 'Clear All',
                  trailing: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey[600]),
                  onTap: _showClearAllDialog,
                ),
                const SizedBox(height: 4),
                _buildSettingTile(
                  icon: Icons.info_outline_rounded,
                  iconColor: widget.isDarkMode ? Colors.purple[300]! : Colors.purple[700]!,
                  title: 'About',
                  trailing: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey[600]),
                  onTap: _showAboutDialog,
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Reusable setting tile widget
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

  Color _getBackgroundColor() {
    return widget.isDarkMode ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5);
  }

  Color _getBorderColor() {
    return widget.isDarkMode ? Colors.grey[850]! : Colors.grey[300]!;
  }
  }