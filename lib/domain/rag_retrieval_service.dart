import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart' hide Condition;
import '../core/embedding_service.dart';
import '../data/document_chunk.dart';
import 'services/acronym_expander.dart';
import 'services/fuzzy_query_corrector.dart';
import '../objectbox.g.dart';

// ── Query Intent ────────────────────────────────────────────────────────────
enum QueryIntent { documents, fees, eligibility, interest, tenure, process, definition, other }

class ScoredChunk {
  final DocumentChunk chunk;
  final double score;
  final double cosine;
  final double kw;
  final double boost;

  ScoredChunk({
    required this.chunk,
    required this.score,
    required this.cosine,
    required this.kw,
    required this.boost,
  });
}

class RagResult {
  final bool requiresLlm;
  final String content;
  final List<String> sources;
  final bool isFromKb;
  final String? context;
  final List<ScoredChunk> chunks;
  final QueryIntent intent;
  final bool contextSufficient;

  RagResult({
    required this.requiresLlm,
    required this.content,
    required this.sources,
    required this.chunks,
    this.isFromKb = false,
    this.context,
    this.intent = QueryIntent.other,
    this.contextSufficient = false,
  });

  factory RagResult.directBypass(String content, List<String> sources, List<ScoredChunk> chunks,
          {bool isFromKb = false, QueryIntent intent = QueryIntent.other, String? context}) =>
      RagResult(
          requiresLlm: false,
          content: content,
          sources: sources,
          chunks: chunks,
          isFromKb: isFromKb,
          intent: intent,
          context: context,
          contextSufficient: true);

  factory RagResult.llmGrounded(String context, List<String> sources, List<ScoredChunk> chunks,
          {QueryIntent intent = QueryIntent.other, bool contextSufficient = true}) =>
      RagResult(
          requiresLlm: true,
          content: '',
          context: context,
          sources: sources,
          chunks: chunks,
          intent: intent,
          contextSufficient: contextSufficient);

  factory RagResult.noAnswer() =>
      RagResult(requiresLlm: false, content: 'No answer available.', sources: [], chunks: [], contextSufficient: false);
}

class RagRetrievalService extends GetxService {
  final Store store;
  final EmbeddingService embeddingService;
  late final Box<DocumentChunk> chunkBox;

  // ── Document scope map ────────────────────────────────────────────────────
  static const Map<String, String> _documentScope = {
    'home loan': 'home_loan_faqs',
    'working capital': 'working_capital_loan_faqs',
    'unsecured': 'unsecured_business_loan_faqs',
    'business loan': 'unsecured_business_loan_faqs',
    'lap': 'loan_against_property_faqs',
    'loan against property': 'loan_against_property_faqs',
    'property loan': 'loan_against_property_faqs',
  };

  // ── Intent keyword BOOSTS (additive only — never block answers) ───────────
  static const Map<QueryIntent, List<String>> _intentKeywords = {
    QueryIntent.documents: [
      'kyc', 'pan', 'aadhaar', 'bank statement', 'itr',
      'document', 'proof', 'identity', 'address',
      'gst', 'balance sheet', 'passport', 'photograph', 'form',
    ],
    QueryIntent.fees: ['fee', 'charge', 'processing', 'cost', 'payment', 'applicable'],
    QueryIntent.eligibility: ['age', 'income', 'salary', 'cibil', 'score', 'eligible', 'criteria'],
    QueryIntent.interest: ['%', 'percent', 'rate', 'interest', 'roi', 'pa'],
    QueryIntent.tenure: ['tenure', 'year', 'month', 'duration', 'period', 'repay'],
    QueryIntent.definition: ['loan', 'used', 'purpose', 'means', 'refers', 'is a'],
    QueryIntent.process: ['apply', 'process', 'step', 'procedure', 'how', 'application'],
    QueryIntent.other: [],
  };

  RagRetrievalService(this.store, this.embeddingService) {
    chunkBox = store.box<DocumentChunk>();
  }

  // ── Intent Detection ───────────────────────────────────────────────────────
  QueryIntent detectIntent(String query) {
    final q = query.toLowerCase();
    if (q.contains('document') || q.contains('paper') || q.contains('kyc') ||
        q.contains('what documents') || q.contains('which documents') ||
        q.contains('require') || (q.contains('need') && q.contains('loan'))) {
      return QueryIntent.documents;
    }
    if (q.contains('fee') || q.contains('charge') || q.contains('cost') || q.contains('processing')) {
      return QueryIntent.fees;
    }
    if (q.contains('eligib') || q.contains('qualify') || q.contains('criteria') || q.contains('who can')) {
      return QueryIntent.eligibility;
    }
    if (q.contains('interest') || q.contains(' rate') || q.contains('roi')) {
      return QueryIntent.interest;
    }
    if (q.contains('tenure') || q.contains('duration') || q.contains('how long')) {
      return QueryIntent.tenure;
    }
    if (q.contains('how to apply') || q.contains('process') || q.contains('steps')) {
      return QueryIntent.process;
    }
    if (q.contains('what is') || q.contains('define') || q.contains('meaning') || q.contains('explain')) {
      return QueryIntent.definition;
    }
    return QueryIntent.other;
  }

  // ── Header/Title Chunk Detection ───────────────────────────────────────────
  // Header chunks (like "HOME LOAN FAQ HOME LOAN FAQ") have no useful content.
  bool _isHeaderChunk(String text) {
    final t = text.trim();
    if (t.length < 40) return true; // Too short to be an answer
    if (t == t.toUpperCase() && t.length < 100) return true; // ALL CAPS short text
    // Detect repeated content (e.g. "Foo Bar Foo Bar")
    if (t.length > 20) {
      final half = t.substring(0, t.length ~/ 2).trim();
      if (half.length > 10 && t.contains(half) &&
          t.indexOf(half) != t.lastIndexOf(half)) {
        return true;
      }
    }
    return false;
  }

  // ── Keyword boost (ADDITIVE only — keywords never block answers) ───────────
  double _computeKeywordBoost(String chunkText, QueryIntent intent) {
    if (intent == QueryIntent.other) return 1.0;
    final text = chunkText.toLowerCase();
    final keywords = _intentKeywords[intent] ?? [];
    final matches = keywords.where((k) => text.contains(k)).length;
    if (matches == 0) return 1.0;   // no boost — answer is NOT blocked
    if (matches == 1) return 1.20;
    if (matches == 2) return 1.35;
    return 1.50;                    // strong boost for 3+ keyword matches
  }

  // ── Deduplication by contentHash ──────────────────────────────────────────
  List<ScoredChunk> _deduplicateChunks(List<ScoredChunk> chunks) {
    final seen = <String>{};
    final unique = <ScoredChunk>[];
    for (final sc in chunks) {
      final key = sc.chunk.contentHash.isNotEmpty
          ? sc.chunk.contentHash
          : sc.chunk.text.substring(0, min(100, sc.chunk.text.length));
      if (!seen.contains(key)) {
        seen.add(key);
        unique.add(sc);
      } else {
        debugPrint('[RAG] Duplicate chunk removed: ${key.substring(0, min(30, key.length))}');
      }
    }
    print('[RAG] After dedup: ${unique.length} (removed ${chunks.length - unique.length} duplicates)');
    return unique;
  }

  String? resolveDocumentScope(String query) {
    final lower = query.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), '');
    for (final entry in _documentScope.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }
    return null;
  }

  Future<RagResult> retrieve(String rawQuery) async {
    final totalChunks = chunkBox.count();
    print('[RAG] Total chunks in DB: $totalChunks');
    print('[RAG] Raw Query: $rawQuery');

    if (totalChunks == 0) {
      print('[RAG] ERROR: ObjectBox is EMPTY');
      return RagResult.noAnswer();
    }

    final typoCorrected = FuzzyQueryCorrector.correct(rawQuery);
    final expanded = AcronymExpander.expand(typoCorrected);
    final resolvedScope = resolveDocumentScope(typoCorrected);
    final intent = detectIntent(typoCorrected);

    if (typoCorrected != rawQuery.toLowerCase().trim()) {
      print('[RAG] Corrected query: "$typoCorrected"');
    }
    if (resolvedScope != null) {
      print('[RAG] Scope resolved: $resolvedScope');
    }
    print('[RAG] Intent detected: $intent');

    // ── Vector Search with Intent Augmentation and Fallback ─────────────────
    final allCandidates = await _vectorSearchWithFallback(expanded, intent, resolvedScope);

    if (allCandidates.isEmpty) return RagResult.noAnswer();

    // ── Step 3: Filter header/title chunks ──────────────────────────────────
    final contentChunks = allCandidates.where((sc) => !_isHeaderChunk(sc.chunk.text)).toList();
    print('[RAG] Filtered ${allCandidates.length - contentChunks.length} header/title chunks');

    // Fall back to all chunks if header filter removed everything
    final candidates = contentChunks.isNotEmpty ? contentChunks : allCandidates;

    // ── Step 4: Deduplicate ─────────────────────────────────────────────────
    final deduped = _deduplicateChunks(candidates);
    if (deduped.isEmpty) return RagResult.noAnswer();

    // ── Step 5: Apply keyword BOOST (additive only — never blocks answers) ──
    final boosted = deduped.map((sc) {
      final kwBoost = _computeKeywordBoost(sc.chunk.text, intent);
      final tagBoost = _tagBoost(sc.chunk, typoCorrected);
      final newScore = sc.score * kwBoost + tagBoost;
      return ScoredChunk(
          chunk: sc.chunk, score: newScore, cosine: sc.cosine, kw: kwBoost, boost: tagBoost);
    }).toList();

    boosted.sort((a, b) => b.score.compareTo(a.score));

    // Log top 3 for debugging
    for (int i = 0; i < min(3, boosted.length); i++) {
      final c = boosted[i];
      print('[RAG] Score: ${c.score.toStringAsFixed(3)} | ${c.chunk.text.substring(0, min(60, c.chunk.text.length))}');
    }

    final top = boosted.first;

    // ── Step 6: Threshold check ─────────────────────────────────────────────
    final threshold = 0.40;
    print('[RAG] Top score: ${top.score.toStringAsFixed(3)} | Threshold: $threshold | Match: ${top.score >= threshold}');

    // If the top chunk score is below 0.40 even after keyword boost,
    // return a RagResult with a special flag: contextSufficient = false
    // The router must check this flag and return "not available" without calling LLM.
    final bool contextSufficient = top.score >= threshold;

    if (!contextSufficient) {
      print('[RAG] → NO ANSWER (below threshold) contextSufficient = false');
      return RagResult.llmGrounded(
        '', 
        [], 
        boosted.take(3).toList(), 
        intent: intent, 
        contextSufficient: false
      );
    }

    // ── Step 8: Build context for ALL paths (including bypass fallback) ──
    final int chunkLimit = (intent == QueryIntent.definition) ? 5 : 3;
    
    var scoredChunks = boosted.where((s) => s.score >= threshold).toList();
    
    if (intent == QueryIntent.definition) {
      final definitionalPhrases = [
        'stands for', 'is defined as', 'abbreviated as',
        'refers to', 'full form', 'short for',
      ];
      
      // Partition: definition chunks first, others second
      final defChunks = scoredChunks.where((c) => 
          definitionalPhrases.any((p) => 
              c.chunk.text.toLowerCase().contains(p))).toList();
      final otherChunks = scoredChunks.where((c) => 
          !definitionalPhrases.any((p) => 
              c.chunk.text.toLowerCase().contains(p))).toList();
      
      scoredChunks = [...defChunks, ...otherChunks];
    }

    final selected = scoredChunks.take(chunkLimit).toList();
    // Filter out empty/whitespace chunks from LLM context
    final validSelected = selected.where((s) => s.chunk.text.trim().length > 20).toList();
    final context = validSelected.map((s) => _sanitizeChunk(s.chunk.text)).join('\n---\n');

    print('[RAG] Final chunks: ${validSelected.length}');

    // ── Step 9: High-confidence bypass → serve directly ────────────────────
    final bypassThreshold = resolvedScope != null ? 0.65 : 0.85;
    if (top.score >= bypassThreshold) {
      print('[RAG] → HIGH CONFIDENCE BYPASS (score ${top.score.toStringAsFixed(2)})');
      return RagResult.directBypass(
        _sanitizeChunk(top.chunk.text),
        _buildUniqueSources(validSelected),
        validSelected,
        isFromKb: top.chunk.isHardcoded,
        intent: intent,
        context: context,
      );
    }

    return RagResult.llmGrounded(
      context,
      _buildUniqueSources(validSelected),
      validSelected,
      intent: intent,
      contextSufficient: contextSufficient,
    );
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
    
    // The chunk must contain AT LEAST 60% of the meaningful query words
    if (queryWords.isEmpty) return true;
    
    int matchCount = queryWords.where((w) => chunkLower.contains(w)).length;
    double matchRatio = matchCount / queryWords.length;
    
    return matchRatio >= 0.6;
  }

  String _augmentQueryForIntent(String query, QueryIntent intent) {
    switch (intent) {
      case QueryIntent.documents:
        return '$query required documents list checklist KYC identity proof';
      case QueryIntent.fees:
        return '$query processing fee charges cost amount';
      case QueryIntent.eligibility:
        return '$query eligible criteria age income salary requirement';
      case QueryIntent.definition:
        return '$query meaning definition what is description overview';
      default:
        return query;
    }
  }

  Future<List<ScoredChunk>> _vectorSearchWithFallback(
      String query, QueryIntent intent, String? scope) async {
    
    // Primary search with augmented query
    final augmented = _augmentQueryForIntent(query, intent);
    var results = await _vectorSearch(augmented, scope, 20);
    
    var filtered = results.where((sc) => !_isHeaderChunk(sc.chunk.text)).toList();
    filtered = _deduplicateChunks(filtered);
    
    // Check if any result actually answers the query
    bool hasRelevant = filtered.any((c) => _chunkAnswersQuery(query.toLowerCase(), c.chunk));
    
    if (!hasRelevant) {
      print('[RAG] No relevant chunks found in primary search. Running secondary search...');
      // Secondary search: drop scope restriction, use raw query
      results = await _vectorSearch(query, null, 20);
      filtered = results.where((sc) => !_isHeaderChunk(sc.chunk.text)).toList();
      filtered = _deduplicateChunks(filtered);
    }
    
    return filtered;
  }

  // ── Internal: vector search helper ────────────────────────────────────────
  Future<List<ScoredChunk>> _vectorSearch(String query, String? scope, int limit) async {
    final queryEmbedding = await embeddingService.embed(query);

    Condition<DocumentChunk> condition = DocumentChunk_.embedding.nearestNeighborsF32(queryEmbedding, limit);
    if (scope != null) {
      condition = condition.and(DocumentChunk_.sourceDocumentTag.contains(scope));
    }

    final dbQuery = chunkBox.query(condition).build();
    final results = dbQuery.findWithScores();
    dbQuery.close();

    return results.map((result) {
      final chunk = result.object;
      final emb = chunk.embedding;
      final cosine = (emb != null && emb.isNotEmpty)
          ? _cosineSimilarity(queryEmbedding, emb)
          : (1.0 - result.score);
      double score = cosine * 0.45;
      if (chunk.isHardcoded) score *= 1.5;
      return ScoredChunk(chunk: chunk, score: score, cosine: cosine, kw: 1.0, boost: 0.0);
    }).toList();
  }

  List<String> _buildUniqueSources(List<ScoredChunk> chunks) {
    final seen = <String>{};
    final sources = <String>[];
    for (final s in chunks) {
      final label = _formatSource(s.chunk);
      if (!seen.contains(label)) {
        seen.add(label);
        sources.add(label);
      }
    }
    return sources;
  }

  double _tagBoost(DocumentChunk chunk, String query) {
    if (chunk.tags == null) return 0.0;
    return query.toLowerCase().contains(chunk.tags!.toLowerCase()) ? 0.05 : 0.0;
  }

  String _formatSource(DocumentChunk chunk) {
    String fileName = chunk.isHardcoded ? 'Knowledge Base — ${chunk.category ?? "FAQ"}' : (chunk.source ?? "Document");
    String excerpt = chunk.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (excerpt.length > 80) {
      excerpt = excerpt.substring(0, 80) + '...';
    }
    return '• [$fileName] — "$excerpt"';
  }

  String _sanitizeChunk(String raw) {
    return raw.replaceAll(RegExp(r'[■●•▪︎➤]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;
    double dot = 0, normA = 0, normB = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    final denom = sqrt(normA) * sqrt(normB);
    return denom == 0 ? 0.0 : (dot / denom).clamp(-1.0, 1.0);
  }
}
