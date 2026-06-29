import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:fllama/fllama.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import '../models/chat_message.dart';

/// Service for running a local GGUF language model on-device via fllama
/// (Flutter binding for llama.cpp).
///
/// Architecture:
///   • [downloadModel]  — streams the GGUF file from HuggingFace with progress.
///   • [loadModel]      — initialises a native llama.cpp context via fllama.
///   • [generate]       — runs inference, streaming tokens via [onToken].
///   • [unloadModel]    — frees native context and RAM.
///
/// The model file is stored under {appSupportDir}/models/ to survive app updates.
class LocalLlmService extends GetxService {
  // ── Reactive state ──────────────────────────────────────
  final RxBool isModelReady = false.obs;
  final RxBool isDownloading = false.obs;
  final RxDouble downloadProgress = 0.0.obs;
  final RxString loadError = ''.obs;

  // ── Model configuration ─────────────────────────────────
  // Llama 3.2 3B Instruct Q4_K_M — ~2 GB, good balance of quality vs. RAM.
  // Requires ≥ 4 GB RAM on device. Runs on arm64-v8a Android and iOS arm64.
  static const String modelDownloadUrl =
      'https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf';
  static const String modelFileName = 'llama-3.2-3b-instruct-q4.gguf';

  // ── Internal ─────────────────────────────────────────────
  final Dio _dio = Dio();

  /// Native fllama context ID. Non-null only when model is loaded.
  String? _contextId;

  // ── Directory helpers ────────────────────────────────────

  Future<String> get _modelDirPath async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/models';
  }

  Future<String> get _modelFilePath async {
    return '${await _modelDirPath}/$modelFileName';
  }

  // ── Public API ───────────────────────────────────────────

  /// Returns true if the GGUF file has been downloaded and is non-empty.
  Future<bool> isModelDownloaded() async {
    try {
      final file = File(await _modelFilePath);
      return file.existsSync() && await file.length() > 0;
    } catch (_) {
      return false;
    }
  }

  /// Downloads the model file to [_modelDirPath] via a streamed dio download.
  /// Calls [onProgress] with values 0.0→1.0. Writes to a .tmp file first,
  /// then renames so a partial download is never mistaken for a complete one.
  Future<void> downloadModel({
    required void Function(double progress) onProgress,
  }) async {
    if (isDownloading.value) return;

    try {
      isDownloading.value = true;
      downloadProgress.value = 0.0;
      loadError.value = '';

      final dirPath = await _modelDirPath;
      await Directory(dirPath).create(recursive: true);
      final tmpPath = '$dirPath/$modelFileName.tmp';
      final finalPath = '$dirPath/$modelFileName';

      await _dio.download(
        modelDownloadUrl,
        tmpPath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress = received / total;
            downloadProgress.value = progress;
            onProgress(progress);
          }
        },
        options: Options(
          receiveTimeout: const Duration(hours: 2),
          sendTimeout: const Duration(seconds: 30),
        ),
      );

      // Rename temp → final only on full download success
      await File(tmpPath).rename(finalPath);
      debugPrint('✅ LocalLlmService: Model downloaded to $finalPath');
    } catch (e) {
      loadError.value = 'Download failed: $e';
      debugPrint('❌ LocalLlmService: Download error: $e');
      rethrow;
    } finally {
      isDownloading.value = false;
    }
  }

  /// Loads the GGUF model into a native llama.cpp context via fllama.
  /// Sets [isModelReady] to true on success, [loadError] on failure.
  Future<void> loadModel() async {
    loadError.value = '';
    isModelReady.value = false;

    try {
      final path = await _modelFilePath;
      if (!File(path).existsSync()) {
        throw Exception('Model file not found. Download it first from Settings.');
      }

      debugPrint('🦙 LocalLlmService: Initialising fllama context from $path');

      final fllama = Fllama.instance();
      if (fllama == null) {
        throw Exception('fllama is not available on this platform/architecture.');
      }

      // initContext returns a Map with a 'contextId' key (> 0 on success).
      // emitLoadProgress: true fires progress events via onTokenStream.
      final result = await fllama.initContext(path, emitLoadProgress: true);
      final ctxId = result?['contextId'];

      if (ctxId == null || (ctxId is num && ctxId <= 0)) {
        throw Exception('fllama returned invalid contextId ($ctxId). '
            'Model may be corrupt or device has insufficient RAM.');
      }

      _contextId = ctxId.toString();
      isModelReady.value = true;
      debugPrint('✅ LocalLlmService: Model loaded. contextId=$_contextId');
    } catch (e) {
      loadError.value = 'Failed to load model: $e';
      isModelReady.value = false;
      _contextId = null;
      debugPrint('❌ LocalLlmService: Load error: $e');
    }
  }

  /// Frees the native llama.cpp context and reclaims RAM.
  /// Must be called when switching away from the Offline provider.
  Future<void> unloadModel() async {
    if (_contextId != null) {
      try {
        Fllama.instance()?.releaseContext(double.parse(_contextId!));
        debugPrint('✅ LocalLlmService: Context $_contextId released.');
      } catch (e) {
        debugPrint('⚠️ LocalLlmService: releaseContext error (safe to ignore): $e');
      }
      _contextId = null;
    }
    isModelReady.value = false;
    debugPrint('✅ LocalLlmService: Model unloaded.');
  }

  /// Runs inference on [messages] and returns the complete assistant reply.
  ///
  /// Streams tokens via [onToken] for a typing-effect UI.
  /// Throws [StateError] if the model is not loaded.
  /// Throws [Exception] if inference fails.
  Future<String> generate({
    required List<ChatMessage> messages,
    void Function(String token)? onToken,
  }) async {
    if (!isModelReady.value || _contextId == null) {
      throw StateError(
          'Offline model not loaded. Call loadModel() or download from Settings first.');
    }

    final fllama = Fllama.instance();
    if (fllama == null) {
      throw Exception('fllama is not available on this platform.');
    }

    final prompt = _buildChatMLPrompt(messages);
    debugPrint(
        '🦙 LocalLlmService: Running inference (prompt length: ${prompt.length}, contextId: $_contextId)');

    final resultBuffer = StringBuffer();
    final completer = Completer<String>();

    // fllama streams tokens via onTokenStream. We listen for 'completion' events
    // matching our contextId and accumulate tokens until stop_type == 'stop' or 'eos'.
    final subscription = fllama.onTokenStream?.listen((data) {
      if (completer.isCompleted) return;

      final fn = data['function'] as String?;
      if (fn == 'completion') {
        final result = data['result'] as Map?;
        final token = result?['token'] as String? ?? '';
        final stopType = result?['stop_type'] as String?;

        if (token.isNotEmpty) {
          resultBuffer.write(token);
          onToken?.call(token);
        }

        if (stopType == 'stop' || stopType == 'eos' || stopType == 'limit') {
          if (!completer.isCompleted) {
            completer.complete(resultBuffer.toString().trim());
          }
        }
      }
    });

    try {
      // Kick off completion — fllama streams tokens asynchronously via onTokenStream
      await fllama.completion(
        double.parse(_contextId!),
        prompt: prompt,
        nPredict: 512,
        temperature: 0.7,
        topP: 0.9,
        penaltyRepeat: 1.1,
      );

      // Wait for the stream to signal completion (stop_type)
      final reply = await completer.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () => throw TimeoutException(
          'Offline model took too long. Try a smaller/more quantized model, '
          'or reduce context length.',
        ),
      );

      debugPrint('✅ LocalLlmService: Inference complete (${reply.length} chars).');
      return reply;
    } catch (e) {
      debugPrint('❌ LocalLlmService: Inference error: $e');
      rethrow;
    } finally {
      await subscription?.cancel();
    }
  }

  /// Deletes the downloaded model file and resets all state.
  Future<void> deleteModel() async {
    await unloadModel();
    try {
      final file = File(await _modelFilePath);
      if (file.existsSync()) await file.delete();
      downloadProgress.value = 0.0;
      debugPrint('✅ LocalLlmService: Model file deleted.');
    } catch (e) {
      debugPrint('❌ LocalLlmService: Delete error: $e');
    }
  }

  // ── Prompt formatting ─────────────────────────────────────

  /// Converts [ChatMessage] list into ChatML format, which most instruction-tuned
  /// GGUF models (Llama 3, Mistral Instruct, Phi-3, etc.) expect.
  ///
  /// Format:
  ///   <|im_start|>system\n{content}<|im_end|>
  ///   <|im_start|>user\n{content}<|im_end|>
  ///   <|im_start|>assistant\n          ← the model continues from here
  String _buildChatMLPrompt(List<ChatMessage> messages) {
    final buffer = StringBuffer();
    for (final msg in messages) {
      final role = switch (msg.role) {
        MessageRole.system => 'system',
        MessageRole.user => 'user',
        MessageRole.assistant => 'assistant',
      };
      
      // Extract text content only (skip images for text-only local models)
      String textContent = msg.content;

      // Prevent massive context blow-up for local offline models (e.g. large PDFs)
      if (textContent.length > 3000) {
        textContent = '${textContent.substring(0, 3000)}\n...[Truncated for local context limit]';
      }

      buffer.writeln('<|im_start|>$role');
      buffer.writeln(textContent);
      buffer.writeln('<|im_end|>');
    }
    buffer.write('<|im_start|>assistant\n');
    return buffer.toString();
  }
}
