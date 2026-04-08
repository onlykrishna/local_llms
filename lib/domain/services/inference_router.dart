import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../../data/datasources/gemini_datasource.dart';
import '../../core/services/settings_service.dart';
import '../services/domain_service.dart';
import '../services/on_device_inference_service.dart';
import '../models/inference_domain.dart';

enum InferenceBackend { ollama, gemini, onDevice }

/// Detection result for domain mismatch (Legacy support)
class DomainDetection {
  final InferenceDomain? detectedDomain;
  final double confidence;
  DomainDetection({this.detectedDomain, this.confidence = 0.0});
}

/// Smart 3-layer Inference Router with Domain-Aware Prompting.
class InferenceRouterService extends GetxService {
  final Rx<InferenceBackend> currentBackend = InferenceBackend.onDevice.obs;
  
  final RxBool isManualMode = false.obs;
  final Rx<InferenceBackend> manualBackend = InferenceBackend.gemini.obs;

  final _gemini = GeminiDatasource();
  final _dio = Dio();

  CancelToken? _ollamaCancelToken;
  late SettingsService _settings;
  late OnDeviceInferenceService _onDevice;
  late DomainService _domainService;

  Future<InferenceRouterService> init() async {
    _settings = Get.find<SettingsService>();
    _onDevice = Get.find<OnDeviceInferenceService>();
    _domainService = Get.find<DomainService>();
    return this;
  }

  void setManualBackend(InferenceBackend backend) {
    isManualMode.value = true;
    manualBackend.value = backend;
    currentBackend.value = backend;
  }

  void resetToAuto() {
    isManualMode.value = false;
  }

  // STEP 3: Domain-specific system prompts (as per Prompt Specs)
  static const Map<InferenceDomain, String> domainSystemPrompts = {
     InferenceDomain.health: 'You are a health and wellness advisor. Provide accurate, science-backed health information. Always recommend consulting healthcare professionals for medical emergencies.',
     InferenceDomain.bollywood: 'You are an expert in Indian cinema and Bollywood culture. Provide detailed information about movies, actors, and entertainment industry trends.',
     InferenceDomain.education: 'You are an education specialist. Help students with academic concepts, study strategies, and learning resources. Be encouraging and clear.',
     InferenceDomain.general: 'You are a helpful, knowledgeable AI assistant. Provide accurate, balanced information on any topic.'
  };

  /// Main entry point (probeAndRoute)
  /// Backwards Compatibility: selectedDomain defaults to 'General' (Scenario 1)
  Stream<String> probeAndRoute({
    required String userMessage,
    InferenceDomain selectedDomain = InferenceDomain.general,
    required List<Map<String, dynamic>> history,
  }) async* {
    yield '⏳ Probing environment...';
    
    final backend = await _resolveBackend();
    currentBackend.value = backend;

    // STEP 3.3: Prepend the domain-specific system prompt
    final systemPrompt = domainSystemPrompts[selectedDomain] ?? domainSystemPrompts[InferenceDomain.general]!;
    final domainName = selectedDomain.name;

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
        } catch (e) {
             currentBackend.value = InferenceBackend.onDevice;
             yield* _onDevice.respond(userMessage, systemPrompt, domainName);
        }
        break;
      case InferenceBackend.onDevice:
        yield* _onDevice.respond(userMessage, systemPrompt, domainName);
        break;
    }
  }

  /// STEP 4: Response Consistency Guardrails (Scenario 1)
  bool validateResponseRelevance(String responseText, InferenceDomain domain) {
    final text = responseText.toLowerCase();
    if (domain == InferenceDomain.general) return true;

    // Use keywords defined in DomainService (via static const exposure)
    final domainKeywords = DomainService.domainKeywords[domain] ?? [];
    if (domainKeywords.isEmpty) return true;

    return domainKeywords.any(text.contains);
  }

  Future<bool> _isOllamaReachable() async {
    try {
      final ip = _settings.ollamaIp.value;
      final port = _settings.ollamaPort.value;
      final probeDio = Dio();
      final resp = await probeDio.get(
        'http://$ip:$port/api/tags',
        options: Options(
          sendTimeout: const Duration(milliseconds: 1500),
          connectTimeout: const Duration(milliseconds: 1500),
          receiveTimeout: const Duration(milliseconds: 1500),
        ),
      );
      return resp.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<bool> _hasInternet() async {
    final result = await Connectivity().checkConnectivity();
    return result.isNotEmpty && !result.every((r) => r == ConnectivityResult.none);
  }

  Future<InferenceBackend> _resolveBackend() async {
    if (isManualMode.value) return manualBackend.value;
    final ollamaReady = await _isOllamaReachable();
    if (ollamaReady) return InferenceBackend.ollama;
    final hasInternet = await _hasInternet();
    final hasGeminiKey = _settings.geminiApiKey.value.isNotEmpty;
    if (hasInternet && hasGeminiKey) return InferenceBackend.gemini;
    return InferenceBackend.onDevice;
  }

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
            String cleanLine = line.trim();
            if (cleanLine.isEmpty) continue;
            final start = cleanLine.indexOf('"content":"');
            if (start != -1) {
              final contentStart = start + 11;
              final contentEnd = cleanLine.indexOf('"', contentStart);
              if (contentEnd > contentStart) {
                yield cleanLine.substring(contentStart, contentEnd);
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

  void cancelCurrentRequest() {
    _ollamaCancelToken?.cancel('Cancelled by user');
    _ollamaCancelToken = null;
    _gemini.cancel();
    _onDevice.cancelInference();
  }
}
