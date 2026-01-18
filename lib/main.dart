import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_llm/provider/ChatProvider.dart';
import 'package:quick_llm/provider/SplitScreenManager_provider.dart';
import 'package:quick_llm/screens/chatScreen.dart';
import 'package:quick_llm/screens/connection_state_screen.dart';
import 'package:quick_llm/services/ollama_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(1000, 700),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => SplitScreenManager()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _ollamaConnected = false;
  bool _isCheckingConnection = true;

  @override
  void initState() {
    super.initState();
    _loadTheme();
    _checkOllamaOnStartup();
  }

  Future<void> _checkOllamaOnStartup() async {
    setState(() => _isCheckingConnection = true);

    // Give a brief moment for the UI to render
    await Future.delayed(const Duration(milliseconds: 100));

    try {
      // Use OllamaService directly instead of through ChatProvider
      final ollamaService = OllamaService();
      final models = await ollamaService.fetchAvailableModels(
        timeout: const Duration(seconds: 5),
      );

      setState(() {
        _ollamaConnected = models.isNotEmpty;
        _isCheckingConnection = false;
      });
    } catch (e) {
      setState(() {
        _ollamaConnected = false;
        _isCheckingConnection = false;
      });
    }
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('darkMode') ?? true;

    if (mounted) {
      context.read<ChatProvider>().setDarkMode(isDark);
    }
  }

  void toggleTheme() async {
    context.read<ChatProvider>().toggleDarkMode();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('darkMode', context.read<ChatProvider>().isDarkMode);
  }

  void _onOllamaConnectionSuccess() {
    setState(() => _ollamaConnected = true);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, chatProvider, child) {
        return MaterialApp(
          title: 'Ollama Chat',
          debugShowCheckedModeBanner: false,
          theme: ThemeData.light(useMaterial3: true),
          darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
            scaffoldBackgroundColor: const Color(0xFF1A1A1A),
            cardColor: const Color(0xFF2A2A2A),
          ),
          themeMode: chatProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          home: _isCheckingConnection
              ? const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          )
              : _ollamaConnected
              ? ChatScreen(
            toggleTheme: toggleTheme,
            isDarkMode: chatProvider.isDarkMode,
          )
              : OllamaConnectionScreen(
            onConnectionSuccess: _onOllamaConnectionSuccess,
          ),
        );
      },
    );
  }
}