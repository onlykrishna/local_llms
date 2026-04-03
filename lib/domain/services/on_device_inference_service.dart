import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:get/get.dart';
import 'package:llamadart/llamadart.dart';
import '../../core/services/settings_service.dart';

/// On-device inference via llamadart (llama.cpp GGUF).
/// Uses LlamaBackend directly as a senior implementation to avoid high-level engine issues.
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
        print('Error during handle disposal: $e');
      }
      _backend = null;
    }
    _isInitialized = false;
    isModelReady.value = false;
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

    // If domain changed or backend lost, re-initialize
    if (_isInitialized) {
      await _disposeHandles();
    }

    final modelPath = _settings.selectedModel.value;
    if (modelPath.isEmpty || !File(modelPath).existsSync()) {
      print('⚠️ Model file not found at: $modelPath');
      return false;
    }

    isLoading.value = true;
    try {
      _backend = LlamaBackend();
      
      final mParams = const ModelParams(
        contextSize: 2048,
        gpuLayers: 0, // CPU only for maximum compatibility
        preferredBackend: GpuBackend.cpu,
      );

      _modelHandle = await _backend!.modelLoad(modelPath, mParams);
      _contextHandle = await _backend!.contextCreate(_modelHandle!, mParams);

      _isInitialized = true;
      _initializedDomain = domainName;
      isModelReady.value = true;
      return true;
    } catch (e) {
      print('❌ OnDevice Inference Init Error: $e');
      await _disposeHandles();
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  /// Streams response tokens from on-device llama.cpp.
  Stream<String> respond(String userMessage, String systemPrompt, String domainName) async* {
    final ok = await _ensureInitialized(domainName);
    if (!ok || _backend == null || _contextHandle == null || _modelHandle == null) {
      yield '⚠️ Local model not found or failed to load. Please go to the Model Setup screen to download Llama 3.2 1B (~650 MB).';
      return;
    }

    try {
      // Build messages for template
      final messages = [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userMessage},
      ];

      String prompt;
      try {
        // Try native chat template if available in model metadata
        prompt = await _backend!.applyChatTemplate(_modelHandle!, messages);
      } catch (_) {
        // Fallback to Llama 3 manual format specified in Fix 3
        prompt = '<|system|>\n$systemPrompt\n<|end|>\n'
                 '<|user|>\n$userMessage\n<|end|>\n'
                 '<|assistant|>\n';
      }

      final gParams = const GenerationParams(
        maxTokens: 512,
        temp: 0.7,
        topP: 0.9,
        penalty: 1.1, // repeat penalty
        topK: 40,
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

  /// Support for cancellation as per Fix 3 point 7.
  void cancelInference() {
    _backend?.cancelGeneration();
  }

  /// Explicitly reset on domain switch as per Fix 3 point 8.
  void notifyDomainSwitch() {
    _disposeHandles(); 
  }
}
