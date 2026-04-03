import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:get/get.dart';
import '../../data/datasources/gemini_datasource.dart';
import '../../core/services/settings_service.dart';
import '../services/domain_service.dart';
import '../services/on_device_inference_service.dart';

enum InferenceBackend { ollama, gemini, onDevice }

/// Smart 3-layer Inference Router.
///
/// Priority:
///   1. Ollama LAN (1.5s probe)
///   2. Gemini 1.5 Flash (free API, if internet)
///   3. On-device llama.cpp (always available fallback)
class InferenceRouterService extends GetxService {
  final Rx<InferenceBackend> currentBackend = InferenceBackend.onDevice.obs;

  final _gemini = GeminiDatasource();
  final _dio = Dio();

  CancelToken? _ollamaCancelToken;
  StreamSubscription? _activeSubscription;

  late SettingsService _settings;
  late OnDeviceInferenceService _onDevice;

  Future<InferenceRouterService> init() async {
    _settings = Get.find<SettingsService>();
    _onDevice = Get.find<OnDeviceInferenceService>();
    return this;
  }

  /// Probe Ollama with 1.5-second timeout.
  Future<bool> _isOllamaReachable() async {
    try {
      final ip = _settings.ollamaIp.value;
      final port = _settings.ollamaPort.value;
      final resp = await _dio
          .get('http://$ip:$port/api/tags')
          .timeout(const Duration(milliseconds: 1500));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _hasInternet() async {
    final result = await Connectivity().checkConnectivity();
    return result.isNotEmpty && !result.contains(ConnectivityResult.none);
  }

  Future<InferenceBackend> _resolveBackend() async {
    // Layer 1: Try Ollama LAN
    if (await _isOllamaReachable()) {
      return InferenceBackend.ollama;
    }
    // Layer 2: Internet → Gemini
    if (await _hasInternet() && _settings.geminiApiKey.value.isNotEmpty) {
      return InferenceBackend.gemini;
    }
    // Layer 3: On-device
    return InferenceBackend.onDevice;
  }

  /// Main entry point: streams response tokens for a given prompt.
  Stream<String> respond({
    required String userMessage,
    required String systemPrompt,
    required List<Map<String, dynamic>> history,
  }) async* {
    final backend = await _resolveBackend();
    currentBackend.value = backend;

    switch (backend) {
      case InferenceBackend.ollama:
        yield* _streamOllama(userMessage, systemPrompt, history);
        break;
      case InferenceBackend.gemini:
        try {
          yield* _gemini.streamChat(
            apiKey: _settings.geminiApiKey.value,
            userMessage: userMessage,
            systemPrompt: systemPrompt,
            history: history,
          );
        } on GeminiRateLimitException {
          // Fallback to on-device
          currentBackend.value = InferenceBackend.onDevice;
          yield* _onDevice.respond(userMessage, systemPrompt);
        }
        break;
      case InferenceBackend.onDevice:
        yield* _onDevice.respond(userMessage, systemPrompt);
        break;
    }
  }

  /// Streams Ollama /api/chat with system prompt injected.
  Stream<String> _streamOllama(
    String userMessage,
    String systemPrompt,
    List<Map<String, dynamic>> history,
  ) async* {
    _ollamaCancelToken = CancelToken();
    final ip = _settings.ollamaIp.value;
    final port = _settings.ollamaPort.value;
    final model = _settings.selectedModel.value;

    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
      ...history.map((m) => {
        'role': m['isUser'] == true ? 'user' : 'assistant',
        'content': m['content'],
      }),
      {'role': 'user', 'content': userMessage},
    ];

    try {
      final response = await _dio.post<ResponseBody>(
        'http://$ip:$port/api/chat',
        data: {'model': model, 'messages': messages, 'stream': true},
        options: Options(responseType: ResponseType.stream),
        cancelToken: _ollamaCancelToken,
      );

      await for (final chunk in response.data!.stream
          .map((bytes) => String.fromCharCodes(bytes))
          .where((s) => s.trim().isNotEmpty)) {
        if (_ollamaCancelToken?.isCancelled ?? false) break;
        try {
          final lines = chunk.split('\n');
          for (final line in lines) {
            if (line.trim().isEmpty) continue;
            final json = line.trim();
            // Ollama returns {"message":{"role":"assistant","content":"token"},"done":false}
            final start = json.indexOf('"content":"');
            if (start != -1) {
              final contentStart = start + 11;
              final contentEnd = json.indexOf('"', contentStart);
              if (contentEnd > contentStart) {
                yield json.substring(contentStart, contentEnd);
              }
            }
          }
        } catch (_) {}
      }
    } on DioException catch (e) {
      if (e.type != DioExceptionType.cancel) {
        yield '\n[Ollama Error: ${e.message}]';
      }
    }
  }

  /// Cancel any in-flight request immediately.
  void cancelCurrentRequest() {
    _ollamaCancelToken?.cancel('Cancelled by user');
    _ollamaCancelToken = null;
    _gemini.cancel();
    _onDevice.cancelInference();
  }
}
