import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_constants.dart';
import 'presentation/bindings/chat_binding.dart';
import 'presentation/pages/chat_page.dart';
import 'presentation/pages/settings_page.dart';
import 'presentation/widgets/app_drawer.dart';
import 'domain/entities/chat_message.dart';
import 'core/services/settings_service.dart';
import 'core/services/fallback_dataset_service.dart';
import 'core/services/hardware_inference_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize FlutterGemma Engine
  await FlutterGemma.initialize();
  
  // Initialize GetStorage for settings
  await GetStorage.init();
  
  // Initialize Core Services with dependency injection
  await Get.putAsync(() => SettingsService().init());
  await Get.putAsync(() => FallbackDatasetService().init());
  await Get.putAsync(() => HardwareInferenceService().init());

  // Initialize Hive for local storage
  await Hive.initFlutter();
  Hive.registerAdapter(ChatMessageAdapter());
  await Hive.openBox<ChatMessage>(AppConstants.chatBoxName);
  
  runApp(const OfflineAIDemoApp());
}

Future<void> initHive() async {
  // Already moved to main
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
