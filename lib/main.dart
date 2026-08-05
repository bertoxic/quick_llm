import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_llm/provider/ChatProvider.dart';
import 'package:quick_llm/provider/SplitScreenManager_provider.dart';
import 'package:quick_llm/screens/chatScreen.dart';
import 'package:quick_llm/theme/app_theme.dart';
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
    final isDark = prefs.getBool('darkMode') ?? false;

    if (mounted) {
      context.read<ChatProvider>().setDarkMode(isDark);
    }
  }

  void toggleTheme() async {
    final provider = context.read<ChatProvider>();
    provider.toggleDarkMode();
    final isDarkMode = provider.isDarkMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('darkMode', isDarkMode);
  }

  @override
  Widget build(BuildContext context) {
    return Selector<ChatProvider, bool>(
      selector: (_, provider) => provider.isDarkMode,
      builder: (context, isDarkMode, child) {
        return MaterialApp(
          title: 'Ollama Chat',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
          home: ChatScreen(
            toggleTheme: toggleTheme,
            isDarkMode: isDarkMode,
          ),
        );
      },
    );
  }
}
