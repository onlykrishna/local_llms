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
import '../deterministic_kb_matcher.dart';
import '../../objectbox.g.dart';

enum InferenceBackend { ollama, onDevice }

enum QueryStage {
  expanding,    // "Expanding query..."
  embedding,    // "Generating query vector..."
  searching,    // "Searching knowledge base..."
  reranking,    // "Ranking results..."
  generating,   // "Generating answer..." (LLM path only)
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
  
  /// Stores the most recently retrieved chunks for programmatic citation generation.
  List<ScoredChunk>? lastRetrievedChunks;
  bool lastIsFromKb = false;
  bool lastRequiresLlm = false;

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
    // Also allow common greetings or short context-less probes
    if (q.length < 4) return true; 
    return _knownTopics.any((topic) => q.contains(topic));
  }
  
  final _deterministicMatcher = DeterministicKbMatcher();
  final _kbChunkCache = <String, DocumentChunk>{}; // id → chunk

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
    
    // Build KB cache once after a short delay to ensure ObjectBox is ready
    Future.delayed(const Duration(seconds: 2), () => _buildKbCache());
    
    return this;
  }

  void _buildKbCache() {
    try {
      final allKb = _retrieval.chunkBox.query(
        DocumentChunk_.isHardcoded.equals(true)
      ).build().find();
      
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
    _queryStatusController.add(QueryStatus(stage: stage, message: message, detail: detail));
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

    // ── PRIORITY 0: Deterministic rule match ─────────────────
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
      } else {
        debugPrint('[ROUTER] Deterministic matched $matchedId but not in cache!');
      }
    }

    // 1. SAFETY CHECK
    final lowerMsg = userMessage.toLowerCase();
    bool isEmergency = false;
    final tempRegex = RegExp(r'(\d{2,3}(\.\d)?)\s*(f|c|fever|temp)');
    for (final m in tempRegex.allMatches(lowerMsg)) {
      double val = double.tryParse(m.group(1) ?? '0') ?? 0;
      if (val >= 103) isEmergency = true;
    }
    final exactKeywords = ['seizure', 'convulsion', 'unconscious', 'chest pain', 'overdose', 'poisoning', 'self-harm'];
    if (exactKeywords.any(lowerMsg.contains)) isEmergency = true;

    if (isEmergency) {
      yield '⚠️ MEDICAL ALERT: This is a medical emergency. Call emergency services right now.';
      _emit(QueryStage.done, 'Done');
      return;
    }

    // ── PRIORITY 1: Topic Guard ──────────────────────────────
    if (!_isOnTopic(userMessage)) {
      debugPrint('[GUARD] Off-topic query blocked: "$userMessage"');
      yield 'No answer available.';
      _emit(QueryStage.done, 'Done');
      return;
    }

    // 2. RETRIEVAL PIPELINE WITH STATUS
    _emit(QueryStage.expanding, 'Expanding query...', detail: 'Detecting acronyms and terminology');
    final expanded = AcronymExpander.expand(userMessage);

    _emit(QueryStage.embedding, 'Generating query vector...', detail: 'Converting to 384-dimensional embedding');
    // Embedding happens inside retrieve(), but we emit stage here
    
    _emit(QueryStage.searching, 'Searching knowledge base...', detail: 'Scanning indexed facts and documents');
    final result = await _retrieval.retrieve(userMessage);

    _emit(QueryStage.reranking, 'Ranking results...', detail: 'Applying hybrid scoring and KB multipliers');
    // Reranking also happens inside retrieve()

    lastIsFromKb = result.isFromKb;
    lastRequiresLlm = result.requiresLlm;
    lastRetrievedChunks = result.chunks;

    // 3. DECISION HANDLING
    if (result.requiresLlm) {
      _emit(QueryStage.generating, 'Synthesizing answer...', detail: 'Grounding response in retrieved context');
      
      final backend = await _resolveBackend();
      currentBackend.value = backend;

      final ragContext = result.context!;
      final systemPrompt = _buildPrompt(ragContext, userMessage);

      String fullLlmOutput = '';
      try {
        switch (backend) {
          case InferenceBackend.ollama:
            await for (final chunk in _streamOllama(userMessage, systemPrompt, history)) {
              fullLlmOutput += chunk;
              yield fullLlmOutput; // Yielding partial for streaming UI
            }
            break;
          case InferenceBackend.onDevice:
            await for (final chunk in _onDevice.respond(userMessage, systemPrompt, 'general')) {
              if (chunk.contains('🔄')) continue;
              fullLlmOutput += chunk;
              yield fullLlmOutput;
            }
            break;
        }

        final finalAnswer = _validateLlmOutput(fullLlmOutput, ragContext);
        
        if (finalAnswer == 'No answer available.') {
          yield 'No answer available.';
        } else {
          final sourcesText = result.sources.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join('\n');
          yield '$finalAnswer\n\n**Sources**\n\n$sourcesText';
        }
      } catch (e) {
        yield '❌ System Error: $e';
      }
    } else {
      if (result.sources.isEmpty) {
        yield _buildNoAnswerResponse(userMessage);
      } else {
        final sourcesText = result.sources.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join('\n');
        yield '${result.content}\n\n**Sources**\n\n$sourcesText';
      }
    }

    _emit(QueryStage.done, 'Done');
  }

  String _buildNoAnswerResponse(String query) {
    final isSummaryRequest = RegExp(
      r'summary|summarize|overview|explain all|tell me about everything',
      caseSensitive: false,
    ).hasMatch(query);

    if (isSummaryRequest) {
      return 'This knowledge base covers specific FAQ topics about '
             'Home Loans, Working Capital Loans, Unsecured Business '
             'Loans, and Loan Against Property. Try asking a specific '
             'question like "What is an EMI?" or "Who can avail a '
             'home loan?"';
    }

    return 'No answer available.';
  }

  String _buildPrompt(String context, String query) {
    return '<|begin_of_text|>'
        '<|start_header_id|>system<|end_header_id|>\n\n'
        'Use only the text below. '
        'If the answer is not in the text, say: No answer available.\n\n'
        'TEXT:\n$context'
        '<|eot_id|>'
        '<|start_header_id|>user<|end_header_id|>\n\n'
        '$query'
        '<|eot_id|>'
        '<|start_header_id|>assistant<|end_header_id|>\n\n';
  }

  String _validateLlmOutput(String raw, String contextUsed) {
    // GUARD 1: Detect system prompt leakage
    final promptLeakPatterns = [
      'INSTRUCTION:',
      'CONTEXT:',
      'Answer the user',
      'using ONLY the context',
      'If the context doesn',
      '<|start_header_id|>',
    ];
    for (final pattern in promptLeakPatterns) {
      if (raw.contains(pattern)) {
        debugPrint('[VALIDATOR] ❌ Prompt leakage detected — discarding');
        return 'No answer available.';
      }
    }
    
    // GUARD 2: Detect repetition loops
    final sentences = raw
        .split(RegExp(r'[.!?]+'))
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.length > 15)
        .toList();
    
    final counts = <String, int>{};
    for (final s in sentences) {
      counts[s] = (counts[s] ?? 0) + 1;
    }
    final maxRepeat = counts.values.isEmpty 
        ? 0 
        : counts.values.reduce((a, b) => a > b ? a : b);
    
    if (maxRepeat >= 2) {
      debugPrint('[VALIDATOR] ❌ Repetition loop detected (max repeats: $maxRepeat) — discarding');
      return 'No answer available.';
    }
    
    // GUARD 3: Output longer than 3x context = hallucination
    if (raw.length > contextUsed.length * 3 && raw.length > 100) {
      debugPrint('[VALIDATOR] ❌ Output length ${raw.length} exceeds 3x context — discarding');
      return 'No answer available.';
    }
    
    // GUARD 4: Output contains "No answer available" buried 
    if (raw.toLowerCase().contains('no answer available') && raw.trim().length > 30) {
      debugPrint('[VALIDATOR] ❌ Mixed output with fallback — returning clean fallback');
      return 'No answer available.';
    }
    
    return raw.trim();
  }

  String _validateLlmResponse(String llmOutput, String ragContext, String query) {
    // Legacy method — redirected to new validator
    return _validateLlmOutput(llmOutput, ragContext);
  }

  Future<bool> _isOllamaReachable() async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none)) return false;
      final url = _settings.ollamaServerUrl;
      final probeDio = Dio();
      final resp = await probeDio.get('$url/api/tags', options: Options(
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

  Stream<String> _streamOllama(String userMessage, String systemPrompt, List<ChatMessage> history) async* {
    _ollamaCancelToken = CancelToken();
    final url = _settings.ollamaServerUrl;
    final modelId = _settings.selectedModelId.value;
    final messages = [
      {'role': 'system', 'content': systemPrompt},
      ...history.map((m) => {'role': m.isUser == true ? 'user' : 'assistant', 'content': m.content}),
      {'role': 'user', 'content': userMessage},
    ];
    try {
      final response = await _dio.post<ResponseBody>(
        '$url/api/chat',
        data: {'model': modelId.isEmpty ? 'llama3.2' : modelId, 'messages': messages, 'stream': true},
        options: Options(responseType: ResponseType.stream),
        cancelToken: _ollamaCancelToken,
      );
      await for (final chunk in response.data!.stream.map((bytes) => String.fromCharCodes(bytes)).where((s) => s.trim().isNotEmpty)) {
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
              if (contentEnd > contentStart) yield cleanLine.substring(contentStart, contentEnd);
            }
          }
        } catch (_) {}
      }
    } on DioException catch (e) {
      if (e.type != DioExceptionType.cancel) yield '\n[Ollama Error: ${e.message}]';
    }
  }

  void cancelCurrentRequest() {
    _ollamaCancelToken?.cancel('Cancelled by user');
    _ollamaCancelToken = null;
    _onDevice.cancelInference();
  }
}
