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

  bool _chunkAnswersQuery(String queryLower, DocumentChunk chunk) {
    final chunkLower = chunk.text.toLowerCase();
    
    // Simple subject extraction: remove question words
    final questionWords = ['what', 'is', 'are', 'how', 'does', 'do', 'can', 
                           'tell', 'me', 'about', 'explain', 'define', 'a', 
                           'the', 'for', 'of', 'in'];
    final queryWords = queryLower.split(RegExp(r'\W+'))
        .where((w) => w.length > 2 && !questionWords.contains(w))
        .toList();
    
    if (queryWords.isEmpty) return true;
    
    // Check keyword match ratio
    int matchCount = queryWords.where((w) => chunkLower.contains(w)).length;
    double matchRatio = matchCount / queryWords.length;
    if (matchRatio < 0.6) return false;

    // DEFINITION INTENT BLOCK
    final isDefinitionQuery = queryLower.contains('what is') || 
                              queryLower.contains('define') || 
                              queryLower.contains('meaning') ||
                              queryLower.contains('stands for');

    if (isDefinitionQuery) {
      final definitionalIndicators = [
        'stands for',
        'is defined as',
        'abbreviated as',
        'refers to',
        'full form',
        'short for',
      ];
      
      bool foundUnambiguousDefinition = false;
      for (final subject in queryWords) {
        final subjectPos = chunkLower.indexOf(subject);
        if (subjectPos == -1) continue;
        
        for (final indicator in definitionalIndicators) {
          final indicatorPos = chunkLower.indexOf(indicator);
          if (indicatorPos == -1) continue;
          
          // Use 80 chars proximity as requested
          if ((subjectPos - indicatorPos).abs() <= 80) {
            foundUnambiguousDefinition = true;
            break;
          }
        }
        if (foundUnambiguousDefinition) break;
      }
      return foundUnambiguousDefinition;
    }
    
    return true;
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
    bool bypassSuccess = false;
    if (result.intent == QueryIntent.definition &&
        topChunk != null &&
        topScore >= 0.50 &&
        topChunk.chunk.text.length > 50) {
      if (_chunkAnswersQuery(correctedQuery, topChunk.chunk)) {
        print('[ROUTER] Direct bypass triggered → returning chunk text for definition query');
        final sourcesText = _buildSourcesBlock(result.chunks.map((sc) => sc.chunk).toList());
        yield '${_cleanChunkText(topChunk.chunk.text)}$sourcesText';
        bypassSuccess = true;
      } else {
        // Chunk doesn't answer it — check chunks 2 and 3
        for (final chunk in result.chunks.skip(1)) {
          if (_chunkAnswersQuery(correctedQuery, chunk.chunk)) {
            print('[ROUTER] Found relevant definition in chunk ${result.chunks.indexOf(chunk) + 1}');
            final sourcesText = _buildSourcesBlock([chunk.chunk]);
            yield '${_cleanChunkText(chunk.chunk.text)}$sourcesText';
            bypassSuccess = true;
            break;
          }
        }
      }
      
      if (bypassSuccess) {
        _emit(QueryStage.done, 'Done');
        return;
      }
      print('[ROUTER] Definition bypass failed relevance check → falling through to LLM');
    }

    // ── Route Decision ────────────────────────────────────────────────────────
    if (!result.contextSufficient) {
      yield 'This information is not available in the provided documents.';
      _emit(QueryStage.done, 'Done');
      return;
    }

    bool requiresLlm = result.requiresLlm;
    if (!requiresLlm) {
      // Path A bypass check
      if (topChunk != null && _chunkAnswersQuery(correctedQuery, topChunk.chunk)) {
        if (result.sources.isEmpty) {
          yield _buildNoAnswerResponse(correctedQuery);
        } else {
          final sourcesText = _buildSourcesBlock(result.chunks.map((sc) => sc.chunk).toList());
          yield '${result.content}$sourcesText';
        }
        _emit(QueryStage.done, 'Done');
        return;
      } else {
        print('[ROUTER] Path A bypass failed relevance check → falling through to LLM');
        requiresLlm = true;
      }
    }

    // ── LLM Synthesis ─────────────────────────────────────────────────────────
    _emit(QueryStage.generating, 'Synthesizing answer...',
        detail: 'Grounding response in retrieved context');

    final backend = await _resolveBackend();
    currentBackend.value = backend;

    // Use the context from result (which we now ensure exists even for bypass)
    final int contextLimit = (result.intent == QueryIntent.definition) ? result.chunks.length : 3;
    final contextChunks = result.chunks.take(contextLimit).toList();
    final ragContext = contextChunks.map((s) => _cleanChunkText(s.chunk.text)).join('\n---\n');

    if (ragContext.isEmpty) {
      yield 'This information is not available in the provided documents.';
      _emit(QueryStage.done, 'Done');
      return;
    }
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

      final validated = _validateOutput(sanitized, result, correctedQuery);

      if (validated == 'No answer available.') {
        yield 'This information is not available in the provided documents.';
      } else {
        final usedChunks = lastRetrievedChunks?.map((sc) => sc.chunk).toList() ?? [];
        final sourcesText = _buildSourcesBlock(usedChunks);
        yield '$validated$sourcesText';
      }
    } catch (e) {
      yield '❌ System Error: $e';
    }

    _emit(QueryStage.done, 'Done');
  }

  // ── Prompt Builder (Llama 3 Instruct format) ──────────────────────────────
  /// Minimal, focused prompt. One instruction paragraph. No redundancy.
  String _buildLlama3Prompt(String context, String query) {
    // Filter empty lines from context before sending to LLM
    final cleanContext = context
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .join('\n');

    if (cleanContext.isEmpty) {
      print('[ROUTER] WARNING: Empty context after cleaning');
    }

    return '<|begin_of_text|>'
        '<|start_header_id|>system<|end_header_id|>\n\n'
        'You are a document answer extractor. You will be given context passages retrieved from \n'
        'official PDF documents. Your ONLY job is to answer the user\'s question using information \n'
        'explicitly present in the provided context. \n'
        'Rules you must follow without exception:\n'
        '- ONLY use information from the <context> blocks below.\n'
        '- If the context contains PARTIAL information relevant to the question, \n'
        '  provide that partial information clearly stating it is from the documents.\n'
        '- If the context contains ZERO relevant information, respond with exactly:\n'
        '  \'This information is not available in the provided documents.\'\n'
        '- Do NOT refuse to answer if ANY relevant information exists in context.\n'
        '- Do NOT use your training knowledge, general knowledge, or make inferences.\n'
        '- Do NOT add explanations, examples, or elaborations beyond what the context states.\n'
        '- Do NOT say phrases like \'Based on my knowledge\' or \'Generally speaking\'.\n'
        '- Quote or closely paraphrase the context. Do not invent numbers, dates, or conditions.\n'
        '<|eot_id|>'
        '<|start_header_id|>user<|end_header_id|>\n\n'
        'STRICT INSTRUCTION: Only answer from the context below. \n'
        'Context is from official PDFs. No outside knowledge allowed.\n'
        'If the context does not contain the answer, say: \n'
        '\'This information is not available in the provided documents.\'\n\n'
        '<context>\n'
        '$cleanContext\n'
        '</context>\n\n'
        'Question: $query\n'
        'Important: If the context contains any information related to the question, \n'
        'use it. Only say not available if context has zero relevant content.\n'
        'Answer (from context only):'
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
  // RULES: Only discard if prompt leaked into output, or sentences are looping.
  // NEVER discard based on response length — a 390-char answer is perfectly valid.
  String _validateOutput(String output, RagResult ragResult, String correctedQuery) {
    // Guard 1: Stop-token cleanup (strip everything after model stop tokens)
    const stopTokens = ['<|eot_id|>', '<|end_of_text|>', '<|im_end|>', '[/INST]'];
    String cleaned = output;
    for (final stop in stopTokens) {
      if (cleaned.contains(stop)) {
        cleaned = cleaned.substring(0, cleaned.indexOf(stop));
      }
    }
    cleaned = cleaned.trim();

    // Guard 2: Prompt template leakage
    final leakPatterns = [
      'INSTRUCTION:', 'CONTEXT:', 'Answer the user',
      'using ONLY the context', '<|start_header_id|>',
    ];
    for (final p in leakPatterns) {
      if (cleaned.contains(p)) {
        debugPrint('[VALIDATOR] ❌ Prompt leakage — discarding');
        return _heuristicFallback(ragResult, correctedQuery);
      }
    }

    // Guard 3: Sentence-level repetition loops
    final sentences = cleaned
        .split(RegExp(r'[.!?]+'))
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.length > 15)
        .toList();
    final counts = <String, int>{};
    for (final s in sentences) {
      counts[s] = (counts[s] ?? 0) + 1;
    }
    final maxRepeat = counts.values.isEmpty ? 0 : counts.values.reduce((a, b) => a > b ? a : b);
    if (maxRepeat >= 3) {
      debugPrint('[VALIDATOR] ❌ Repetition loop detected (max=$maxRepeat) — discarding');
      return _heuristicFallback(ragResult, correctedQuery);
    }

    // Guard 4: LLM explicitly says no answer
    if (cleaned.isEmpty || cleaned.toLowerCase().contains('no answer available') || cleaned.toLowerCase().contains('not available in the provided documents')) {
      debugPrint('[VALIDATOR] LLM said no answer — trying heuristic fallback');
      return _heuristicFallback(ragResult, correctedQuery);
    }

    // Hallucination leak check — catch self-referential LLM language
    final hallucinationPhrases = [
      'based on my knowledge',
      'generally speaking',
      'typically',
      'in most cases',
      'as an ai',
      'i believe',
      'you should consult',
      'please note that',
      'it is important to',
    ];
    final lowerOutput = cleaned.toLowerCase();
    for (final phrase in hallucinationPhrases) {
      if (lowerOutput.contains(phrase)) {
        // LLM leaked self-generated content — fall back to raw chunk
        return _heuristicFallback(ragResult, correctedQuery);
      }
    }

    // Grounding check — verify output contains at least one key term from ANY chunk
    final outputWords = cleaned.toLowerCase()
        .split(RegExp(r'\W+'))
        .where((w) => w.length > 4)
        .toSet();
    
    bool hasGrounding = false;
    for (final chunk in ragResult.chunks) {
      final chunkWords = chunk.chunk.text
          .toLowerCase()
          .split(RegExp(r'\W+'))
          .where((w) => w.length > 4)
          .toSet();
      final overlap = chunkWords.intersection(outputWords).length;
      if (overlap >= 3) {
        hasGrounding = true;
        break;
      }
    }
    
    if (!hasGrounding) {
      debugPrint('[VALIDATOR] ❌ No grounding overlap with ANY chunk — discarding');
      return _heuristicFallback(ragResult, correctedQuery);
    }

    debugPrint('[VALIDATOR] ✅ Answer accepted (${cleaned.length} chars)');
    return cleaned;
  }

  String _heuristicFallback(RagResult ragResult, String correctedQuery) {
    final queryLower = correctedQuery.toLowerCase();
    
    // Extract subject words
    const stopWords = {'what', 'is', 'are', 'how', 'does', 'do', 'can',
                       'tell', 'me', 'about', 'explain', 'define', 
                       'a', 'the', 'for', 'of', 'in', 'an', 'and'};
    final subjectWords = queryLower
        .split(RegExp(r'\W+'))
        .where((w) => w.length > 1 && !stopWords.contains(w))
        .toList();
    
    // Step 1: find a chunk that contains ALL subject words
    for (final chunk in ragResult.chunks) {
      final chunkLower = chunk.chunk.text.toLowerCase();
      if (subjectWords.every((w) => chunkLower.contains(w))) {
        return _cleanChunkText(chunk.chunk.text);
      }
    }
    
    // Step 2: find a chunk containing MOST subject words (60%)
    for (final chunk in ragResult.chunks) {
      final chunkLower = chunk.chunk.text.toLowerCase();
      final matchCount = subjectWords
          .where((w) => chunkLower.contains(w)).length;
      if (subjectWords.isEmpty || 
          matchCount / subjectWords.length >= 0.6) {
        return _cleanChunkText(chunk.chunk.text);
      }
    }
    
    // Step 3: return top chunk text directly (better than "not available"
    // when we know context exists)
    if (ragResult.chunks.isNotEmpty) {
      final top = ragResult.chunks.first;
      return _cleanChunkText(top.chunk.text);
    }
    
    return 'This information is not available in the provided documents.';
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

    return 'This information is not available in the provided documents.';
  }

  String _buildSourcesBlock(List<DocumentChunk> chunks) {
    if (chunks.isEmpty) return '';
    
    String _toFilename(String? source) {
      if (source == null) return 'document.pdf';
      final s = source.toLowerCase().trim();
      if (s.contains('home_loan') || s.contains('home loan'))
        return 'home_loan_faqs.pdf';
      if (s.contains('working_capital') || s.contains('working capital'))
        return 'working_capital_loan_faqs.pdf';
      if (s.contains('loan_against') || s.contains('loan against'))
        return 'loan_against_property_faqs.pdf';
      if (s.contains('unsecured') || s.contains('business'))
        return 'unsecured_business_loan_faqs.pdf';
      if (s.endsWith('.pdf')) return source;
      return 'knowledge_base.pdf';
    }
    
    // Collect unique filenames only — NO excerpts
    final seen = <String>{};
    final filenames = <String>[];
    for (final chunk in chunks) {
      final name = _toFilename(chunk.source);
      if (seen.add(name)) filenames.add(name);
    }
    
    if (filenames.isEmpty) return '';
    
    final buffer = StringBuffer('\n\n**Sources:**\n');
    for (int i = 0; i < filenames.length; i++) {
      buffer.write('${i + 1}. ${filenames[i]}\n');
    }
    return buffer.toString().trimRight();
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
