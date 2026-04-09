import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:llamadart/llamadart.dart';
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

  /// Initialize model and context for a specific GGUF file and domain.
  Future<bool> _ensureInitialized(String modelPath, String domainName) async {
    if (_isInitialized && 
        _initializedDomain == domainName && 
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
      
      // Dynamically scale context to fit 'Fact Blocks' vs RAM limits
      bool isVeryLarge = modelPath.contains('3b') || modelPath.contains('4b') || 
                         modelPath.contains('12b') || modelPath.contains('27b');
      
      final mParams = ModelParams(
        contextSize: isVeryLarge ? 512 : 1024, 
        gpuLayers: 0, 
        numberOfThreads: 2,
        batchSize: 512, 
        preferredBackend: GpuBackend.cpu,
      );

      debugPrint('>>> ONDEVICE: loading model: $modelPath (Large=$isVeryLarge)');
      _modelHandle = await _backend!.modelLoad(modelPath, mParams)
          .timeout(const Duration(seconds: 300));

      _contextHandle = await _backend!.contextCreate(_modelHandle!, mParams);

      _isInitialized = true;
      _initializedDomain = domainName;
      _initializedModelPath = modelPath;
      isModelReady.value = true;
      return true;
    } catch (e) {
      debugPrint('>>> ONDEVICE: init error = $e');
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
      // v3.1: Silent init — model path not shown to user
    }

    try {
      final ok = await _ensureInitialized(currentPath, domainName).timeout(
        const Duration(seconds: 300),
      );

      if (!ok) {
        final pathLower = currentPath.toLowerCase();
        final isLargeModel = pathLower.contains('3b') || pathLower.contains('4b') ||
            pathLower.contains('7b') || pathLower.contains('8b') ||
            pathLower.contains('12b') || pathLower.contains('13b') || pathLower.contains('27b');
        if (Platform.isIOS && isLargeModel) {
          yield '⚠️ iOS RAM Limit Reached\n\n'
              'The LLaMA 3.2 3B model (~2GB) exceeds the memory budget '
              'iOS allows for individual apps on this device.\n\n'
              'Fix: Go to Settings → Manage Models → download the 1B model (~600MB) '
              'which runs reliably on all iPhones.\n--- END ---';
        } else {
          yield '⚠️ Failed to launch local engine.\n\n'
              'Possible causes:\n'
              '1. iOS denied the RAM request (close other apps and retry)\n'
              '2. Model file may be corrupted (re-download in Settings)\n'
              '3. Device storage is full\n\n'
              'Go to Settings → Manage Models to verify or re-download.\n--- END ---';
        }
        return;
      }
    } catch (e) {
      yield '❌ Neural Core Error: $e';
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
        // v3.1: Clean fallback — no raw ChatML tokens, plain-text format only
        prompt = 'SYSTEM:\n$hardenedSystemPrompt\n\nUSER:\n$userMessage\n\nASSISTANT:';
      }

      final gParams = const GenerationParams(
        maxTokens: 512,
        temp: 0.0, // Force greedy search for 1B/3B factual reliability
        topP: 0.0,
        penalty: 1.1,
        topK: 1,
      );

      final stream = _backend!.generate(_contextHandle!, prompt, gParams);
      
      await for (final chunk in stream) {
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

  void notifyDomainSwitch() {
    _disposeHandles(); 
  }
}
