import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../../core/services/settings_service.dart';
import '../services/on_device_inference_service.dart';
import '../rag_retrieval_service.dart';
import '../entities/chat_message.dart';
import '../../data/document_chunk.dart';
import 'acronym_expander.dart';
import 'fuzzy_query_corrector.dart';
import '../deterministic_kb_matcher.dart';
import '../../objectbox.g.dart';

enum InferenceBackend { ollama, onDevice }

enum QueryStage {
  expanding,
  embedding,
  searching,
  reranking,
  generating,
  done,
}

class QueryStatus {
  final QueryStage stage;
  final String message;
  final String? detail;
  const QueryStatus({required this.stage, required this.message, this.detail});
}

/// Strict Document-Grounded Inference Router.
class InferenceRouterService extends GetxService {
  final Rx<InferenceBackend> currentBackend = InferenceBackend.onDevice.obs;

  final RxBool isManualMode = false.obs;
  final Rx<InferenceBackend> manualBackend = InferenceBackend.onDevice.obs;

  List<ScoredChunk>? lastRetrievedChunks;
  bool lastIsFromKb = false;
  bool lastRequiresLlm = false;

  // ── Topic guard: only answer questions about these known topics ────────────
  static const Set<String> _knownTopics = {
    'home loan', 'loan', 'emi', 'pre-emi', 'pemi', 'ltv',
    'amortization', 'tenure', 'interest', 'rate', 'disbursement',
    'sanction', 'working capital', 'business loan', 'unsecured',
    'collateral', 'security', 'mortgage', 'property', 'lap',
    'tax', 'co-applicant', 'nri', 'insurance', 'startup',
    'sme', 'nbfc', 'eligibility', 'eligible', 'avail',
    'repayment', 'principal', 'instalment', 'installment',
    'balance transfer', 'plot', 'renovation', 'construction',
    'salaried', 'self employed', 'itr', 'kyc', 'documents', 'document',
    'summary', 'summarize', 'about', 'overview', 'explain', 'tell me',
  };

  bool _isOnTopic(String query) {
    final q = query.toLowerCase();
    if (q.length < 4) return true;
    return _knownTopics.any((topic) => q.contains(topic));
  }

  final _deterministicMatcher = DeterministicKbMatcher();
  final _kbChunkCache = <String, DocumentChunk>{};

  final _dio = Dio();

  final _queryStatusController = StreamController<QueryStatus>.broadcast();
  Stream<QueryStatus> get queryStatusStream => _queryStatusController.stream;

  CancelToken? _ollamaCancelToken;
  late SettingsService _settings;
  late OnDeviceInferenceService _onDevice;
  late RagRetrievalService _retrieval;

  Future<InferenceRouterService> init() async {
    _settings = Get.find<SettingsService>();
    _onDevice = Get.find<OnDeviceInferenceService>();
    _retrieval = Get.find<RagRetrievalService>();

    Future.delayed(const Duration(seconds: 2), () => _buildKbCache());

    return this;
  }

  void _buildKbCache() {
    try {
      final allKb = _retrieval.chunkBox
          .query(DocumentChunk_.isHardcoded.equals(true))
          .build()
          .find();

      _kbChunkCache.clear();
      for (final chunk in allKb) {
        if (chunk.tags != null) {
          _kbChunkCache[chunk.tags!] = chunk;
        }
      }
      debugPrint('[CACHE] KB cache built: ${_kbChunkCache.length} entries');
    } catch (e) {
      debugPrint('[CACHE] Error building KB cache: $e');
    }
  }

  void _emit(QueryStage stage, String message, {String? detail}) {
    _queryStatusController
        .add(QueryStatus(stage: stage, message: message, detail: detail));
  }

  void setManualBackend(InferenceBackend backend) {
    isManualMode.value = true;
    manualBackend.value = backend;
    currentBackend.value = backend;
  }

  void resetToAuto() {
    isManualMode.value = false;
  }

  Stream<String> probeAndRoute(
      String rawUserMessage, List<ChatMessage> history) async* {
    // Step 1: Fuzzy correction — correctedQuery used for BOTH retrieval AND LLM
    final correctedQuery = FuzzyQueryCorrector.correct(rawUserMessage);
    print('[ROUTER] Original query: "$rawUserMessage"');
    if (correctedQuery != rawUserMessage.toLowerCase().trim()) {
      print('[ROUTER] Corrected query: "$correctedQuery"');
    }

    lastIsFromKb = false;

    /* 
    // ── PRIORITY 0: Deterministic rule match ─────────────────────────────────
    final matchedId = _deterministicMatcher.match(userMessage);
    if (matchedId != null) {
      final chunk = _kbChunkCache[matchedId];
      if (chunk != null) {
        debugPrint('[ROUTER] Deterministic match → $matchedId');
        lastIsFromKb = true;
        lastRequiresLlm = false;
        final sourcesText = '1. 📄 Knowledge Base — ${chunk.category ?? "FAQ"}';
        yield '${chunk.text}\n\n**Sources**\n\n$sourcesText';
        _emit(QueryStage.done, 'Done');
        return;
      }
    }
    */

    // ── Safety guard: emergency queries ──────────────────────────────────────
    final lowerMsg = correctedQuery.toLowerCase();
    final exactKeywords = [
      'seizure', 'convulsion', 'unconscious', 'chest pain',
      'overdose', 'poisoning', 'self-harm'
    ];
    if (exactKeywords.any(lowerMsg.contains)) {
      yield '⚠️ MEDICAL ALERT: This is a medical emergency. Call emergency services right now.';
      _emit(QueryStage.done, 'Done');
      return;
    }

    // ── Topic guard ───────────────────────────────────────────────────────────
    if (!_isOnTopic(correctedQuery)) {
      debugPrint('[ROUTER] Off-topic → blocked');
      yield 'No answer available.';
      _emit(QueryStage.done, 'Done');
      return;
    }

    // ── RAG Pipeline ──────────────────────────────────────────────────────────
    _emit(QueryStage.expanding, 'Expanding query...');
    _emit(QueryStage.embedding, 'Generating query vector...');
    _emit(QueryStage.searching, 'Searching knowledge base...');

    final result = await _retrieval.retrieve(correctedQuery);

    _emit(QueryStage.reranking, 'Ranking results...');

    final topChunk = result.chunks.isNotEmpty ? result.chunks.first : null;
    final topScore = topChunk?.score ?? 0.0;
    
    print('[ROUTER] Chunks retrieved: ${result.chunks.length}');
    if (topChunk != null) {
      print('[ROUTER] Top score: ${topScore.toStringAsFixed(3)}');
    }
    print('[ROUTER] Requires LLM: ${result.requiresLlm}');
    print('[ROUTER] Intent: ${result.intent}');

    lastIsFromKb = result.isFromKb;
    lastRequiresLlm = result.requiresLlm;
    lastRetrievedChunks = result.chunks;

    // ── Direct bypass for definition-type queries ──────────────────────────
    if (result.intent == QueryIntent.definition &&
        topChunk != null &&
        topScore >= 0.50 &&
        topChunk.chunk.text.length > 50) {
      print('[ROUTER] Direct bypass triggered → returning chunk text for definition query');
      final sourcesText = result.sources.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join('\n');
      yield '${_cleanChunkText(topChunk.chunk.text)}\n\n**Sources**\n\n$sourcesText';
      _emit(QueryStage.done, 'Done');
      return;
    }

    // ── Route Decision ────────────────────────────────────────────────────────
    if (!result.requiresLlm) {
      if (result.sources.isEmpty) {
        yield _buildNoAnswerResponse(correctedQuery);
      } else {
        final sourcesText = result.sources
            .asMap()
            .entries
            .map((e) => '${e.key + 1}. ${e.value}')
            .join('\n');
        yield '${result.content}\n\n**Sources**\n\n$sourcesText';
      }
      _emit(QueryStage.done, 'Done');
      return;
    }

    // ── LLM Synthesis ─────────────────────────────────────────────────────────
    _emit(QueryStage.generating, 'Synthesizing answer...',
        detail: 'Grounding response in retrieved context');

    final backend = await _resolveBackend();
    currentBackend.value = backend;

    final ragContext = result.context!;
    // FIX: Use correctedQuery (not originalQuery) for the LLM prompt
    print('[ROUTER] Using corrected query for LLM: "$correctedQuery"');
    final fullPrompt = _buildLlama3Prompt(ragContext, correctedQuery);

    debugPrint('[ROUTER] Using ${backend.name} backend');
    debugPrint('[ROUTER] Context chunks: ${result.chunks.length}');

    String fullLlmOutput = '';
    try {
      switch (backend) {
        case InferenceBackend.ollama:
          await for (final chunk
              in _streamOllama(correctedQuery, fullPrompt, history)) {
            fullLlmOutput += chunk;
            yield fullLlmOutput;
          }
          break;
        case InferenceBackend.onDevice:
          await for (final token
              in _onDevice.respond(correctedQuery, fullPrompt, 'banking')) {
            if (token.contains('🔄')) continue;
            fullLlmOutput += token;
            yield fullLlmOutput;
          }
          break;
      }

      // ── Post-process: sanitize then validate ─────────────────────────────
      final sanitized = OnDeviceInferenceService.sanitizeResponse(fullLlmOutput);
      debugPrint('[ROUTER] Raw length: ${fullLlmOutput.length} → Sanitized: ${sanitized.length}');

      final validated = _validateOutput(sanitized, ragContext);

      if (validated == 'No answer available.') {
        yield 'No answer available.';
      } else {
        final sourcesText = result.sources
            .asMap()
            .entries
            .map((e) => '${e.key + 1}. ${e.value}')
            .join('\n');
        yield '$validated\n\n**Sources**\n\n$sourcesText';
      }
    } catch (e) {
      yield '❌ System Error: $e';
    }

    _emit(QueryStage.done, 'Done');
  }

  // ── Prompt Builder (Llama 3 Instruct format) ──────────────────────────────
  /// Minimal, focused prompt. One instruction paragraph. No redundancy.
  String _buildLlama3Prompt(String context, String query) {
    return '<|begin_of_text|>'
        '<|start_header_id|>system<|end_header_id|>\n\n'
        'You are a helpful loan assistant. '
        'Answer ONLY from the context provided. '
        'Be direct and concise. Do not repeat yourself. '
        'If context does not contain the answer, say exactly: "No answer available."\n\n'
        'Context:\n$context'
        '<|eot_id|>'
        '<|start_header_id|>user<|end_header_id|>\n\n'
        'Question: $query'
        '<|eot_id|>'
        '<|start_header_id|>assistant<|end_header_id|>\n\n';
  }

  String _cleanChunkText(String raw) {
    return raw
        .replaceAll(RegExp(r'[■●•▪︎➤]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // ── Output Validator ──────────────────────────────────────────────────────
  String _validateOutput(String raw, String contextUsed) {
    // Guard: prompt template leakage
    final leakPatterns = [
      'INSTRUCTION:', 'CONTEXT:', 'Answer the user',
      'using ONLY the context', '<|start_header_id|>',
    ];
    for (final p in leakPatterns) {
      if (raw.contains(p)) {
        debugPrint('[VALIDATOR] ❌ Prompt leakage — discarding');
        return 'No answer available.';
      }
    }

    // Guard: still-looping content (sentences repeating)
    final sentences = raw
        .split(RegExp(r'[.!?]+'))
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.length > 15)
        .toList();

    final counts = <String, int>{};
    for (final s in sentences) {
      counts[s] = (counts[s] ?? 0) + 1;
    }
    final maxRepeat =
        counts.values.isEmpty ? 0 : counts.values.reduce((a, b) => a > b ? a : b);

    if (maxRepeat >= 2) {
      debugPrint('[VALIDATOR] ❌ Repetition detected (max=$maxRepeat) — discarding');
      return 'No answer available.';
    }

    // Guard: output longer than 3x the provided context
    if (raw.length > contextUsed.length * 3 && raw.length > 100) {
      debugPrint('[VALIDATOR] ❌ Output too long — discarding');
      return 'No answer available.';
    }

    if (raw.isEmpty || raw.toLowerCase().contains('no answer available')) {
      // ── HEURISTIC FALLBACK ────────────────────────────────────────────────
      // If the LLM refused but we had strong chunks, don't show the refusal.
      if (lastRetrievedChunks != null && lastRetrievedChunks!.isNotEmpty) {
        final top = lastRetrievedChunks!.first;
        if (top.score >= 0.5) {
          debugPrint('[VALIDATOR] 🛡️ LLM refused but Top Score is ${top.score}. Falling back to Top Chunk.');
          return top.chunk.text.trim();
        }
      }
      return 'No answer available.';
    }

    return raw.trim();
  }

  String _buildNoAnswerResponse(String query) {
    final isSummary = RegExp(
      r'summary|summarize|overview|explain all|tell me about everything',
      caseSensitive: false,
    ).hasMatch(query);

    if (isSummary) {
      return 'This knowledge base covers FAQ topics about '
          'Home Loans, Working Capital Loans, Unsecured Business Loans, '
          'and Loan Against Property. Try asking a specific question like '
          '"What is an EMI?" or "Who can avail a home loan?"';
    }

    return 'No answer available.';
  }

  Future<bool> _isOllamaReachable() async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none)) return false;
      final url = _settings.ollamaServerUrl;
      final probeDio = Dio();
      final resp = await probeDio.get('$url/api/tags',
          options: Options(
            sendTimeout: const Duration(milliseconds: 500),
            connectTimeout: const Duration(milliseconds: 500),
            receiveTimeout: const Duration(milliseconds: 500),
          ));
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
      String userMessage, String systemPrompt, List<ChatMessage> history) async* {
    _ollamaCancelToken = CancelToken();
    final url = _settings.ollamaServerUrl;
    final modelId = _settings.selectedModelId.value;
    final messages = [
      {'role': 'system', 'content': systemPrompt},
      ...history.map((m) => {
            'role': m.isUser == true ? 'user' : 'assistant',
            'content': m.content
          }),
      {'role': 'user', 'content': userMessage},
    ];
    try {
      final response = await _dio.post<ResponseBody>(
        '$url/api/chat',
        data: {
          'model': modelId.isEmpty ? 'llama3.2' : modelId,
          'messages': messages,
          'stream': true
        },
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
              if (contentEnd > contentStart)
                yield cleanLine.substring(contentStart, contentEnd);
            }
          }
        } catch (_) {}
      }
    } on DioException catch (e) {
      if (e.type != DioExceptionType.cancel)
        yield '\n[Ollama Error: ${e.message}]';
    }
  }

  void cancelCurrentRequest() {
    _ollamaCancelToken?.cancel('Cancelled by user');
    _ollamaCancelToken = null;
    _onDevice.cancelInference();
  }
}
