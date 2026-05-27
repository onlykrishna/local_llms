import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../core/services/settings_service.dart';
import '../../core/services/log_service.dart';
import 'inference_backend.dart';
import 'inference_isolate.dart';

/// Exception thrown when no model is installed but inference is requested.
class ModelNotDownloadedException implements Exception {
  final String message;
  ModelNotDownloadedException(this.message);
  @override
  String toString() => message;
}

/// On-device inference service that decouples the UI/Domain from the specific backend.
class OnDeviceInferenceService extends GetxService {
  final InferenceBackend _backend;
  final SettingsService _settings = Get.find<SettingsService>();

  bool _isShuttingDown = false;
  String? _initializedModelPath;
  String? _dbPath;

  final RxBool isLoading = false.obs;
  final RxBool isModelReady = false.obs;
  final RxString loadingStage = 'Ready'.obs;

  OnDeviceInferenceService(this._backend);

  bool get isModelLoaded => _backend.isReady;

  @override
  void onInit() {
    super.onInit();
    _initPaths();
    Future.microtask(() => warmup());
  }

  Future<void> _initPaths() async {
    final docsDir = await getApplicationDocumentsDirectory();
    _dbPath = p.join(docsDir.path, "obx-rag");
  }

  @override
  Future<void> onClose() async {
    if (_isShuttingDown) return;
    _isShuttingDown = true;
    
    LogService.to.log('[Inference] Starting graceful shutdown...');
    await _backend.dispose();
    super.onClose();
  }

  Future<void> unloadModel() async {
    await _backend.dispose();
    isModelReady.value = false;
    _initializedModelPath = null;
  }

  Future<bool>? _initFuture;

  Future<bool> warmup() async {
    if (_initFuture != null) return await _initFuture!;
    final currentPath = _settings.selectedModel.value;
    if (currentPath.isEmpty) return false;
    return await _ensureInitialized(currentPath);
  }

  Future<bool> _ensureInitialized(String modelPath) async {
    if (_initFuture != null) return await _initFuture!;
    if (_backend.isReady && _initializedModelPath == modelPath) return true;

    _initFuture = _doInitialize(modelPath);
    try {
      return await _initFuture!;
    } finally {
      _initFuture = null;
    }
  }

  Future<bool> _doInitialize(String modelPath) async {
    final valErr = await validateModelFile(modelPath);
    if (valErr != null) {
      loadingStage.value = 'Error: $valErr';
      return false;
    }

    isLoading.value = true;
    loadingStage.value = 'Loading model weights...';

    try {
      final config = InferenceConfig(
        gpuLayers: 99,
        contextSize: 2048,
        numberOfThreads: _optimalThreadCount(),
        batchSize: 512,
      );

      await _backend.loadModel(modelPath, config, dbPath: _dbPath);

      _initializedModelPath = modelPath;
      isModelReady.value = true;
      loadingStage.value = 'Ready';
      return true;
    } catch (e) {
      LogService.to.log('[Inference] Load Error: $e');
      loadingStage.value = 'Load Failed';
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  /// Optimized RAG-aware inference stream.
  Stream<String> respondWithIds(
    String userMessage,
    ChunkIdResult chunkIdResult,
    String domainName,
  ) async* {
    if (_isShuttingDown) {
      yield '⚠️ Service is shutting down...';
      return;
    }
    final currentPath = _settings.selectedModel.value;
    if (currentPath.isEmpty) {
      throw ModelNotDownloadedException("No model installed.");
    }

    try {
      final ok = await _ensureInitialized(currentPath)
          .timeout(const Duration(seconds: 300));
      if (!ok) throw Exception("Init failed.");
    } catch (e) {
      yield '⚠️ Failed to launch local engine: $e';
      return;
    }

    yield* _backend.generate('', data: {
      'query': userMessage,
      'chunkIdResult': chunkIdResult,
    });
  }

  /// Stream on-device inference tokens. (Legacy/Fallback)
  Stream<String> respond(
      String userMessage, String fullPrompt, String domainName) async* {
    if (_isShuttingDown) {
      yield '⚠️ Service is shutting down...';
      return;
    }
    final currentPath = _settings.selectedModel.value;
    if (currentPath.isEmpty) {
      throw ModelNotDownloadedException("No model installed.");
    }

    try {
      final ok = await _ensureInitialized(currentPath)
          .timeout(const Duration(seconds: 300));
      if (!ok) throw Exception("Init failed.");
    } catch (e) {
      yield '⚠️ Failed to launch local engine: $e';
      return;
    }

    yield* _backend.generate(fullPrompt);
  }

  Future<void> cancelInference() async {
    await _backend.cancel();
  }

  int _optimalThreadCount() {
    if (Platform.isIOS) return 3;
    if (Platform.isAndroid) return 4;
    return 4;
  }

  Future<String?> validateModelFile(String path) async {
    final file = File(path);
    if (!await file.exists()) return "File not found at $path";
    final size = await file.length();
    if (size < 100 * 1024 * 1024) return "File too small to be a valid model";
    return null;
  }

  static String sanitizeResponse(String raw) {
    return raw
        .replaceAll(RegExp(r'<\|.*?\|>'), '')
        .replaceAll(RegExp(r'\(Fact \d+\)'), '')
        .trim();
  }

  Future<void> clearModelCache() async {
    await unloadModel();
    _initializedModelPath = null;
    isModelReady.value = false;
  }
}
