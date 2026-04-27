import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:llamadart/llamadart.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/services/settings_service.dart';

/// Exception thrown when no model is installed but inference is requested.
class ModelNotDownloadedException implements Exception {
  final String message;
  ModelNotDownloadedException(this.message);
  @override
  String toString() => message;
}

/// On-device inference via llamadart (llama.cpp GGUF).
class OnDeviceInferenceService extends GetxService {
  final SettingsService _settings = Get.find<SettingsService>();
  
  LlamaBackend? _backend;
  int? _modelHandle;
  int? _contextHandle;
  bool _isInitialized = false;
  String? _initializedDomain;
  String? _initializedModelPath;

  final RxBool isLoading = false.obs;
  final RxBool isModelReady = false.obs;
  final RxString loadingStage = 'Ready'.obs;

  bool get isModelLoaded => _isInitialized && _modelHandle != null;

  @override
  void onInit() {
    super.onInit();
    Future.microtask(() => warmup());
  }

  @override
  void onClose() {
    _disposeHandles();
    super.onClose();
  }

  Future<void> _disposeHandles() async {
    if (_backend != null) {
      try {
        if (_contextHandle != null) {
          await _backend!.contextFree(_contextHandle!);
          _contextHandle = null;
        }
        if (_modelHandle != null) {
          await _backend!.modelFree(_modelHandle!);
          _modelHandle = null;
        }
        await _backend!.dispose();
      } catch (e) {
        debugPrint('>>> ONDEVICE: handle disposal error: $e');
      }
      _backend = null;
    }
    _isInitialized = false;
    isModelReady.value = false;
    _initializedModelPath = null;
  }

  /// Manually unload the model to free memory.
  Future<void> unloadModel() async {
    await _disposeHandles();
  }

  Future<bool>? _initFuture;

  /// Public method to pre-load the model (Warm Start)
  Future<bool> warmup() async {
    if (_initFuture != null) return await _initFuture!;
    final currentPath = _settings.selectedModel.value;
    if (currentPath.isEmpty) return false;
    return await _ensureInitialized(currentPath, 'general');
  }

  /// Initialize model and context for a specific GGUF file and domain.
  Future<bool> _ensureInitialized(String modelPath, String domainName) async {
    if (_initFuture != null) return await _initFuture!;

    // Only reload if the model file itself changed. Domain changes don't require handle disposal.
    if (_isInitialized && 
        _initializedModelPath == modelPath &&
        _backend != null) {
      return true;
    }

    _initFuture = _doInitialize(modelPath, domainName);
    try {
      return await _initFuture!;
    } finally {
      _initFuture = null;
    }
  }

  Future<bool> _doInitialize(String modelPath, String domainName) async {
    if (_isInitialized) {
      await _disposeHandles();
    }

    final valErr = await validateModelFile(modelPath);
    if (valErr != null) {
      debugPrint('>>> ONDEVICE: validation failed: $valErr');
      loadingStage.value = 'Error: $valErr';
      return false;
    }

    isLoading.value = true;
    loadingStage.value = 'Preparing engine...';
    final sw = Stopwatch()..start();
    try {
      _backend = LlamaBackend();
      
      bool isVeryLarge = modelPath.contains('1.5b') || modelPath.contains('3b') || 
                         modelPath.contains('4b') || modelPath.contains('7b') || 
                         modelPath.contains('8b') || modelPath.contains('12b') || 
                         modelPath.contains('27b') || modelPath.contains('e2b') || 
                         modelPath.contains('e4b') || modelPath.contains('phi-4-mini') || 
                         modelPath.contains('qwen');

      loadingStage.value = 'Loading model weights... (1.1GB)';
      
      // Optimization for budget Android (M12): 8 cores available, use 8 threads for all-core boost
      final mParams = ModelParams(
        gpuLayers: 0,
        contextSize: 2048, // Increase to 2048 for all models to prevent truncation
        numberOfThreads: 4, // 4 threads is optimal for iPhone A-series chips
        batchSize: 64,
      );

      _modelHandle = await _backend!.modelLoad(modelPath, mParams);
      
      loadingStage.value = 'Initializing context...';
      _contextHandle = await _backend!.contextCreate(_modelHandle!, mParams);
      
      _isInitialized = true;
      _initializedDomain = domainName;
      _initializedModelPath = modelPath;
      isModelReady.value = true;
      loadingStage.value = 'Ready';
      sw.stop();
      debugPrint('>>> ONDEVICE: Total initialization complete in ${sw.elapsedMilliseconds}ms.');
      return true;
    } catch (e, stack) {
      debugPrint('>>> ONDEVICE: Init error: $e\n$stack');
      loadingStage.value = 'Error: ${e.toString().split('\n').first}';
      await _disposeHandles();
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  /// Streams response tokens from on-device llama.cpp.
  Stream<String> respond(String userMessage, String systemPrompt, String domainName) async* {
    final currentPath = _settings.selectedModel.value;
    if (currentPath.isEmpty) {
      throw ModelNotDownloadedException("No on-device model installed. Go to Settings → Manage Models to download one.");
    }

    // v3.1: Use the system prompt as-is — no extra append to preserve context window for 3B models
    final hardenedSystemPrompt = systemPrompt;

    final isFirstLoadForThisModel = !isModelReady.value || _initializedModelPath != currentPath;

    try {
      final ok = await _ensureInitialized(currentPath, domainName).timeout(
        const Duration(seconds: 300),
      );

      if (!ok) throw Exception("Failed to initialize model handles.");

    } catch (e) {
      final pathLower = currentPath.toLowerCase();
      final isLargeModel = pathLower.contains('3b') || pathLower.contains('4b') ||
          pathLower.contains('7b') || pathLower.contains('8b') ||
          pathLower.contains('12b') || pathLower.contains('13b') || pathLower.contains('27b') ||
          pathLower.contains('e2b') || pathLower.contains('e4b');
      
      if (Platform.isIOS && isLargeModel) {
        final fileName = currentPath.split('/').last;
        yield '⚠️ iOS RAM Limit Reached\n\n'
            'The model "$fileName" is too large for the memory budget '
            'iOS allows for individual apps on this device.\n\n'
            'Error detail: $e\n\n'
            'Fix: Go to Settings → Manage Models → download a 1B model (like Gemma 3 1B) '
            'which runs reliably on all iPhones.\n--- END ---';
      } else {
        yield '⚠️ Failed to launch local engine.\n\n'
            'Error detail: $e\n\n'
            'Possible causes:\n'
            '1. iOS denied the RAM request (close other apps and retry)\n'
            '2. Model file may be corrupted (re-download in Settings)\n'
            '3. Device storage is full\n\n'
            'Go to Settings → Manage Models to verify or re-download.\n--- END ---';
      }
      return;
    }

    try {
      // RESET context by freeing and recreating (fast way to clear state if resetContext is missing)
      if (_contextHandle != null) {
        await _backend!.contextFree(_contextHandle!);
      }
      
      final pathLower = _initializedModelPath?.toLowerCase() ?? '';
      bool isVeryLarge = pathLower.contains('1.5b') || pathLower.contains('3b') || 
                         pathLower.contains('qwen') || pathLower.contains('gemma');

      final mParams = ModelParams(
        contextSize: 2048, // Match initialization context size
        numberOfThreads: 4,
        batchSize: 64,
      );
      _contextHandle = await _backend!.contextCreate(_modelHandle!, mParams);

      final messages = [
        {'role': 'system', 'content': hardenedSystemPrompt},
        {'role': 'user', 'content': userMessage},
      ];

      String prompt;
      try {
        prompt = await _backend!.applyChatTemplate(_modelHandle!, messages);
      } catch (_) {
        prompt = '<|im_start|>system\n$hardenedSystemPrompt<|im_end|>\n<|im_start|>user\n$userMessage<|im_end|>\n<|im_start|>assistant\n';
      }

      final gParams = GenerationParams(
        maxTokens: 300, // Increase from 200 to allow full answers
        temp: 0.1,
        topP: 0.85,
        topK: 20,
        penalty: 1.05,
        stopSequences: ['<|im_end|>', '<|endoftext|>'],
      );

      await for (final chunk in _backend!.generate(_contextHandle!, prompt, gParams)) {
        if (chunk.isNotEmpty) {
          yield utf8.decode(chunk);
        }
      }
    } catch (e) {
      yield '\n[Local AI Error: $e]';
    }
  }

  Future<String?> validateModelFile(String path) async {
    final file = File(path);
    if (!file.existsSync()) return 'Model file not found';
    final size = await file.length();
    if (size < 50 * 1024 * 1024) return 'File is too small/corrupt.';
    
    try {
      final raf = await file.open();
      final header = await raf.read(4);
      await raf.close();
      if (header.length < 4 || 
          header[0] != 0x47 || header[1] != 0x47 || 
          header[2] != 0x55 || header[3] != 0x46) {
        return 'Invalid GGUF format';
      }
    } catch (_) {
      return 'Header verification failed';
    }
    return null;
  }

  void cancelInference() {
    _backend?.cancelGeneration();
  }

  Future<void> clearModelCache() async {
    try {
      _disposeHandles();
      final dir = await getApplicationDocumentsDirectory();
      final modelDir = Directory('${dir.path}/models');
      if (await modelDir.exists()) {
        await modelDir.delete(recursive: true);
        await modelDir.create();
      }
    } catch (e) {
      debugPrint('Error clearing model cache: $e');
    }
  }

  void notifyDomainSwitch() {
    // No longer disposing handles on domain switch to keep model warm.
    // _disposeHandles(); 
    _initializedDomain = null; 
  }
}
