import 'dart:math';

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

  RagResult({
    required this.requiresLlm,
    required this.content,
    required this.sources,
    required this.chunks,
    this.isFromKb = false,
    this.context,
    this.intent = QueryIntent.other,
  });

  factory RagResult.directBypass(String content, List<String> sources, List<ScoredChunk> chunks, {bool isFromKb = false, QueryIntent intent = QueryIntent.other}) =>
      RagResult(requiresLlm: false, content: content, sources: sources, chunks: chunks, isFromKb: isFromKb, intent: intent);

  factory RagResult.llmGrounded(String context, List<String> sources, List<ScoredChunk> chunks, {QueryIntent intent = QueryIntent.other}) =>
      RagResult(requiresLlm: true, content: '', context: context, sources: sources, chunks: chunks, intent: intent);

  factory RagResult.noAnswer() => RagResult(requiresLlm: false, content: 'No answer available.', sources: [], chunks: []);
}

class RagRetrievalService extends GetxService {
  final Store store;
  final EmbeddingService embeddingService;
  late final Box<DocumentChunk> chunkBox;

  static const Map<String, String> _documentScope = {
    'home loan': 'home_loan_faqs',
    'working capital': 'working_capital_loan_faqs',
    'unsecured': 'unsecured_business_loan_faqs',
    'business loan': 'unsecured_business_loan_faqs',
    'lap': 'loan_against_property_faqs',
    'property loan': 'loan_against_property_faqs',
  };

  // ── Mandatory keywords per intent ──────────────────────────────────────────
  static const Map<QueryIntent, List<String>> _mandatoryKeywords = {
    QueryIntent.documents: [
      'kyc', 'pan', 'aadhaar', 'bank statement', 'itr',
      'document', 'proof', 'identity', 'address',
      'financial statement', 'gst', 'balance sheet',
      'passport', 'photograph', 'application form', 'form',
    ],
    QueryIntent.fees: [
      'fee', 'charge', 'processing', 'cost', 'payment', 'applicable',
    ],
    QueryIntent.eligibility: [
      'age', 'income', 'salary', 'cibil', 'score',
      'eligible', 'criteria', 'minimum', 'maximum',
    ],
    QueryIntent.interest: [
      '%', 'percent', 'rate', 'interest', 'roi', 'pa',
    ],
    QueryIntent.tenure: [
      'tenure', 'year', 'month', 'duration', 'period', 'repay',
    ],
    QueryIntent.definition: [
      'loan', 'used', 'purpose', 'means', 'refers', 'is a', 'are',
    ],
    QueryIntent.process: [
      'apply', 'process', 'step', 'procedure', 'how', 'application',
    ],
    QueryIntent.other: [],
  };

  RagRetrievalService(this.store, this.embeddingService) {
    chunkBox = store.box<DocumentChunk>();
  }

  // ── Intent Detection ───────────────────────────────────────────────────────
  QueryIntent detectIntent(String query) {
    final q = query.toLowerCase();
    if (q.contains('document') || q.contains('paper') ||
        q.contains('require') || q.contains('need') ||
        q.contains('submit') || q.contains('kyc') ||
        q.contains('what documents') || q.contains('which documents')) {
      return QueryIntent.documents;
    }
    if (q.contains('fee') || q.contains('charge') ||
        q.contains('cost') || q.contains('processing')) {
      return QueryIntent.fees;
    }
    if (q.contains('eligib') || q.contains('qualify') ||
        q.contains('criteria') || q.contains('who can')) {
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
    if (q.contains('what is') || q.contains('define') ||
        q.contains('meaning') || q.contains('explain')) {
      return QueryIntent.definition;
    }
    return QueryIntent.other;
  }

  // ── Intent-based Re-ranking ────────────────────────────────────────────────
  List<ScoredChunk> _reRankByIntent(List<ScoredChunk> chunks, QueryIntent intent) {
    if (intent == QueryIntent.other) return chunks;
    final keywords = _mandatoryKeywords[intent] ?? [];
    if (keywords.isEmpty) return chunks;

    final matching = chunks.where((c) {
      final text = (c.chunk.text + ' ' + c.chunk.question).toLowerCase();
      return keywords.any((kw) => text.contains(kw));
    }).toList();

    if (matching.isNotEmpty) {
      print('[RAG] Intent: $intent → Found ${matching.length} keyword-matching chunks');
      return matching;
    }

    print('[RAG] Intent: $intent → No chunks match mandatory keywords → returning all for fallback');
    // Return all instead of empty to avoid false "no answer" — let threshold decide
    return chunks;
  }

  // ── Deduplication ──────────────────────────────────────────────────────────
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
        print('[RAG] Duplicate chunk removed: ${key.substring(0, min(30, key.length))}');
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

    if (totalChunks == 0) {
      print('[RAG] ERROR: ObjectBox is EMPTY');
      return RagResult.noAnswer();
    }

    final queryEmbedding = await embeddingService.embed(expanded);

    // ── Vector Query ───────────────────────────────────────────────────────
    Condition<DocumentChunk> condition = DocumentChunk_.embedding.nearestNeighborsF32(queryEmbedding, 40);
    if (resolvedScope != null) {
      condition = condition.and(DocumentChunk_.sourceDocumentTag.contains(resolvedScope));
    }
    final dbQuery = chunkBox.query(condition).build();
    final rawResults = dbQuery.findWithScores();
    dbQuery.close();

    print('[RAG] Raw results: ${rawResults.length}');

    if (rawResults.isEmpty) return RagResult.noAnswer();

    // ── Score ──────────────────────────────────────────────────────────────
    final scored = rawResults.map((result) {
      final chunk = result.object;
      final emb = chunk.embedding;
      double cosine = (emb != null && emb.isNotEmpty)
          ? _cosineSimilarity(queryEmbedding, emb)
          : (1.0 - result.score);
      final kwBoost = _computeKeywordBoost(chunk.text + ' ' + chunk.question, expanded);
      final tagBoost = _tagBoost(chunk, expanded);
      double score = (cosine * 0.45) * kwBoost + (tagBoost * 0.20);
      if (chunk.isHardcoded) score *= 1.5;
      return ScoredChunk(chunk: chunk, score: score, cosine: cosine, kw: kwBoost, boost: tagBoost);
    }).toList();

    // ── Deduplicate ────────────────────────────────────────────────────────
    final deduped = _deduplicateChunks(scored);
    deduped.sort((a, b) => b.score.compareTo(a.score));

    // ── Intent Re-ranking ──────────────────────────────────────────────────
    final reRanked = _reRankByIntent(deduped, intent);
    if (reRanked.isEmpty) return RagResult.noAnswer();
    reRanked.sort((a, b) => b.score.compareTo(a.score));

    final top = reRanked.first;
    final threshold = resolvedScope != null ? 0.25 : 0.40;
    print('[RAG] Top score: ${top.score.toStringAsFixed(3)} | Threshold: $threshold | Match: ${top.score >= threshold}');

    if (top.score < threshold) {
      print('[RAG] → NO ANSWER (below threshold)');
      return RagResult.noAnswer();
    }

    // ── High-confidence Direct Bypass ──────────────────────────────────────
    final double bypassThreshold = resolvedScope != null ? 0.65 : 0.85;
    if (top.score >= bypassThreshold) {
      print('[RAG] → HIGH CONFIDENCE BYPASS (score ${top.score.toStringAsFixed(2)})');
      return RagResult.directBypass(
        _sanitizeChunk(top.chunk.text),
        _buildUniqueSources(reRanked.take(3).toList()),
        reRanked.take(3).toList(),
        isFromKb: top.chunk.isHardcoded,
        intent: intent,
      );
    }

    // ── LLM Grounding ──────────────────────────────────────────────────────
    final selected = reRanked.where((s) => s.score >= threshold).take(3).toList();
    final context = selected.map((s) => _sanitizeChunk(s.chunk.text)).join('\n\n');

    return RagResult.llmGrounded(
      context,
      _buildUniqueSources(selected),
      selected,
      intent: intent,
    );
  }

  /// Build unique source citations — no duplicates from same page
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

  double _computeKeywordBoost(String chunkText, String query) {
    double boost = 1.0;
    final qLower = query.toLowerCase();
    final cLower = chunkText.toLowerCase();
    for (final intent in {
      'documents': ['document', 'paper', 'require', 'kyc', 'proof'],
      'eligibility': ['eligible', 'criteria', 'qualify', 'income'],
      'interest': ['interest', 'rate', 'roi'],
      'emi': ['emi', 'monthly', 'installment'],
      'tenure': ['tenure', 'year', 'month'],
    }.entries) {
      if (qLower.contains(intent.key)) {
        final matches = intent.value.where((kw) => cLower.contains(kw)).length;
        if (matches > 0) boost += (matches * 0.25);
      }
    }
    return boost.clamp(0.5, 3.0);
  }

  double _tagBoost(DocumentChunk chunk, String query) {
    if (chunk.tags == null) return 0.0;
    return query.toLowerCase().contains(chunk.tags!.toLowerCase()) ? 0.5 : 0.0;
  }

  String _formatSource(DocumentChunk chunk) {
    if (chunk.isHardcoded) return '📄 Knowledge Base — ${chunk.category ?? "FAQ"}';
    return '${chunk.source ?? "Document"}, p.${chunk.pageNumber}';
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
