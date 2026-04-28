import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:llamadart/llamadart.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/services/settings_service.dart';
import 'inference_isolate.dart';

/// Exception thrown when no model is installed but inference is requested.
class ModelNotDownloadedException implements Exception {
  final String message;
  ModelNotDownloadedException(this.message);
  @override
  String toString() => message;
}

/// On-device inference via llamadart (llama.cpp GGUF) with Isolate support.
class OnDeviceInferenceService extends GetxService {
  final SettingsService _settings = Get.find<SettingsService>();
  
  Isolate? _isolate;
  SendPort? _isolateSendPort;
  ReceivePort? _mainReceivePort;
  final Completer<void> _isolateReady = Completer<void>();

  bool _isInitialized = false;
  String? _initializedModelPath;

  final RxBool isLoading = false.obs;
  final RxBool isModelReady = false.obs;
  final RxString loadingStage = 'Ready'.obs;

  bool get isModelLoaded => _isInitialized;

  @override
  void onInit() {
    super.onInit();
    _startIsolate();
    Future.microtask(() => warmup());
  }

  @override
  void onClose() {
    _disposeIsolate();
    super.onClose();
  }

  Future<void> _startIsolate() async {
    _mainReceivePort = ReceivePort();
    _isolate = await Isolate.spawn(inferenceIsolateEntryPoint, _mainReceivePort!.sendPort);
    
    _mainReceivePort!.listen((message) {
      if (message is SendPort) {
        _isolateSendPort = message;
        _isolateReady.complete();
      }
    });
  }

  void _disposeIsolate() {
    _isolateSendPort?.send(IsolateRequest('dispose', null, ReceivePort().sendPort));
    _isolate?.kill(priority: Isolate.immediate);
    _mainReceivePort?.close();
  }

  Future<void> _disposeHandles() async {
    await _isolateReady.future;
    _isolateSendPort?.send(IsolateRequest('dispose', null, ReceivePort().sendPort));
    _isInitialized = false;
    isModelReady.value = false;
    _initializedModelPath = null;
  }

  Future<void> unloadModel() async {
    await _disposeHandles();
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
    if (_isInitialized && _initializedModelPath == modelPath) return true;

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
    await _isolateReady.future;

    try {
      final responsePort = ReceivePort();
      final mParams = ModelParams(
        gpuLayers: 0,
        contextSize: 2048,
        numberOfThreads: 3, // Reduced to 3 to keep UI responsive
        batchSize: 64,
      );

      _isolateSendPort!.send(IsolateRequest('init', {
        'path': modelPath,
        'params': mParams,
      }, responsePort.sendPort));

      final response = await responsePort.first as IsolateResponse;
      responsePort.close();

      if (response.isError) {
        loadingStage.value = 'Error: ${response.data}';
        return false;
      }

      _isInitialized = true;
      _initializedModelPath = modelPath;
      isModelReady.value = true;
      loadingStage.value = 'Ready';
      return true;
    } catch (e) {
      loadingStage.value = 'Error: $e';
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  Stream<String> respond(String userMessage, String systemPrompt, String domainName) async* {
    final currentPath = _settings.selectedModel.value;
    if (currentPath.isEmpty) {
      throw ModelNotDownloadedException("No model installed.");
    }

    try {
      final ok = await _ensureInitialized(currentPath).timeout(const Duration(seconds: 300));
      if (!ok) throw Exception("Init failed.");
    } catch (e) {
      yield '⚠️ Failed to launch local engine: $e';
      return;
    }

    final messages = [
      {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': userMessage},
    ];

    // Applying the prefix "Based on the provided text, " directly into the prompt
    // to steer the 1B model towards grounding.
    final assistantPrefix = 'Based on the provided text, ';
    
    // We construct the prompt manually to ensure the prefix is attached to the assistant role
    final prompt = '<|im_start|>system\n$systemPrompt<|im_end|>\n<|im_start|>user\n$userMessage<|im_end|>\n<|im_start|>assistant\n$assistantPrefix';

    final gParams = GenerationParams(
      maxTokens: 300, 
      temp: 0.0,
      topP: 0.9,
      topK: 40,
      penalty: 1.1,
      stopSequences: ['<|im_end|>', '<|endoftext|>'],
    );

    final responsePort = ReceivePort();
    _isolateSendPort!.send(IsolateRequest('generate', {
      'prompt': prompt,
      'params': gParams,
    }, responsePort.sendPort));

    await for (final response in responsePort.map((r) => r as IsolateResponse)) {
      if (response.isError) {
        yield '\n[Local AI Error: ${response.data}]';
        break;
      }
      if (response.isDone) break;
      if (response.data != null) {
        yield response.data as String;
      }
    }
    responsePort.close();
  }

  Future<String?> validateModelFile(String path) async {
    final file = File(path);
    if (!file.existsSync()) return 'Model file not found';
    final size = await file.length();
    if (size < 50 * 1024 * 1024) return 'File is too small/corrupt.';
    return null;
  }

  void cancelInference() {
    _isolateSendPort?.send(IsolateRequest('cancel', null, ReceivePort().sendPort));
  }

  void notifyDomainSwitch() {
    // Keep warm
  }

  Future<void> clearModelCache() async {
    try {
      _disposeIsolate();
      _isInitialized = false;
      isModelReady.value = false;
      
      final dir = await getApplicationSupportDirectory(); // Using support dir as per common patterns
      final modelDir = Directory('${dir.path}/models');
      if (await modelDir.exists()) {
        await modelDir.delete(recursive: true);
      }
      
      // Restart isolate for future use
      await _startIsolate();
    } catch (e) {
      debugPrint('Error clearing model cache: $e');
    }
  }
}
