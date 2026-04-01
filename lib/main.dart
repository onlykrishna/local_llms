import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'core/theme/app_theme.dart';
import 'presentation/bindings/chat_binding.dart';
import 'presentation/pages/chat_page.dart';
import 'presentation/pages/history_page.dart';
import 'presentation/pages/settings_page.dart';
import 'presentation/widgets/app_drawer.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize GetStorage for settings and Hive for local storage
  await GetStorage.init();
  await initHive();
  runApp(const OfflineAIDemoApp());
}

Future<void> initHive() async {
  // Register Hive adapters and open boxes
  // Assuming ChatMessageAdapter is generated
  // Hive.initFlutter();
  // Hive.registerAdapter(ChatMessageAdapter());
  // await Hive.openBox<ChatMessage>('chat_history');
}

class OfflineAIDemoApp extends StatelessWidget {
  const OfflineAIDemoApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Offline AI Demo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      initialBinding: ChatBinding(),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline AI Chat'),
        centerTitle: true,
      ),
      drawer: const AppDrawer(),
      body: const ChatPage(),
    );
  }
}
