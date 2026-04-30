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
    _isolate = await Isolate.spawn(
        inferenceIsolateEntryPoint, _mainReceivePort!.sendPort);

    _mainReceivePort!.listen((message) {
      if (message is SendPort) {
        _isolateSendPort = message;
        _isolateReady.complete();
      }
    });
  }

  void _disposeIsolate() {
    _isolateSendPort
        ?.send(IsolateRequest('dispose', null, ReceivePort().sendPort));
    _isolate?.kill(priority: Isolate.immediate);
    _mainReceivePort?.close();
  }

  Future<void> _disposeHandles() async {
    await _isolateReady.future;
    _isolateSendPort
        ?.send(IsolateRequest('dispose', null, ReceivePort().sendPort));
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
        numberOfThreads: 3,
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

  /// Stream on-device inference tokens.
  /// [fullPrompt] is the already-formatted Llama 3 prompt string built by InferenceRouter.
  Stream<String> respond(
      String userMessage, String fullPrompt, String domainName) async* {
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

    // ── Inference parameters tuned to prevent repetition loops ──────────────
    final gParams = GenerationParams(
      maxTokens: 256,
      temp: 0.15,       // Non-zero prevents deterministic loops
      topP: 0.85,
      topK: 30,
      penalty: 1.3,     // Aggressive repetition penalty
      stopSequences: [
        '<|eot_id|>',
        '<|end_of_text|>',
        '<|im_end|>',
        '<|endoftext|>',
        '\n\nQuestion:',
        '\n\nQ:',
        '\n\nContext:',
      ],
    );

    debugPrint('[LLM] Sending prompt (${fullPrompt.length} chars):\n'
        '--- PROMPT START ---\n$fullPrompt\n--- PROMPT END ---');

    final responsePort = ReceivePort();
    _isolateSendPort!.send(IsolateRequest('generate', {
      'prompt': fullPrompt,
      'params': gParams,
    }, responsePort.sendPort));

    String accumulatedRaw = '';

    await for (final response
        in responsePort.map((r) => r as IsolateResponse)) {
      if (response.isError) {
        yield '\n[Local AI Error: ${response.data}]';
        break;
      }
      if (response.isDone) break;
      if (response.data != null) {
        accumulatedRaw += response.data as String;
        yield response.data as String;
      }
    }
    responsePort.close();
  }

  // ── Response Sanitizer ─────────────────────────────────────────────────────
  /// Cleans the raw LLM output to remove loops, stop token leakage, and
  /// duplicate lines. Call this AFTER streaming is complete.
  static String sanitizeResponse(String raw) {
    // 1. Strip leading "Based on the provided text," prefix if present
    raw = raw.replaceFirst(
        RegExp(r'^Based on the provided (text|context)[,.]?\s*',
            caseSensitive: false),
        '');

    // 2. Cut at stop tokens that may have leaked into output
    for (final stop in [
      '<|eot_id|>',
      '<|end_of_text|>',
      '<|im_end|>',
      '<|endoftext|>',
      '\n\nQuestion:',
      '\n\nQ:',
      '\n\nContext:',
    ]) {
      final idx = raw.indexOf(stop);
      if (idx != -1) {
        debugPrint('[SANITIZER] Stop token found at $idx: "$stop" — truncating');
        raw = raw.substring(0, idx);
      }
    }

    // 3. Deduplicate repeated lines (the most common loop pattern)
    final lines = raw.split('\n');
    final seen = <String>{};
    final deduped = <String>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        deduped.add(line); // Preserve blank lines
        continue;
      }
      if (!seen.contains(trimmed)) {
        deduped.add(line);
        seen.add(trimmed);
      } else {
        debugPrint('[SANITIZER] Duplicate line removed: "$trimmed"');
      }
    }
    raw = deduped.join('\n');

    // 4. Detect and truncate at the midpoint loop pattern
    // e.g. "A home loan can be used... A home loan can be used..."
    final words = raw.trim().split(RegExp(r'\s+'));
    if (words.length > 40) {
      final half = words.length ~/ 2;
      final firstHalf = words.sublist(0, half).join(' ').toLowerCase();
      final secondHalf = words.sublist(half).join(' ').toLowerCase();
      // If second half begins with the same 8 words as first half → loop detected
      final probe = words.sublist(0, 8).join(' ').toLowerCase();
      if (secondHalf.contains(probe)) {
        debugPrint(
            '[SANITIZER] ⚠️ Mid-response loop detected — truncating at midpoint');
        raw = words.sublist(0, half).join(' ');
      }
    }

    // 5. Cap total length to prevent excessively long answers
    if (raw.length > 1200) {
      debugPrint('[SANITIZER] Response too long (${raw.length}) — capping at 1200 chars');
      // Find last sentence boundary before cap
      final cap = raw.substring(0, 1200);
      final lastPeriod = cap.lastIndexOf(RegExp(r'[.!?]'));
      raw = lastPeriod > 800 ? cap.substring(0, lastPeriod + 1) : cap;
    }

    return raw.trim();
  }

  Future<String?> validateModelFile(String path) async {
    final file = File(path);
    if (!file.existsSync()) return 'Model file not found';
    final size = await file.length();
    if (size < 50 * 1024 * 1024) return 'File is too small/corrupt.';
    return null;
  }

  void cancelInference() {
    _isolateSendPort
        ?.send(IsolateRequest('cancel', null, ReceivePort().sendPort));
  }

  void notifyDomainSwitch() {
    // Keep warm
  }

  Future<void> clearModelCache() async {
    try {
      _disposeIsolate();
      _isInitialized = false;
      isModelReady.value = false;

      final dir = await getApplicationSupportDirectory();
      final modelDir = Directory('${dir.path}/models');
      if (await modelDir.exists()) {
        await modelDir.delete(recursive: true);
      }

      await _startIsolate();
    } catch (e) {
      debugPrint('Error clearing model cache: $e');
    }
  }
}
