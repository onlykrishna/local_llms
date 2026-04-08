import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:llamadart/llamadart.dart';
import '../../core/services/settings_service.dart';

/// On-device inference via llamadart (llama.cpp GGUF).
class OnDeviceInferenceService extends GetxService {
  final SettingsService _settings = Get.find<SettingsService>();
  
  LlamaBackend? _backend;
  int? _modelHandle;
  int? _contextHandle;
  bool _isInitialized = false;
  String? _initializedDomain;

  final RxBool isLoading = false.obs;
  final RxBool isModelReady = false.obs;

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
        print('>>> ONDEVICE: handle disposal error: $e');
      }
      _backend = null;
    }
    _isInitialized = false;
    isModelReady.value = false;
  }

  /// Validation: Check if the file starts with 'GGUF' and is large enough.
  Future<String?> validateModelFile(String path) async {
    final file = File(path);
    if (!file.existsSync()) return 'Model file not found';
    
    final size = await file.length();
    if (size < 50 * 1024 * 1024) { // Less than 50MB is likely a partial/corrupt download
       return 'Model file is too small (${(size / (1024 * 1024)).toStringAsFixed(1)} MB). Expected ~400-800 MB.';
    }

    try {
      final raf = await file.open();
      // Read first 4 bytes for magic 'GGUF'
      final header = await raf.read(4);
      await raf.close();
      
      if (header.length < 4 || 
          header[0] != 0x47 || header[1] != 0x47 || 
          header[2] != 0x55 || header[3] != 0x46) {
        return 'Invalid file format. This is not a valid GGUF model.';
      }
    } catch (e) {
      return 'Could not verify model header: $e';
    }
    return null;
  }

  /// Initialize model and context lazily or on domain switch.
  Future<bool> _ensureInitialized(String domainName) async {
    // If already initialized for this domain, we are good
    if (_isInitialized && 
        _initializedDomain == domainName && 
        _backend != null && 
        _modelHandle != null && 
        _contextHandle != null) {
      return true;
    }

    if (_isInitialized) {
      await _disposeHandles();
    }

    final modelPath = _settings.selectedModel.value;
    print('>>> ONDEVICE: model path = $modelPath');

    // Fast pre-flight validation
    final valErr = await validateModelFile(modelPath);
    if (valErr != null) {
      print('>>> ONDEVICE: validation failed: $valErr');
      return false;
    }

    isLoading.value = true;
    try {
      _backend = LlamaBackend();
      
      final mParams = ModelParams(
        contextSize: 512, 
        gpuLayers: 0, 
        numberOfThreads: Platform.numberOfProcessors,
        batchSize: 512, 
        preferredBackend: GpuBackend.cpu,
      );

      print('>>> ONDEVICE: loading model (300s timeout)...');
      _modelHandle = await _backend!.modelLoad(modelPath, mParams)
          .timeout(const Duration(seconds: 300), onTimeout: () {
            print('>>> ONDEVICE: modelLoad timed out!');
            throw TimeoutException('Model load took too long (300s)');
          });

      print('>>> ONDEVICE: creating context...');
      _contextHandle = await _backend!.contextCreate(_modelHandle!, mParams);

      _isInitialized = true;
      _initializedDomain = domainName;
      isModelReady.value = true;
      print('>>> ONDEVICE: initialized = $_isInitialized');
      return true;
    } catch (e) {
      print('>>> ONDEVICE: init error = $e');
      await _disposeHandles();
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  /// Streams response tokens from on-device llama.cpp.
  Stream<String> respond(String userMessage, String systemPrompt, String domainName) async* {
    print('>>> ONDEVICE: respond() called');
    
    // Check path before trying init
    final currentPath = _settings.selectedModel.value;
    final valErr = await validateModelFile(currentPath);
    if (valErr != null) {
      yield '⚠️ $valErr\n\n'
            'Please go to the "Model Setup" screen from the sidebar to download Llama 3.2 1B or select a valid GGUF file.';
      return;
    }

    // Move initialization BEFORE returning the generator stream to prevent race with ChatController timeout
    final isFirstLoad = !isModelReady.value;
    if (isFirstLoad) {
      yield '⏳ Loading on-device AI (first run: 60–180s on low-RAM devices)...';
    }

    // Do model load BEFORE any yield that could race with the caller's timeout
    final ok = await _ensureInitialized(domainName).timeout(
      const Duration(seconds: 300),
      onTimeout: () {
        debugPrint('[OnDevice] _ensureInitialized timed out after 300s');
        return false;
      },
    );

    if (!ok || _backend == null || _contextHandle == null || _modelHandle == null) {
      yield '⚠️ Failed to launch local model. Please ensure your device has enough free RAM and the file is valid.';
      return;
    }

    try {
      final messages = [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userMessage},
      ];

      String prompt;
      try {
        prompt = await _backend!.applyChatTemplate(_modelHandle!, messages);
      } catch (_) {
        prompt = '<|system|>\n$systemPrompt\n<|end|>\n'
                 '<|user|>\n$userMessage\n<|end|>\n'
                 '<|assistant|>\n';
      }

      final gParams = const GenerationParams(
        maxTokens: 512,
        temp: 0.2, // Reduced from 0.7 for factual precision
        topP: 0.4, // Targeted greedyish decoding
        penalty: 1.1,
        topK: 40,
      );

      print('>>> ONDEVICE: starting generation...');
      final stream = _backend!.generate(_contextHandle!, prompt, gParams);
      
      await for (final chunk in stream) {
        if (chunk.isNotEmpty) {
          yield utf8.decode(chunk);
        }
      }
    } catch (e) {
      print('>>> ONDEVICE: inference error: $e');
      yield '\n[Local AI Error: $e]';
    }
  }

  void cancelInference() {
    print('>>> ONDEVICE: generation cancelled');
    _backend?.cancelGeneration();
  }

  void notifyDomainSwitch() {
    print('>>> ONDEVICE: reset on domain switch');
    _disposeHandles(); 
  }
}
