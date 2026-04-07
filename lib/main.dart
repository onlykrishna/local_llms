import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_constants.dart';
import 'core/services/settings_service.dart';
import 'core/services/fallback_dataset_service.dart';
import 'domain/entities/chat_message.dart';
import 'domain/services/domain_service.dart';
import 'domain/services/on_device_inference_service.dart';
import 'domain/services/inference_router.dart';
import 'presentation/bindings/chat_binding.dart';
import 'presentation/pages/chat_page.dart';
import 'presentation/pages/settings_page.dart';
import 'presentation/widgets/app_drawer.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // FEATURE 4: Lock orientation to Portrait only
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  try {
    await GetStorage.init();
    await Hive.initFlutter();
    Hive.registerAdapter(ChatMessageAdapter());
    await Hive.openBox<ChatMessage>(AppConstants.chatBoxName);

    // Register all services (order matters for dependencies)
    await Get.putAsync(() => SettingsService().init());
    await Get.putAsync(() => FallbackDatasetService().init());
    await Get.putAsync(() => DomainService().init());
    Get.put(OnDeviceInferenceService());
    await Get.putAsync(() => InferenceRouterService().init());
  } catch (e) {
    debugPrint('🚨 Startup Error: $e');
  }

  runApp(const OfflineAIDemoApp());
}

class OfflineAIDemoApp extends StatelessWidget {
  const OfflineAIDemoApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Offline AI',
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
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Offline AI'),
        backgroundColor: Colors.transparent,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            onPressed: () => Get.to(() => const SettingsPage()),
          ),
        ],
      ),
      drawer: const AppDrawer(),
      body: const ChatPage(),
    );
  }
}
