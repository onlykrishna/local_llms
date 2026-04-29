import 'dart:io';
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
import 'domain/services/on_device_inference_service.dart';
import 'domain/services/inference_router.dart';
import 'presentation/bindings/chat_binding.dart';
import 'presentation/pages/chat_page.dart';
import 'presentation/pages/settings_page.dart';
import 'presentation/widgets/app_drawer.dart';

import 'domain/entities/download_state.dart';
import 'domain/services/model_download_service.dart';
import 'presentation/controllers/model_manager_controller.dart';
import 'core/embedding_service.dart';
import 'domain/document_ingestion_service.dart';
import 'domain/rag_retrieval_service.dart';
import 'domain/source_citation_service.dart';
import 'objectbox.g.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

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

  await _initServices();

  runApp(const OfflineAIDemoApp());
}

Future<void> _initServices() async {
  final overallSw = Stopwatch()..start();
  try {
    // 1. Core Services (Parallel)
    await Future.wait([
      Get.putAsync(() => SettingsService().init()),
      Get.putAsync(() => ModelDownloadService().init()),
      Get.putAsync(() => FallbackDatasetService().init()),
    ]).timeout(const Duration(seconds: 15));

    // 2. Heavy I/O & Model Services (Parallel)
    final docsDir = await getApplicationDocumentsDirectory();
    final embeddingService = EmbeddingService();
    
    Store? store;
    try {
      store = await openStore(directory: p.join(docsDir.path, "obx-rag"));
    } catch (e) {
      debugPrint('🚨 ObjectBox Index Mismatch (Branch Switch). Clearing DB: $e');
      final dbDir = Directory(p.join(docsDir.path, "obx-rag"));
      if (await dbDir.exists()) {
        await dbDir.delete(recursive: true);
      }
      store = await openStore(directory: p.join(docsDir.path, "obx-rag"));
    }

    final results = await Future.wait([
      Future.value(store),
      embeddingService.init(),
      Future.microtask(() => Get.put(OnDeviceInferenceService())),
      Future.microtask(() => Get.put(SourceCitationService())),
    ]);

    store = results[0] as Store;
    Get.put(store);
    Get.put(embeddingService);
    
    // 3. Dependent Services
    Get.put(DocumentIngestionService(store, embeddingService));
    Get.put(RagRetrievalService(store, embeddingService));

    // 4. Router & Controller
    await Get.putAsync(() => InferenceRouterService().init());
    Get.lazyPut(() => ModelManagerController());
    
    debugPrint('🚀 All services initialized in ${overallSw.elapsedMilliseconds}ms');
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
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/logo_icon.png', height: 24),
            const SizedBox(width: 10),
            const Text('Offline AI'),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
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
