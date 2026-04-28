import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../../core/services/settings_service.dart';
import '../services/on_device_inference_service.dart';
import '../rag_retrieval_service.dart';
import '../entities/chat_message.dart';
import '../hardcoded_kb_service.dart';
import '../../data/hardcoded_kb.dart';

enum InferenceBackend { ollama, onDevice }

/// Strict Document-Grounded Inference Router.
class InferenceRouterService extends GetxService {
  final Rx<InferenceBackend> currentBackend = InferenceBackend.onDevice.obs;
  
  final RxBool isManualMode = false.obs;
  final Rx<InferenceBackend> manualBackend = InferenceBackend.onDevice.obs;
  
  /// Stores the most recently retrieved chunks for programmatic citation generation.
  List<RetrievedChunk>? lastRetrievedChunks;
  bool lastIsFromKb = false;

  final _dio = Dio();
  final _kbService = HardcodedKbService();

  CancelToken? _ollamaCancelToken;
  late SettingsService _settings;
  late OnDeviceInferenceService _onDevice;
  late RagRetrievalService _retrieval;

  Future<InferenceRouterService> init() async {
    _settings = Get.find<SettingsService>();
    _onDevice = Get.find<OnDeviceInferenceService>();
    _retrieval = Get.find<RagRetrievalService>();
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

  Stream<String> probeAndRoute(String userMessage, List<ChatMessage> history) async* {
    debugPrint('[RAG] Probing: $userMessage');
    lastIsFromKb = false;

    // ── PRIORITY 0: Hardcoded KB lookup ──────────────────
    final kbMatch = _kbService.lookup(userMessage);
    if (kbMatch != null) {
      debugPrint('[KB] Hardcoded match: ${kbMatch.source}');
      lastIsFromKb = true;
      yield '${kbMatch.answer}\n\n**Sources**\n\n1. ${kbMatch.source}';
      return;
    }

    // 1. SAFETY CHECK (Non-negotiable)
    final lowerMsg = userMessage.toLowerCase();
    bool isEmergency = false;

    final tempRegex = RegExp(r'(\d{2,3}(\.\d)?)\s*(f|c|fever|temp)');
    for (final m in tempRegex.allMatches(lowerMsg)) {
      double val = double.tryParse(m.group(1) ?? '0') ?? 0;
      if (val >= 103) isEmergency = true;
    }

    final exactKeywords = [
      'seizure', 'convulsion', 'unconscious', 'chest pain',
      'overdose', 'poisoning', 'self-harm', 'bleach', 'ammonia',
      'cant breathe', "can't breathe", 'not breathing', 'not responding',
      'too many pills', 'too many tablets', 'took too much',
    ];
    if (exactKeywords.any(lowerMsg.contains)) isEmergency = true;

    final fuzzyPatterns = [
      RegExp(r'burning up'),
      RegExp(r'very high temp'),
      RegExp(r'trouble breath|hard to breath|breath.*problem|breathe properly'),
      RegExp(r'took.*lot.*medic|too much.*medic'),
      RegExp(r'mixing clean|mixing chem|household chem|cleaning product'),
      RegExp(r'passed out|blacked out|not waking|won.?t wake'),
      RegExp(r'(my )?(child|kid|baby).*(fever|temp|burning)'),
      RegExp(r'hurting myself|hurt myself|want to die|end my life'),
    ];
    if (fuzzyPatterns.any((p) => p.hasMatch(lowerMsg))) isEmergency = true;

    if (isEmergency) {
      yield '⚠️ MEDICAL ALERT:\nThis is a medical emergency requiring immediate attention.\nCall emergency services or go to the nearest emergency room right now.\nDo not attempt home treatment.\n[Source: Please consult emergency medical services immediately]\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n--- END ---';
      return;
    }

    final domainName = _settings.selectedDomain.value == 'Universal' 
        ? null 
        : _settings.selectedDomain.value;

    // 2. EXECUTE THREE-TIER RETRIEVAL
    final result = await _retrieval.retrieve(userMessage, domainName);

    // 3. DECISION HANDLING
    if (result.type == RetrievalResultType.noAnswer) {
      yield 'No answer available.';
      return;
    }

    if (result.type == RetrievalResultType.directBypass) {
      debugPrint('[RAG] Result: DIRECT BYPASS');
      debugPrint('[BYPASS] Returning text: "${result.content.substring(0, min(100, result.content.length))}"');
      final sourcesText = result.sources
          .asMap()
          .entries
          .map((e) => '${e.key + 1}. ${e.value}')
          .join('\n');

      yield '${result.content}\n\n**Sources**\n\n$sourcesText';
      return;
    }

    // 4. LLM GROUNDED QA
    debugPrint('[RAG] Result: LLM GROUNDED');
    final backend = await _resolveBackend();
    currentBackend.value = backend;

    final ragContext = result.content;

    final systemPrompt = '''
Use only the text below to answer. Do not add any information.
If the answer is not in the text, say: No answer available.

TEXT:
$ragContext
''';

    String fullLlmOutput = '';

    try {
      switch (backend) {
        case InferenceBackend.ollama:
          await for (final chunk in _streamOllama(userMessage, systemPrompt, history)) {
            fullLlmOutput += chunk;
          }
          break;
        case InferenceBackend.onDevice:
          await for (final chunk in _onDevice.respond(userMessage, systemPrompt, 'general')) {
            if (chunk.contains('🔄')) continue;
            fullLlmOutput += chunk;
          }
          break;
      }

      final finalAnswer = _validateLlmResponse(fullLlmOutput, ragContext, userMessage);
      
      if (finalAnswer.contains('No answer available')) {
        yield 'No answer available.';
      } else {
        final sourcesText = result.sources
            .asMap()
            .entries
            .map((e) => '${e.key + 1}. ${e.value}')
            .join('\n');
            
        yield '$finalAnswer\n\n**Sources**\n\n$sourcesText';
      }

    } catch (e) {
      yield '❌ System Error: $e\n--- END ---';
    }
  }

  String _validateLlmResponse(String llmOutput, String ragContext, String query) {
    final output = llmOutput.trim();
    if (output.toLowerCase().contains('no answer available')) {
      return 'No answer available.';
    }
    if (output.length > ragContext.length * 2.5) {
      return _sanitizeChunk(ragContext.split('\n\n').first);
    }
    if (output.length < 5) {
      return 'No answer available.';
    }
    return output;
  }

  String _sanitizeChunk(String raw) {
    String sanitized = raw.replaceAll(RegExp(r'^[A-Z\s\?\.\-\/]+\?\s*', multiLine: true), '');
    sanitized = sanitized.replaceAll(RegExp(r'^\d+[\.\)]\s*', multiLine: true), '');
    sanitized = sanitized.replaceAll(RegExp(r'[■●•▪︎➤]'), '');
    sanitized = sanitized.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    return sanitized;
  }

  Future<bool> _isOllamaReachable() async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none)) return false;

      final url = _settings.ollamaServerUrl;
      final probeDio = Dio();
      final resp = await probeDio.get(
        '$url/api/tags',
        options: Options(
          sendTimeout: const Duration(milliseconds: 500),
          connectTimeout: const Duration(milliseconds: 500),
          receiveTimeout: const Duration(milliseconds: 500),
        ),
      );
      return resp.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<InferenceBackend> _resolveBackend() async {
    if (isManualMode.value) return manualBackend.value;
    final ollamaReady = await _isOllamaReachable();
    if (ollamaReady) return InferenceBackend.ollama;
    return InferenceBackend.onDevice;
  }

  Stream<String> _streamOllama(
    String userMessage,
    String systemPrompt,
    List<ChatMessage> history,
  ) async* {
    _ollamaCancelToken = CancelToken();
    final url = _settings.ollamaServerUrl;
    final modelId = _settings.selectedModelId.value;

    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
      ...history.map((m) => {
        'role': m.isUser == true ? 'user' : 'assistant',
        'content': m.content,
      }),
      {'role': 'user', 'content': userMessage},
    ];

    try {
      final response = await _dio.post<ResponseBody>(
        '$url/api/chat',
        data: {'model': modelId.isEmpty ? 'llama3.2' : modelId, 'messages': messages, 'stream': true},
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
    _onDevice.cancelInference();
  }
}
