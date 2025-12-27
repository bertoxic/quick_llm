// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import 'package:window_manager/window_manager.dart';
// import 'package:file_picker/file_picker.dart';
// import 'dart:async';
// import 'dart:io';
// import '../../dialogs/settings_dialog.dart';
// import '../../models/chat_message.dart';
// import '../../models/conversation.dart';
// import '../../provider/ChatProvider.dart';
// import '../../services/ollama_service.dart';
// import '../../services/storage_service.dart';
// import '../../widgets/chat_header.dart';
// import '../../widgets/message_bubble.dart';
// import '../../widgets/sidebar.dart';
// import '../../widgets/typing_indicaator.dart';
// import '../../utils/conversation_manager.dart';
// import '../../utils/message_stream_handler.dart';
// import '../provider/SplitScreenManager_provider.dart';
// import '../utils/context_manager.dart';
// import 'mini_mode_screen.dart';
//
// class ChatScreen extends StatefulWidget {
//   final VoidCallback toggleTheme;
//   final bool isDarkMode;
//
//   const ChatScreen({
//     super.key,
//     required this.toggleTheme,
//     required this.isDarkMode,
//   });
//
//   @override
//   State<ChatScreen> createState() => _ChatScreenState();
// }
//
// class _ChatScreenState extends State<ChatScreen> with WindowListener {
//   final TextEditingController _controller = TextEditingController();
//   final TextEditingController _systemPromptController = TextEditingController();
//   final ScrollController _scrollController = ScrollController();
//   final OllamaService _ollamaService = OllamaService();
//   final StorageService _storageService = StorageService();
//   late final SplitScreenManager _splitScreenManager;
//
//   late final ConversationManager _conversationManager;
//   late final MessageStreamHandler _messageStreamHandler;
//
//   bool _isAlwaysOnTop = false;
//   bool _isMiniMode = false;
//   List<String> _availableModels = [];
//   String _streamingResponse = '';
//
//   // For file attachments
//   List<File> _attachedFiles = [];
//   final List<String> _supportedImageExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'];
//   final List<String> _supportedDocExtensions = ['.pdf', '.txt', '.doc', '.docx', '.md'];
//
//   // For cancellation support
//   bool _shouldStopGeneration = false;
//
//
//   // Auto-scroll control
//   bool _userHasScrolled = false;
//   bool _isAutoScrollEnabled = true;
//   bool _isProgrammaticScroll = false;
//
//   // File attachment preference
//   bool _copyFileAttachments = true;
//
//   // Stream subscription for cleanup
//   StreamSubscription? _currentStreamSubscription;
//
//   @override
//   void initState() {
//     super.initState();
//     _splitScreenManager = SplitScreenManager();
//     _conversationManager = ConversationManager(_storageService);
//     _messageStreamHandler = MessageStreamHandler(_ollamaService);
//     windowManager.addListener(this);
//     _initializeApp();
//   }
//
//   Future<void> _initializeApp() async {
//     await _loadConversations();
//     await _loadPreferences();
//     await _fetchAvailableModels();
//     _startNewConversation();
//     _setupScrollListener();
//   }
//
//   @override
//   void dispose() {
//     // Cancel any active stream
//     _currentStreamSubscription?.cancel();
//     windowManager.removeListener(this);
//     _controller.dispose();
//     _systemPromptController.dispose();
//     _scrollController.dispose();
//     _messageStreamHandler.dispose();
//     super.dispose();
//   }
//
//   Future<void> _sendMessage({bool regenerate = false, String? message}) async {
//     if (!mounted) return;
//
//     final provider = context.read<ChatProvider>();
//     final messageText = message ?? _controller.text.trim();
//
//     if (!provider.hasValidModel) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(
//           content: Text('⚠️ No model selected. Please select a model first.'),
//           duration: Duration(seconds: 3),
//         ),
//       );
//       return;
//     }
//
//     if (messageText.isEmpty || provider.isGenerating || provider.isSending) {
//       debugPrint('⚠️ Message send blocked');
//       return;
//     }
//
//     final userMessage = ChatMessage(
//       text: messageText,
//       isUser: true,
//       timestamp: DateTime.now(),
//       attachedFiles: _attachedFiles.isNotEmpty
//           ? _attachedFiles.map((f) => f.path).toList()
//           : null,
//     );
//
//     // Add user message to UI
//     if (!regenerate) {
//       provider.addMessage(userMessage);
//     }
//
//     // Start generation
//     provider.startGenerating();
//
//     // Add empty assistant message
//     provider.addMessage(ChatMessage(
//       text: '',
//       isUser: false,
//       timestamp: DateTime.now(),
//       modelName: provider.selectedModel,
//     ));
//
//     setState(() {
//       _shouldStopGeneration = false;
//       _isAutoScrollEnabled = true;
//       _userHasScrolled = false;
//     });
//
//     if (!regenerate) {
//       _controller.clear();
//       _attachedFiles.clear();
//     }
//     _scrollToBottom();
//
//     // Create/update conversation
//     _conversationManager.createOrUpdate(userMessage, provider);
//     final generatingForConversationIndex = provider.selectedConversationIndex;
//
//     try {
//       // Get messages for context (exclude the newly added user message and empty assistant message)
//       final allMessages = provider.messages;
//       final messagesForContext = allMessages.length >= 2
//           ? allMessages.sublist(0, allMessages.length - 2)
//           : <ChatMessage>[];
//
//       debugPrint('📚 Total messages in conversation: ${allMessages.length}');
//       debugPrint('📚 Messages for context: ${messagesForContext.length}');
//
//       // Separate attached files
//       List<String>? imageFiles;
//       List<String>? documentFiles;
//
//       if (userMessage.attachedFiles != null && userMessage.attachedFiles!.isNotEmpty) {
//         final images = <String>[];
//         final documents = <String>[];
//
//         for (final filePath in userMessage.attachedFiles!) {
//           final extension = filePath.toLowerCase().substring(filePath.lastIndexOf('.'));
//
//           if (_supportedImageExtensions.contains(extension)) {
//             images.add(filePath);
//           } else if (_supportedDocExtensions.contains(extension)) {
//             documents.add(filePath);
//           }
//         }
//
//         imageFiles = images.isNotEmpty ? images : null;
//         documentFiles = documents.isNotEmpty ? documents : null;
//       }
//
//       // ✅ CRITICAL FIX: Build messages array for Ollama chat endpoint
//       final messagesArray = <Map<String, String>>[];
//
//       // Add all previous messages from context
//       for (final msg in messagesForContext) {
//         messagesArray.add({
//           'role': msg.isUser ? 'user' : 'assistant',
//           'content': msg.text,
//         });
//       }
//
//       // Add current user message
//       messagesArray.add({
//         'role': 'user',
//         'content': messageText,
//       });
//
//       debugPrint('📨 Sending ${messagesArray.length} messages to Ollama');
//       debugPrint('📨 Last 3 messages:');
//       final startIdx = messagesArray.length > 3 ? messagesArray.length - 3 : 0;
//       for (var i = startIdx; i < messagesArray.length; i++) {
//         final msg = messagesArray[i];
//         final preview = msg['content']!.length > 100
//             ? '${msg['content']!.substring(0, 100)}...'
//             : msg['content']!;
//         debugPrint('   [${msg['role']}]: $preview');
//       }
//
//       // Generate response using messages array (NOT concatenated prompt)
//       final stream = _ollamaService.generateResponse(
//         model: provider.selectedModel,
//         prompt: messageText, // Single message prompt (used as fallback)
//         messagesArray: messagesArray, // ✅ Pass full conversation history
//         systemPrompt: provider.useSystemPrompt ? provider.systemPrompt : null,
//         temperature: provider.temperature,
//         maxTokens: provider.maxTokens,
//         images: imageFiles,
//         documents: documentFiles,
//       );
//
//       await _messageStreamHandler.handleStream(
//         stream: stream,
//         provider: provider,
//         generatingForIndex: generatingForConversationIndex,
//         onUpdate: () {
//           if (mounted &&
//               provider.selectedConversationIndex == generatingForConversationIndex) {
//             setState(() {});
//             if (_isAutoScrollEnabled) {
//               _scrollToBottom();
//             }
//           }
//         },
//         onStopGenerationChanged: (isSending) {
//           if (mounted) {
//             provider.setIsSending(isSending);
//           }
//         },
//       );
//
//       // Save conversation
//       if (generatingForConversationIndex != null && mounted) {
//         _conversationManager.saveAtIndex(provider, generatingForConversationIndex);
//         debugPrint('✅ Message stream finished\n');
//       }
//
//     } catch (e) {
//       debugPrint('❌ Error during streaming: $e');
//       if (mounted) {
//         provider.stopGenerating();
//         provider.setIsSending(false);
//       }
//     } finally {
//       if (mounted) {
//         provider.setIsSending(false);
//       }
//     }
//   }
//
//   void _stopGeneration() {
//     debugPrint('🛑 Stop button pressed');
//
//     if (!mounted) return;
//     final provider = context.read<ChatProvider>();
//
//     if (provider.generatingConversationIndex != null) {
//       _conversationManager.saveAtIndex(provider, provider.generatingConversationIndex!);
//     }
//
//     _messageStreamHandler.cancelActiveStream(); // Add this line
//     _currentStreamSubscription?.cancel();
//     _currentStreamSubscription = null;
//
//     _ollamaService.cancelGeneration();
//     provider.stopGenerating();
//     provider.setIsSending(false);
//
//     setState(() {
//       _shouldStopGeneration = true;
//     });
//   }
//
//   void _setupScrollListener() {
//     _scrollController.addListener(() {
//       if (!_scrollController.hasClients || !mounted) return;
//       if (_isProgrammaticScroll) return;
//
//       final provider = context.read<ChatProvider>();
//       if (provider.isGenerating && _isAutoScrollEnabled) {
//         final isAtBottom = _scrollController.position.pixels >=
//             _scrollController.position.maxScrollExtent - 50;
//
//         if (!isAtBottom) {
//           // Fixed: No setState, just update the flag
//           _isAutoScrollEnabled = false;
//           _userHasScrolled = true;
//           debugPrint('🔒 Auto-scroll disabled - user scrolled up');
//         }
//       }
//     });
//   }
//
//   Future<void> _savePreferences() async {
//     if (!mounted) return;
//     final provider = context.read<ChatProvider>();
//     await _storageService.savePreferences({
//       'sidebarVisible': provider.isSidebarVisible,
//       'systemPrompt': provider.systemPrompt,
//       'temperature': provider.temperature,
//       'maxTokens': provider.maxTokens,
//       'useSystemPrompt': provider.useSystemPrompt,
//       'monitorClipboard': false,
//       'copyFileAttachments': _copyFileAttachments,
//     });
//   }
//
//   Future<void> _fetchAvailableModels() async {
//     try {
//       final models = await _ollamaService.fetchAvailableModels();
//       if (models.isNotEmpty && mounted) {
//         final provider = context.read<ChatProvider>();
//         setState(() {
//           _availableModels = models;
//         });
//
//         // Set the first model if none is selected or current selection is invalid
//         if (provider.selectedModel == null || !models.contains(provider.selectedModel)) {
//           provider.setSelectedModel(models.first);
//         }
//       } else if (models.isEmpty && mounted) {
//         final provider = context.read<ChatProvider>();
//         setState(() {
//           _availableModels = [];
//         });
//         provider.setSelectedModel(null); // Clear invalid selection
//
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(
//             content: Text('⚠️ No models found. Please install Ollama models.'),
//             duration: Duration(seconds: 5),
//           ),
//         );
//       }
//     } catch (e) {
//       debugPrint('Error fetching models: $e');
//       if (mounted) {
//         final provider = context.read<ChatProvider>();
//         setState(() {
//           _availableModels = [];
//         });
//         provider.setSelectedModel(null);
//
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text('⚠️ Cannot connect to Ollama: $e'),
//             duration: const Duration(seconds: 5),
//           ),
//         );
//       }
//     }
//   }
//
//   Future<void> _toggleAlwaysOnTop() async {
//     try {
//       final newValue = !_isAlwaysOnTop;
//       await windowManager.setAlwaysOnTop(newValue);
//       if (mounted) {
//         setState(() {
//           _isAlwaysOnTop = newValue;
//         });
//       }
//     } catch (e) {
//       debugPrint('Error toggling always on top: $e');
//     }
//   }
//
//   void _toggleSidebar() {
//     if (!mounted) return;
//     context.read<ChatProvider>().toggleSidebar();
//     _savePreferences();
//   }
//
//   Future<void> _toggleMiniMode() async {
//     try {
//       setState(() {
//         _isMiniMode = true;
//       });
//       await windowManager.setSize(const Size(350, 500));
//       await windowManager.setAlwaysOnTop(true);
//     } catch (e) {
//       debugPrint('Error entering mini mode: $e');
//     }
//   }
//
//   void _startNewConversation() {
//     if (!mounted) return;
//     final provider = context.read<ChatProvider>();
//     provider.clearMessages();
//     provider.selectConversation(null);
//     provider.stopGenerating();
//
//     setState(() {
//       _streamingResponse = '';
//       _shouldStopGeneration = false;
//       provider.setIsSending(false);
//       _attachedFiles.clear();
//     });
//   }
//
//   Future<void> _loadPreferences() async {
//     final prefs = await _storageService.loadPreferences();
//     if (mounted) {
//       final provider = context.read<ChatProvider>();
//       provider.updateSettings(
//         isSidebarVisible: prefs['sidebarVisible'] ?? true,
//         systemPrompt: prefs['systemPrompt'] ?? '',
//         temperature: prefs['temperature'] ?? 0.7,
//         maxTokens: prefs['maxTokens'] ?? 2048,
//         useSystemPrompt: prefs['useSystemPrompt'] ?? false,
//       );
//       _systemPromptController.text = provider.systemPrompt;
//
//       // Load file attachment preference
//       setState(() {
//         _copyFileAttachments = prefs['copyFileAttachments'] ?? true;
//       });
//     }
//   }
//
//   Future<void> _pickFiles() async {
//     try {
//       FilePickerResult? result = await FilePicker.platform.pickFiles(
//         allowMultiple: true,
//         type: FileType.custom,
//         allowedExtensions: [
//           'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp',
//           'pdf', 'txt', 'doc', 'docx', 'md',
//         ],
//       );
//
//       if (result != null && result.files.isNotEmpty) {
//         List<File> filesToAttach = [];
//
//         for (var file in result.files) {
//           if (file.path != null) {
//             try {
//               final filePath = await _storageService.saveAttachment(
//                 file.path!,
//                 copyFile: _copyFileAttachments,
//               );
//               filesToAttach.add(File(filePath));
//
//               if (_copyFileAttachments) {
//                 debugPrint('✅ File copied to: $filePath');
//               } else {
//                 debugPrint('📌 File referenced at: $filePath');
//               }
//             } catch (e) {
//               debugPrint('❌ Failed to process file: ${file.name}, error: $e');
//               if (mounted) {
//                 ScaffoldMessenger.of(context).showSnackBar(
//                   SnackBar(content: Text('Failed to attach ${file.name}')),
//                 );
//               }
//             }
//           }
//         }
//
//         if (filesToAttach.isNotEmpty && mounted) {
//           setState(() {
//             _attachedFiles.addAll(filesToAttach);
//           });
//           debugPrint('📎 Total files attached: ${_attachedFiles.length}');
//         }
//       }
//     } catch (e) {
//       debugPrint('❌ Error picking files: $e');
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text('Failed to pick files: $e')),
//         );
//       }
//     }
//   }
//
//   Future<void> _checkMissingAttachments() async {
//     if (!mounted) return;
//     final provider = context.read<ChatProvider>();
//     final allFiles = <String>[];
//
//     for (var message in provider.messages) {
//       if (message.attachedFiles != null) {
//         allFiles.addAll(message.attachedFiles!);
//       }
//     }
//
//     if (allFiles.isEmpty) return;
//
//     final missing = await _storageService.getMissingAttachments(allFiles);
//
//     if (missing.isNotEmpty && mounted) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(
//           content: Text('⚠️ ${missing.length} attached file(s) are missing'),
//           action: SnackBarAction(
//             label: 'Details',
//             onPressed: () {
//               showDialog(
//                 context: context,
//                 builder: (context) => AlertDialog(
//                   title: const Text('Missing Files'),
//                   content: SingleChildScrollView(
//                     child: Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       mainAxisSize: MainAxisSize.min,
//                       children: missing.map((path) =>
//                           Padding(
//                             padding: const EdgeInsets.only(bottom: 8),
//                             child: Text('• ${_getFileName(path)}'),
//                           )
//                       ).toList(),
//                     ),
//                   ),
//                   actions: [
//                     TextButton(
//                       onPressed: () => Navigator.pop(context),
//                       child: const Text('OK'),
//                     ),
//                   ],
//                 ),
//               );
//             },
//           ),
//           duration: const Duration(seconds: 5),
//         ),
//       );
//     }
//   }
//
//   void _loadConversation(int index) {
//     if (!mounted) return;
//     final provider = context.read<ChatProvider>();
//     if (index < 0 || index >= provider.conversations.length) return;
//
//     // Fixed: Actually prevent switching during generation
//     if (provider.isGenerating) {
//       debugPrint('⚠️ Cannot switch conversations while generating');
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(
//           content: Text('Please wait for the current response to finish'),
//           duration: Duration(seconds: 2),
//         ),
//       );
//    //   return;
//     }
//
//     provider.selectConversation(index);
//     final messages = provider.conversations[index].messages.map((m) => ChatMessage(
//       text: m.text,
//       isUser: m.isUser,
//       timestamp: m.timestamp,
//       thinkingText: m.thinkingText,
//       isThinking: m.isThinking,
//       modelName: m.modelName,
//       attachedFiles: m.attachedFiles,
//     )).toList();
//     provider.setMessages(messages);
//
//     // Check for missing attachments
//     _checkMissingAttachments();
//
//     _scrollToBottom();
//   }
//
//   void _removeAttachedFile(int index) {
//     if (index >= 0 && index < _attachedFiles.length) {
//       setState(() {
//         _attachedFiles.removeAt(index);
//       });
//     }
//   }
//
//   String _getFileIcon(String path) {
//     final extension = path.toLowerCase().substring(path.lastIndexOf('.'));
//
//     if (_supportedImageExtensions.contains(extension)) {
//       return '🖼️';
//     } else if (extension == '.pdf') {
//       return '📄';
//     } else if (['.doc', '.docx'].contains(extension)) {
//       return '📝';
//     } else if (extension == '.txt') {
//       return '📃';
//     } else if (extension == '.md') {
//       return '📋';
//     }
//     return '📎';
//   }
//
//   String _getFileName(String path) {
//     return path.split('/').last;
//   }
//
//   Future<void> _loadConversations() async {
//     final conversations = await _conversationManager.load();
//     if (mounted) {
//       context.read<ChatProvider>().setConversations(conversations);
//     }
//   }
//
//   void _deleteConversation(int index) {
//     if (!mounted) return;
//     final provider = context.read<ChatProvider>();
//     if (index < 0 || index >= provider.conversations.length) return;
//
//     provider.deleteConversation(index);
//     _conversationManager.save(provider);
//   }
//
//   void _regenerateLastResponse() async {
//     if (!mounted) return;
//     final provider = context.read<ChatProvider>();
//     if (provider.messages.length < 2 || provider.isGenerating) return;
//
//     provider.removeLastMessage();
//     final lastUserMessage = provider.messages.last.text;
//     _sendMessage(regenerate: true, message: lastUserMessage);
//   }
//
//   void _editMessage(int index) {
//     if (!mounted) return;
//     final provider = context.read<ChatProvider>();
//     if (index < 0 || index >= provider.messages.length) return;
//
//     final message = provider.messages[index];
//     _controller.text = message.text;
//     provider.removeMessagesFromIndex(index);
//   }
//
//   void _scrollToBottom() {
//     WidgetsBinding.instance.addPostFrameCallback((_) {
//       if (_scrollController.hasClients && mounted) {
//         _isProgrammaticScroll = true;
//         _scrollController.animateTo(
//           _scrollController.position.maxScrollExtent,
//           duration: const Duration(milliseconds: 300),
//           curve: Curves.easeOut,
//         ).then((_) {
//           _isProgrammaticScroll = false;
//         });
//       }
//     });
//   }
//
//   void _showSettingsDialog() {
//     if (!mounted) return;
//     final provider = context.read<ChatProvider>();
//     showDialog(
//       context: context,
//       builder: (context) => SettingsDialog(
//         systemPromptController: _systemPromptController,
//         useSystemPrompt: provider.useSystemPrompt,
//         temperature: provider.temperature,
//         maxTokens: provider.maxTokens,
//         onUseSystemPromptChanged: (value) {
//           provider.setUseSystemPrompt(value);
//         },
//         onTemperatureChanged: (value) {
//           provider.setTemperature(value);
//         },
//         onMaxTokensChanged: (value) {
//           provider.setMaxTokens(value);
//         },
//         onSave: () {
//           provider.setSystemPrompt(_systemPromptController.text);
//           _savePreferences();
//         },
//         isDarkMode: widget.isDarkMode,
//       ),
//     );
//   }
//
//   Future<void> _exportConversation(Conversation conv) async {
//     try {
//       final path = await _conversationManager.exportConversation(conv);
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text('Exported to $path')),
//         );
//       }
//     } catch (e) {
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text('Export failed: $e')),
//         );
//       }
//     }
//   }
//
//   Future<void> _exportAllConversations() async {
//     try {
//       final provider = context.read<ChatProvider>();
//       final path = await _conversationManager.exportAll(provider.conversations);
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text('Exported all to $path')),
//         );
//       }
//     } catch (e) {
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text('Export failed: $e')),
//         );
//       }
//     }
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Consumer<ChatProvider>(
//       builder: (context, provider, child) {
//         if (_isMiniMode) {
//           return MiniModeScreen(
//             isDarkMode: widget.isDarkMode,
//             availableModels: _availableModels,
//             onExitMiniMode: () async {
//               try {
//                 setState(() {
//                   _isMiniMode = false;
//                 });
//                 await windowManager.setSize(const Size(1000, 700));
//                 if (!_isAlwaysOnTop) {
//                   await windowManager.setAlwaysOnTop(false);
//                 }
//               } catch (e) {
//                 debugPrint('Error exiting mini mode: $e');
//               }
//             },
//           );
//         }
//
//         return Scaffold(
//           body: Row(
//             children: [
//               if (provider.isSidebarVisible)
//                 Sidebar(
//                   isDarkMode: widget.isDarkMode,
//                   conversations: provider.conversations,
//                   selectedConversationIndex: provider.selectedConversationIndex,
//                   generatingConversationIndex: provider.generatingConversationIndex,
//                   onNewChat: _startNewConversation,
//                   onLoadConversation: _loadConversation,
//                   onDeleteConversation: _deleteConversation,
//                   onExportConversation: _exportConversation,
//                   onExportAll: _exportAllConversations,
//                   onToggleTheme: widget.toggleTheme,
//                   onClearAllConversations: () async {
//                     final success = await _storageService.clearAllConversations();
//                     if (success) {
//                       setState(() {
//                         provider.conversations.clear();
//                         //_currentConversation = null;
//                       });
//                       // Show success message
//                       ScaffoldMessenger.of(context).showSnackBar(
//                         const SnackBar(content: Text('All conversations cleared')),
//                       );
//                     }}),
//               Expanded(
//                 child: Column(
//                   children: [
//                     // Header - fixed height
//                     ChatHeader(
//                       isDarkMode: widget.isDarkMode,
//                       isSidebarVisible: provider.isSidebarVisible,
//                       selectedModel: provider.selectedModel,
//                       availableModels: _availableModels,
//                       isAlwaysOnTop: _isAlwaysOnTop,
//                       onToggleSidebar: _toggleSidebar,
//                       onModelChanged: (model) {
//                         provider.setSelectedModel(model);
//                       },
//                       onSettingsTap: _showSettingsDialog,
//                       onMiniModeTap: _toggleMiniMode,
//                       onToggleAlwaysOnTop: _toggleAlwaysOnTop,
//                       onRefreshModels: _fetchAvailableModels,
//                     ),
//
//                     // Messages area - flexible
//                     Expanded(
//                       child: provider.messages.isEmpty
//                           ? Center(
//                         child: Column(
//                           mainAxisAlignment: MainAxisAlignment.center,
//                           mainAxisSize: MainAxisSize.min,
//                           children: [
//                             Icon(
//                               Icons.chat_bubble_outline,
//                               size: 64,
//                               color: Colors.grey[400],
//                             ),
//                             const SizedBox(height: 16),
//                             Text(
//                               'Start a conversation',
//                               style: TextStyle(
//                                 fontSize: 20,
//                                 color: Colors.grey[400],
//                               ),
//                             ),
//                           ],
//                         ),
//                       )
//                           : ListView.builder(
//                         controller: _scrollController,
//                         padding: const EdgeInsets.all(16),
//                         itemCount: provider.messages.length +
//                             (provider.isGenerating ? 1 : 0),
//                         itemBuilder: (context, index) {
//                           if (provider.isGenerating &&
//                               index == provider.messages.length) {
//                             return TypingIndicator(
//                               isDarkMode: widget.isDarkMode,
//                               modelName: provider.selectedModel,
//                             );
//                           }
//
//                           final message = provider.messages[index];
//                           return MessageBubble(
//                             message: message,
//                             isDarkMode: widget.isDarkMode,
//                             onEdit: message.isUser
//                                 ? () => _editMessage(index)
//                                 : null,
//                             onRegenerate: !message.isUser &&
//                                 index == provider.messages.length - 1 &&
//                                 !provider.isGenerating
//                                 ? _regenerateLastResponse
//                                 : null,
//                           );
//                         },
//                       ),
//                     ),
//
//                     // Input area - fixed but flexible height based on content
//                     Container(
//                       constraints: BoxConstraints(
//                         maxHeight: MediaQuery.of(context).size.height * 0.3,
//                       ),
//                       decoration: BoxDecoration(
//                         color: widget.isDarkMode
//                             ? const Color(0xFF2A2A2A)
//                             : Colors.grey[200],
//                         border: Border(
//                           top: BorderSide(
//                             color: widget.isDarkMode
//                                 ? Colors.grey[800]!
//                                 : Colors.grey[300]!,
//                           ),
//                         ),
//                       ),
//                       child: SingleChildScrollView(
//                         child: Padding(
//                           padding: const EdgeInsets.all(16),
//                           child: Column(
//                             crossAxisAlignment: CrossAxisAlignment.start,
//                             mainAxisSize: MainAxisSize.min,
//                             children: [
//                               // File attachments preview
//                               if (_attachedFiles.isNotEmpty)
//                                 Container(
//                                   margin: const EdgeInsets.only(bottom: 12),
//                                   padding: const EdgeInsets.all(8),
//                                   decoration: BoxDecoration(
//                                     color: widget.isDarkMode
//                                         ? Colors.grey[800]
//                                         : Colors.grey[300],
//                                     borderRadius: BorderRadius.circular(8),
//                                   ),
//                                   child: Wrap(
//                                     spacing: 8,
//                                     runSpacing: 8,
//                                     children: _attachedFiles
//                                         .asMap()
//                                         .entries
//                                         .map((entry) {
//                                       final index = entry.key;
//                                       final file = entry.value;
//                                       return Container(
//                                         padding: const EdgeInsets.symmetric(
//                                           horizontal: 12,
//                                           vertical: 8,
//                                         ),
//                                         decoration: BoxDecoration(
//                                           color: widget.isDarkMode
//                                               ? Colors.grey[700]
//                                               : Colors.white,
//                                           borderRadius: BorderRadius.circular(6),
//                                           border: Border.all(
//                                             color: widget.isDarkMode
//                                                 ? Colors.grey[600]!
//                                                 : Colors.grey[400]!,
//                                           ),
//                                         ),
//                                         child: Row(
//                                           mainAxisSize: MainAxisSize.min,
//                                           children: [
//                                             Text(
//                                               _getFileIcon(file.path),
//                                               style: const TextStyle(fontSize: 16),
//                                             ),
//                                             const SizedBox(width: 6),
//                                             ConstrainedBox(
//                                               constraints: const BoxConstraints(
//                                                   maxWidth: 150),
//                                               child: Text(
//                                                 _getFileName(file.path),
//                                                 overflow: TextOverflow.ellipsis,
//                                                 style: const TextStyle(fontSize: 13),
//                                               ),
//                                             ),
//                                             const SizedBox(width: 6),
//                                             InkWell(
//                                               onTap: () =>
//                                                   _removeAttachedFile(index),
//                                               child: Icon(
//                                                 Icons.close,
//                                                 size: 16,
//                                                 color: Colors.red[400],
//                                               ),
//                                             ),
//                                           ],
//                                         ),
//                                       );
//                                     }).toList(),
//                                   ),
//                                 ),
//
//                               // Message input row
//                               Row(
//                                 crossAxisAlignment: CrossAxisAlignment.end,
//                                 children: [
//                                   // Attach file button
//                                   IconButton(
//                                     icon: Icon(
//                                       Icons.attach_file,
//                                       color: _attachedFiles.isNotEmpty
//                                           ? Colors.blue
//                                           : null,
//                                     ),
//                                     onPressed: provider.isGenerating
//                                         ? null
//                                         : _pickFiles,
//                                     tooltip:
//                                     'Attach files (images, PDFs, documents)',
//                                   ),
//                                   const SizedBox(width: 4),
//
//                                   // Text input
//                                   Expanded(
//                                     child: ConstrainedBox(
//                                       constraints: const BoxConstraints(
//                                         maxHeight: 150,
//                                       ),
//                                       child: TextField(
//                                         controller: _controller,
//                                         decoration: const InputDecoration(
//                                           hintText: 'Type a message...',
//                                           border: OutlineInputBorder(),
//                                           contentPadding: EdgeInsets.symmetric(
//                                             horizontal: 12,
//                                             vertical: 12,
//                                           ),
//                                         ),
//                                         maxLines: null,
//                                         textInputAction: TextInputAction.newline,
//                                         onSubmitted: (_) => provider.isGenerating
//                                             ? null
//                                             : _sendMessage(),
//                                         enabled: !provider.isGenerating,
//                                       ),
//                                     ),
//                                   ),
//                                   const SizedBox(width: 8),
//
//                                   // Send/Stop button
//                                   if (provider.isGenerating)
//                                     IconButton(
//                                       icon: const Icon(Icons.stop_circle),
//                                       onPressed: _stopGeneration,
//                                       iconSize: 28,
//                                       color: Colors.red,
//                                       tooltip: 'Stop generation',
//                                     )
//                                   else
//                                     IconButton(
//                                       icon: const Icon(Icons.send),
//                                       onPressed: _sendMessage,
//                                       iconSize: 28,
//                                       tooltip: 'Send message',
//                                     ),
//                                 ],
//                               ),
//                             ],
//                           ),
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ],
//           ),
//         );
//       },
//     );
//   }
//   }