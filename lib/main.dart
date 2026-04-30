import 'dart:async';
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

import 'domain/kb_embedding_service.dart';
import 'data/document_chunk.dart';

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
    
    try {
      await Hive.openBox<ChatMessage>(AppConstants.chatBoxName);
    } catch (e) {
      debugPrint('🚨 Chat box corrupt, clearing: $e');
      await Hive.deleteBoxFromDisk(AppConstants.chatBoxName);
      await Hive.openBox<ChatMessage>(AppConstants.chatBoxName);
    }
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

    // 2. Heavy I/O - ObjectBox MUST be first
    final docsDir = await getApplicationDocumentsDirectory();
    final store = await openStore(directory: p.join(docsDir.path, "obx-rag"));
    Get.put(store);
    debugPrint('[STARTUP] ✅ ObjectBox ready');

    // 3. Embedding model MUST be fully loaded before KB embedding
    final embeddingService = EmbeddingService();
    await embeddingService.init();
    Get.put(embeddingService);
    debugPrint('[STARTUP] ✅ EmbeddingService ready');
    
    // 4. Heavy LLM & Utility Services
    Get.put(OnDeviceInferenceService());
    Get.put(SourceCitationService());
    Get.put(DocumentIngestionService(store, embeddingService));
    Get.put(RagRetrievalService(store, embeddingService));
    
    // 5. KB Embedding Service — Sequential (Safe Option)
    final kbService = KbEmbeddingService(embeddingService, store.box<DocumentChunk>());
    Get.put(kbService);
    await kbService.initializeKb(); // Wait for KB to be ready
    debugPrint('[STARTUP] ✅ KB embedding complete');

    // 6. Router & Controller
    await Get.putAsync(() => InferenceRouterService().init());
    Get.lazyPut(() => ModelManagerController());
    
    // 7. Warm-start LLM in background (non-blocking)
    unawaited(Get.find<OnDeviceInferenceService>().warmup()); // Using warmup() as it matches existing code
    debugPrint('[STARTUP] ✅ LLM warm start triggered');
    
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
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      behavior: HitTestBehavior.translucent,
      child: Scaffold(
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
      ),
    );
  }
}
