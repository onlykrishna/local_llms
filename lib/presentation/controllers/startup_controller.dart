import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/fallback_dataset_service.dart';
import '../../domain/services/on_device_inference_service.dart';
import '../../domain/services/inference_router.dart';
import '../../domain/services/model_download_service.dart';
import '../../core/embedding_service.dart';
import '../../domain/document_ingestion_service.dart';
import '../../domain/rag_retrieval_service.dart';
import '../../domain/source_citation_service.dart';
import '../../core/services/bundled_pdf_service.dart';
import '../../domain/kb_embedding_service.dart';
import '../../presentation/controllers/model_manager_controller.dart';
import '../../presentation/bindings/chat_binding.dart';
import '../../presentation/pages/chat_page.dart';
import '../../objectbox.g.dart';
import '../../data/document_chunk.dart';
import '../../core/services/log_service.dart';

class StartupController extends GetxController {
  final RxList<String> logs = <String>[].obs;
  final RxDouble progress = 0.0.obs;
  final RxString currentTask = 'Initializing system...'.obs;
  StreamSubscription? _logSubscription;

  @override
  void onInit() {
    super.onInit();
    
    // Start listening to logs immediately
    _logSubscription = Get.find<LogService>().logStream.listen((msg) {
      addLog(msg);
    });

    Future.delayed(const Duration(milliseconds: 500), () {
      _performSystemStartup();
    });
  }

  @override
  void onClose() {
    _logSubscription?.cancel();
    super.onClose();
  }

  void addLog(String message) {
    // Basic filtering to keep UI clean but informative
    if (message.startsWith('I/flutter')) {
      message = message.replaceFirst('I/flutter', '').trim();
      if (message.startsWith('(')) {
        message = message.substring(message.indexOf(')') + 1).trim();
        if (message.startsWith(':')) message = message.substring(1).trim();
      }
    }

    logs.add(message);
    if (logs.length > 50) logs.removeAt(0);
    
    // Update high-level task description based on log patterns
    if (message.contains('[STARTUP]')) currentTask.value = 'Core Services Ready';
    if (message.contains('[INGEST]')) currentTask.value = 'Processing PDF Documents...';
    if (message.contains('[BUNDLED]')) currentTask.value = 'Indexing Local Documents...';
    if (message.contains('[KB_EMBED]')) currentTask.value = 'Optimizing Knowledge Base...';
    if (message.contains('All services initialized')) {
      currentTask.value = 'System Ready';
      progress.value = 1.0;
    }
  }

  void setProgress(double val) {
    progress.value = val;
  }

  Future<void> _performSystemStartup() async {
    final overallSw = Stopwatch()..start();
    final logService = Get.find<LogService>();
    
    void log(String msg, {double? progress}) {
      logService.log(msg);
      if (progress != null) setProgress(progress);
    }

    try {
      log('Initializing core settings...', progress: 0.1);
      await Future.wait([
        Get.putAsync(() => SettingsService().init()),
        Get.putAsync(() => ModelDownloadService().init()),
        Get.putAsync(() => FallbackDatasetService().init()),
      ]).timeout(const Duration(seconds: 15));
      log('[STARTUP] ✅ Core services ready', progress: 0.2);

      log('Opening vector database...', progress: 0.3);
      final docsDir = await getApplicationDocumentsDirectory();
      final store = await openStore(directory: p.join(docsDir.path, "obx-rag"));
      Get.put(store);
      log('[STARTUP] ✅ ObjectBox ready', progress: 0.4);

      log('Loading neural embedding model...', progress: 0.5);
      final embeddingService = EmbeddingService();
      await embeddingService.init();
      Get.put(embeddingService);
      log('[STARTUP] ✅ EmbeddingService ready', progress: 0.6);
      
      log('Configuring AI inference engine...', progress: 0.7);
      Get.put(OnDeviceInferenceService());
      Get.put(SourceCitationService());
      Get.put(DocumentIngestionService(store, embeddingService));
      Get.put(RagRetrievalService(store, embeddingService));
      
      log('Indexing bundled documents...', progress: 0.8);
      final bundledPdfService = Get.put(BundledPdfService());
      await bundledPdfService.init(); 
      
      log('Optimizing RAG retrieval...', progress: 0.9);
      final kbService = KbEmbeddingService(embeddingService, store.box<DocumentChunk>());
      Get.put(kbService);
      await kbService.initializeKb();
      log('[STARTUP] ✅ KB embedding complete');

      await Get.putAsync(() => InferenceRouterService().init());
      Get.lazyPut(() => ModelManagerController());
      
      unawaited(Get.find<OnDeviceInferenceService>().warmup());
      log('[STARTUP] ✅ LLM warm start triggered');
      
      log('🚀 All services initialized in ${overallSw.elapsedMilliseconds}ms', progress: 1.0);
      
      await Future.delayed(const Duration(milliseconds: 1200));
      Get.offAllNamed('/home');
    } catch (e) {
      log('🚨 Critical Initialization Error: $e');
    }
  }
}
