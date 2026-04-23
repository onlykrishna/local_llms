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
import 'domain/services/factual_hardening_service.dart';
import 'domain/services/inference_router.dart';
import 'presentation/bindings/chat_binding.dart';
import 'presentation/pages/chat_page.dart';
import 'presentation/pages/settings_page.dart';
import 'presentation/widgets/app_drawer.dart';

import 'domain/entities/download_state.dart';
import 'domain/services/model_download_service.dart';
import 'presentation/controllers/model_manager_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // FEATURE 4: Lock orientation to Portrait only
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initial core storage (fast)
  try {
    await GetStorage.init();
    await Hive.initFlutter();
    Hive.registerAdapter(ChatMessageAdapter());
    Hive.registerAdapter(DownloadStateAdapter());
    
    await Hive.openBox<ChatMessage>(AppConstants.chatBoxName);
    await Hive.openBox<DownloadState>(AppConstants.downloadBoxName);
  } catch (e) {
    debugPrint('🚨 Storage Init Error: $e');
  }

  // Start service initialization
  await _initServices();

  runApp(const OfflineAIDemoApp());
}

Future<void> _initServices() async {
  try {
    // These can run in parallel
    await Future.wait([
      Get.putAsync(() => SettingsService().init()).timeout(const Duration(seconds: 15)),
      Get.putAsync(() => ModelDownloadService().init()).timeout(const Duration(seconds: 15)),
      Get.putAsync(() => FallbackDatasetService().init()).timeout(const Duration(seconds: 15)),
      Get.putAsync(() => DomainService().init()).timeout(const Duration(seconds: 15)),
    ]);

    // These depend on the ones above
    Get.put(FactualHardeningService());
    Get.put(OnDeviceInferenceService());
    await Get.putAsync(() => InferenceRouterService().init());
    Get.lazyPut(() => ModelManagerController());
    
    debugPrint('✅ All services initialized in background');
  } catch (e) {
    debugPrint('🚨 Background Service Init Error: $e');
  }
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
