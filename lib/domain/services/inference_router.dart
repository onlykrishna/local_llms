import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../../data/datasources/gemini_datasource.dart';
import '../../core/services/settings_service.dart';
import '../services/domain_service.dart';
import '../services/on_device_inference_service.dart';
import '../services/factual_hardening_service.dart';
import '../models/inference_domain.dart';

enum InferenceBackend { ollama, gemini, onDevice }

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

  Future<InferenceRouterService> init() async {
    _settings = Get.find<SettingsService>();
    _onDevice = Get.find<OnDeviceInferenceService>();
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

  static const Map<InferenceDomain, String> domainSystemPrompts = {
     InferenceDomain.health: '''Medical Assist Only. Rules:
1. SAFETY SCAN: If fever >= 103°F or 110°F, output ONLY: "⚠️ MEDICAL ALERT: A fever of [X] is a medical emergency. Go to the nearest emergency room immediately. Do not attempt home treatment." Stop.
2. IF NOT EMERGENCY structure:
- Likely meaning (1 sentence)
- Action (2-3 bullets)
- Doctor threshold (1 sentence)
- Source: "Please verify with a licensed medical professional."''',
     InferenceDomain.bollywood: 'Factual Bollywood historian. Provide specific names, dates, and awards. Avoid conversational filler and generic advice.',
     InferenceDomain.education: 'Academic assistant. Explain concepts directly and objectively. No conversational padding or tutor-style fluff.',
     InferenceDomain.general: 'Precise assistant. Direct, objective info. No filler.'
  };

  Stream<String> probeAndRoute({
    required String userMessage,
    InferenceDomain selectedDomain = InferenceDomain.general,
    required List<Map<String, dynamic>> history,
  }) async* {
    // v3.1: All routing/classification is silent — no status messages yielded to UI

    // 1. GLOBAL SAFETY OVERRIDE (Master v2.0 Section 2 — P1 Fix)
    final lowerMsg = userMessage.toLowerCase();
    bool isEmergency = false;

    // Explicit temperature threshold check
    final tempRegex = RegExp(r'(\d{2,3}(\.\d)?)\s*(f|c|fever|temp)');
    for (final m in tempRegex.allMatches(lowerMsg)) {
      double val = double.tryParse(m.group(1) ?? '0') ?? 0;
      if (val >= 103) isEmergency = true;
    }

    // Explicit keyword triggers
    final exactKeywords = [
      'seizure', 'convulsion', 'unconscious', 'chest pain',
      'overdose', 'poisoning', 'self-harm', 'bleach', 'ammonia',
      'cant breathe', "can't breathe", 'not breathing', 'not responding',
      'too many pills', 'too many tablets', 'took too much',
    ];
    if (exactKeywords.any(lowerMsg.contains)) isEmergency = true;

    // Fuzzy pattern triggers (P1 Fix)
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

    // 2. BACKEND RESOLUTION
    final backend = await _resolveBackend();
    currentBackend.value = backend;
    final hardening = Get.find<FactualHardeningService>();
    final domainName = selectedDomain.name;

    try {
      switch (backend) {
        case InferenceBackend.ollama:
          final systemPrompt = hardening.getConsolidatedSystemPrompt();
          yield* _streamOllama(userMessage, systemPrompt, history);
          break;
        case InferenceBackend.gemini:
          final systemPrompt = hardening.getConsolidatedSystemPrompt();
          yield* _gemini.streamChat(
            apiKey: _settings.geminiApiKey.value,
            userMessage: userMessage,
            systemPrompt: systemPrompt,
            history: history,
          );
          break;
        case InferenceBackend.onDevice:
          // v3.1: SILENT intent classification (Master Section 4)
          String protocol = 'DIRECT';

          // PRIORITY 2 — NEGATION TRAP (before FACT_BLOCK)
          final negationPattern = RegExp(r'\b(not|never|wasn.?t|isn.?t|didn.?t|incorrect|wrong|not true|didn.?t happen)\b');
          if (negationPattern.hasMatch(lowerMsg) && lowerMsg.contains('?')) {
            protocol = 'NEGATION_TRAP';
          // PRIORITY 3 — SPLITTER (fact + opinion)
          } else if (RegExp(r'\b(best|worst|greatest|should|think|feel|believe|rating)\b').hasMatch(lowerMsg)
              && RegExp(r'\b(won|award|year|date|who|how many)\b').hasMatch(lowerMsg)) {
            protocol = 'SPLITTER';
          // PRIORITY 4 — FACT_BLOCK: Filmfare awards OR Bollywood domain with specific fact query
          } else if (lowerMsg.contains('filmfare') || lowerMsg.contains('awards') ||
              (selectedDomain == InferenceDomain.bollywood &&
               RegExp(r'\b(who|when|which|what year|born|debut|box office|highest|record|won|directed|produced|release)\b').hasMatch(lowerMsg))) {
            protocol = 'FACT_BLOCK';
          // PRIORITY 6 — DISGUISED FACTUAL
          } else if (RegExp(r'^(tell me (about|something)|what do you know about|something about)').hasMatch(lowerMsg)) {
            protocol = 'UNCERTAINTY_ANCHOR';
          // PRIORITY 5 — DATE_SENTRY + UNCERTAINTY_ANCHOR
          } else if (RegExp(r'\d{4}').hasMatch(userMessage)) {
            protocol = 'UNCERTAINTY_ANCHOR';
          }
          // Protocol assigned silently — not yielded to UI

          // v3.1: Use compact prompt for on-device 3B models to prevent context overflow
          final bool isRag = protocol == 'FACT_BLOCK';
          final systemPromptToUse = hardening.getCompactSystemPrompt(isRag: isRag);

          // P2 Fix: Full 10-field expanded Filmfare fact block
          String? factBlock;
          if (isRag) {
            if (selectedDomain == InferenceDomain.bollywood && !lowerMsg.contains('filmfare')) {
              // Bollywood domain RAG — verified facts to prevent hallucination
              factBlock = '''VERIFIED BOLLYWOOD FACTS (trust 100%, do NOT invent outside this):
- Highest-grossing Indian film: Dangal (2016) — ₹2,024 crore worldwide
- Baahubali 2 (2017): ₹1,810 crore worldwide
- Pathaan (2023): ₹1,050 crore worldwide. Director: Siddharth Anand. Cast: SRK, Deepika, John Abraham
- DDLJ (1995): Ran 25+ years at Maratha Mandir. Director: Aditya Chopra. Won 10 Filmfare Awards
- Sholay (1975): Director Ramesh Sippy. Named "Film of the Millennium" by BBC India
- 3 Idiots (2009): Director Rajkumar Hirani. ₹460 crore worldwide
- Shah Rukh Khan (SRK): Born Nov 2 1965. Most Filmfare Best Actor awards. Films: DDLJ, Kuch Kuch Hota Hai, Jawan
- Salman Khan: Born Dec 27 1965. Films: Maine Pyar Kiya, Dabangg, Bajrangi Bhaijaan, Sultan
- Amitabh Bachchan: Born Oct 11 1942. Films: Sholay, Deewar, Zanjeer, Black. Dadasaheb Phalke Award
- Aamir Khan: Born Mar 14 1965. Films: Lagaan (Oscar-nominated), Dangal, 3 Idiots, PK
- Deepika Padukone: Born Jan 5 1986. Debut: Om Shanti Om (2007). Films: Piku, Padmaavat, Pathaan
- Filmfare Awards first held: March 21 1954. Organizer: Times of India Group. First Best Actor: Dilip Kumar (Daag)
If the answer is NOT in these facts, respond: "NO_DATA: This model is not yet updated with complete knowledge on this topic. Please refer to an official source."''';
            } else {
              // Filmfare-specific fact block
              factBlock = '''VERIFIED FILMFARE FACTS (1954 ONLY — trust 100%):
- First ceremony: March 21, 1954
- Best Actor: Dilip Kumar — film: Daag
- Best Actress: Meena Kumari — film: Parineeta (NOT Baiju Bawra)
- Best Film: Do Bigha Zamin
- Best Director: Bimal Roy — film: Do Bigha Zamin
- Organized by: The Times of India Group
- Also called: Black Lady Awards
If year in question is NOT 1954, say: "MISMATCH: My verified data covers 1954 only."
If answer not in facts, say: "NO_DATA: This model is not yet updated with complete knowledge on this topic. Please check official Filmfare records."''';
              final userYearMatch = RegExp(r'\b(19|20)\d{2}\b').firstMatch(userMessage);
              if (userYearMatch != null && userYearMatch.group(0) != '1954') {
                yield '❌ MISMATCH: My verified data covers 1954, not ${userYearMatch.group(0)}.\n--- END ---';
                return;
              }
            }
          }


          final finalUserPrompt = hardening.buildFactualPrompt(
            question: userMessage,
            factBlock: factBlock,
          );

          // Track meaningful output to detect silent model failure
          int meaningfulChunkCount = 0;
          String? lastErrorChunk;

          // Buffer full response to apply whole-text post-processing
          final responseBuffer = StringBuffer();
          await for (final status in _onDevice.respond(finalUserPrompt, systemPromptToUse, domainName)) {
            if (status.contains('⚠️') || status.contains('❌')) {
              lastErrorChunk = status;
              break;
            }
            responseBuffer.write(status);
            meaningfulChunkCount++;
          }

          if (meaningfulChunkCount > 0) {
            // Apply full post-processing pipeline on the complete response
            String full = responseBuffer.toString();
            full = hardening.sanitizeOutput(full);               // strip tokens
            full = hardening.stripSystemLeak(full);              // strip echoed prompt
            full = hardening.enforceFormatCompliance(full);      // fix merged words
            full = hardening.enforceResponseStructure(full, finalUserPrompt); // rebuild structure
            full = hardening.addVerificationFlags(full);         // tag dates
            if (full.trim().isNotEmpty) yield full;
          }

          // If model produced no content, explain why instead of showing a blank response
          if (meaningfulChunkCount == 0) {
            if (lastErrorChunk != null) {
              yield lastErrorChunk;
            } else {
              yield '❌ Model returned no response.\n\n'
                  'Possible reasons:\n'
                  '1. Context overflow — question was too long for available model memory.\n'
                  '2. Model is still loading — please try again in a moment.\n'
                  '3. Insufficient RAM — close other apps and retry.\n\n'
                  'Try rephrasing your question more briefly.\n--- END ---';
              return;
            }
          }
          yield '\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n--- END ---';
          break;
      }
    } catch (e) {
      yield '❌ System Error: $e\n--- END ---';
    }
  }

  /// STEP 4: Response Consistency Guardrails (Scenario 1)
  bool validateResponseRelevance(String responseText, InferenceDomain domain) {
    // Pass if general or if it's a known error status
    if (domain == InferenceDomain.general) return true;
    if (responseText.contains('⚠️') || responseText.contains('❌')) return true;
    if (responseText.contains('⏳')) return true;

    final text = responseText.toLowerCase();

    // Use keywords defined in DomainService
    final domainKeywords = DomainService.domainKeywords[domain] ?? [];
    if (domainKeywords.isEmpty) return true;

    return domainKeywords.any(text.contains);
  }

  Future<bool> _isOllamaReachable() async {
    try {
      final url = _settings.ollamaServerUrl;
      final probeDio = Dio();
      final resp = await probeDio.get(
        '$url/api/tags',
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
    final url = _settings.ollamaServerUrl;
    final modelId = _settings.selectedModelId.value;

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
    _gemini.cancel();
    _onDevice.cancelInference();
  }
}
