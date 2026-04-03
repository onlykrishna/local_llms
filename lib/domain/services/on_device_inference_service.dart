import 'dart:async';
import 'dart:io';
import 'package:get/get.dart';
import 'package:llamadart/llamadart.dart';
import 'package:path_provider/path_provider.dart';

/// On-device inference via llamadart (llama.cpp GGUF).
/// Loaded LAZILY — only when Layer 3 is selected by the router.
class OnDeviceInferenceService extends GetxService {
  static const String _defaultModelFileName = 'llama-3.2-1b-q4.gguf';

  LlamaServiceBase? _service;
  bool _isLoaded = false;
  String? _loadedSystemPrompt;

  final RxBool isModelReady = false.obs;
  final RxBool isLoading = false.obs;

  Future<OnDeviceInferenceService> init() async {
    // Lazy — do not load heavy model on startup
    return this;
  }

  /// Resolves the model path from app documents dir (+ ADB migration fallback).
  Future<String?> resolveModelPath() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/models/$_defaultModelFileName';
    if (await File(path).exists()) {
      final size = await File(path).length();
      if (size > 200 * 1024 * 1024) return path; // >200MB = valid
    }

    // Fallback: check external storage (adb push scenario)
    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        final extPath = '${ext.path}/$_defaultModelFileName';
        if (await File(extPath).exists()) {
          // Migrate to internal sandbox
          final destFile = File(path);
          await destFile.parent.create(recursive: true);
          await File(extPath).copy(path);
          print('📦 Model migrated from external storage to sandbox.');
          return path;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Lazy-loads the engine. Safe to call multiple times.
  Future<bool> ensureLoaded(String systemPrompt) async {
    if (_isLoaded && _service != null && _service!.isReady) {
      return true;
    }

    final modelPath = await resolveModelPath();
    if (modelPath == null) {
      isModelReady.value = false;
      return false;
    }

    isLoading.value = true;
    try {
      // Dispose previous session if re-initializing
      _service?.dispose();
      _service = LlamaService();

      await _service!.init(
        modelPath,
        modelParams: const ModelParams(
          contextSize: 2048,
          gpuLayers: 0, // CPU-only for compatibility
          preferredBackend: GpuBackend.cpu,
        ),
      );

      _loadedSystemPrompt = systemPrompt;
      _isLoaded = true;
      isModelReady.value = true;
      print('🚀 On-Device AI Engine loaded (CPU mode).');
      return true;
    } catch (e) {
      print('❌ OnDevice Engine Load Error: $e');
      isModelReady.value = false;
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  /// Streams response tokens from on-device llama.cpp.
  Stream<String> respond(String userMessage, String systemPrompt) async* {
    final ready = await ensureLoaded(systemPrompt);
    if (!ready || _service == null) {
      yield '⚠️ On-device model not found. Go to the Model Setup screen to download Llama 3.2 1B (~650 MB).';
      return;
    }

    // Build the prompt using the chat template
    final messages = <LlamaChatMessage>[
      LlamaChatMessage(role: 'system', content: systemPrompt),
      LlamaChatMessage(role: 'user', content: userMessage),
    ];

    try {
      final formattedPrompt = await _service!.applyChatTemplate(messages);
      
      yield* _service!.generate(
        formattedPrompt,
        params: const GenerationParams(
          maxTokens: 512,
          temp: 0.7,
          topP: 0.9,
          penalty: 1.1, // CRITICAL: prevents repetition loops
        ),
      );
    } catch (e) {
      yield '\n[Error: $e]';
    }
  }

  void cancelInference() {
    _service?.cancelGeneration();
  }

  @override
  void onClose() {
    _service?.dispose();
    super.onClose();
  }
}
