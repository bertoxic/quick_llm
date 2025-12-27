import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_llm/provider/ChatProvider.dart';
import 'package:quick_llm/provider/SplitScreenManager_provider.dart';
import 'package:quick_llm/screens/chatScreen.dart';
import 'package:quick_llm/screens/chat_screen.dart';
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
  @override
  void initState() {
    super.initState();
    _loadTheme();
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
          home: ChatScreen(
            toggleTheme: toggleTheme,
            isDarkMode: chatProvider.isDarkMode,
          ),
        );
      },
    );
  }
}