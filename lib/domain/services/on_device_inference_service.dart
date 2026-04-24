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

  bool get isModelLoaded => _isInitialized && _modelHandle != null;

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

  /// Public method to pre-load the model (Warm Start)
  Future<bool> warmup() async {
    final currentPath = _settings.selectedModel.value;
    if (currentPath.isEmpty) return false;
    return await _ensureInitialized(currentPath, 'general');
  }

  /// Initialize model and context for a specific GGUF file and domain.
  Future<bool> _ensureInitialized(String modelPath, String domainName) async {
    // Only reload if the model file itself changed. Domain changes don't require handle disposal.
    if (_isInitialized && 
        _initializedModelPath == modelPath &&
        _backend != null) {
      return true;
    }

    if (_isInitialized) {
      await _disposeHandles();
    }

    final valErr = await validateModelFile(modelPath);
    if (valErr != null) {
      debugPrint('>>> ONDEVICE: validation failed: $valErr');
      return false;
    }

    isLoading.value = true;
    try {
      _backend = LlamaBackend();
      
      bool isVeryLarge = modelPath.contains('3b') || modelPath.contains('4b') || 
                         modelPath.contains('7b') || modelPath.contains('8b') ||
                         modelPath.contains('12b') || modelPath.contains('27b') ||
                         modelPath.contains('e2b') || modelPath.contains('e4b') ||
                         modelPath.contains('phi-4-mini') || modelPath.contains('qwen2.5-3b');

      // v3.3: Increased context size to 4096 for RAG support on 1B models, 2048 for 3B+
      final mParams = ModelParams(
        contextSize: isVeryLarge ? 2048 : 4096, 
        gpuLayers: Platform.isIOS ? 99 : 0, 
        numberOfThreads: 4, 
        batchSize: 512, 
        preferredBackend: GpuBackend.auto,
      );

      debugPrint('>>> ONDEVICE: Loading model: $modelPath (Large=$isVeryLarge)');
      _modelHandle = await _backend!.modelLoad(modelPath, mParams)
          .timeout(const Duration(seconds: 300));

      debugPrint('>>> ONDEVICE: Creating context...');
      _contextHandle = await _backend!.contextCreate(_modelHandle!, mParams);

      _isInitialized = true;
      _initializedDomain = domainName;
      _initializedModelPath = modelPath;
      isModelReady.value = true;
      debugPrint('>>> ONDEVICE: Initialization complete.');
      return true;
    } catch (e, stack) {
      debugPrint('>>> ONDEVICE: Init error: $e\n$stack');
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
    if (isFirstLoadForThisModel) {
      yield '🔄 Initializing local engine...\n(This can take 10-30s for large models)';
    }

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
      final messages = [
        {'role': 'system', 'content': hardenedSystemPrompt},
        {'role': 'user', 'content': userMessage},
      ];

      String prompt;
      try {
        prompt = await _backend!.applyChatTemplate(_modelHandle!, messages);
      } catch (_) {
        // Fallbacks
        final pathLower = currentPath.toLowerCase();
        if (pathLower.contains('qwen')) {
          prompt = '<|im_start|>system\n$hardenedSystemPrompt<|im_end|>\n<|im_start|>user\n$userMessage<|im_end|>\n<|im_start|>assistant\n';
        } else if (pathLower.contains('gemma')) {
          prompt = '<start_of_turn>user\n$userMessage<end_of_turn>\n<start_of_turn>model\n';
        } else if (pathLower.contains('llama-3') || pathLower.contains('llama3')) {
          prompt = '<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n$hardenedSystemPrompt<|eot_id|><|start_header_id|>user<|end_header_id|>\n\n$userMessage<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n';
        } else {
          prompt = '### System:\n$hardenedSystemPrompt\n\n### User:\n$userMessage\n\n### Assistant:\n';
        }
      }

      debugPrint('>>> ONDEVICE: Starting generation with prompt length: ${prompt.length}');

      final gParams = const GenerationParams(
        maxTokens: 256,
        temp: 0.1, // Slight temp for less looping but still factual
        topP: 0.9,
        penalty: 1.1,
        topK: 40,
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
