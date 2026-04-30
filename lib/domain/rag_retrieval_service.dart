import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart' hide Condition;
import '../core/embedding_service.dart';
import '../data/document_chunk.dart';
import 'services/acronym_expander.dart';
import 'services/fuzzy_query_corrector.dart';
import '../objectbox.g.dart';

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

  RagResult({
    required this.requiresLlm,
    required this.content,
    required this.sources,
    required this.chunks,
    this.isFromKb = false,
    this.context,
  });

  factory RagResult.directBypass(String content, List<String> sources, List<ScoredChunk> chunks, {bool isFromKb = false}) =>
      RagResult(requiresLlm: false, content: content, sources: sources, chunks: chunks, isFromKb: isFromKb);

  factory RagResult.llmGrounded(String context, List<String> sources, List<ScoredChunk> chunks) =>
      RagResult(requiresLlm: true, content: '', context: context, sources: sources, chunks: chunks);

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

  static const Map<String, List<String>> _intentKeywords = {
    'documents': ['document', 'paper', 'require', 'need', 'submit', 'provide', 'kyc', 'proof'],
    'eligibility': ['eligible', 'criteria', 'qualify', 'age', 'income', 'salary', 'score'],
    'interest': ['interest', 'rate', '%', 'roi'],
    'emi': ['emi', 'monthly', 'installment'],
    'tenure': ['tenure', 'year', 'month', 'duration', 'period'],
    'process': ['process', 'step', 'apply', 'how'],
  };

  RagRetrievalService(this.store, this.embeddingService) {
    chunkBox = store.box<DocumentChunk>();
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
    print('[RAG-DIAG] Total chunks in ObjectBox: $totalChunks');
    print('[RAG-DIAG] Raw Query: $rawQuery');

    final typoCorrected = FuzzyQueryCorrector.correct(rawQuery);
    final expanded = AcronymExpander.expand(typoCorrected);
    final resolvedScope = resolveDocumentScope(typoCorrected);
    
    print('[RAG-DIAG] Resolved scope: $resolvedScope');

    if (totalChunks == 0) {
      print('[RAG-DIAG] ERROR: ObjectBox is EMPTY');
      return RagResult.noAnswer();
    }

    final queryEmbedding = await embeddingService.embed(expanded);

    // ── Build Query ────────────────────────────────────────────────────────
    Condition<DocumentChunk> condition = DocumentChunk_.embedding.nearestNeighborsF32(queryEmbedding, 40);
    
    if (resolvedScope != null) {
      // Use contains to be safer with tags
      condition = condition.and(DocumentChunk_.sourceDocumentTag.contains(resolvedScope));
    }

    final dbQuery = chunkBox.query(condition).build();
    final results = dbQuery.findWithScores();
    dbQuery.close();

    print('[RAG-DIAG] Raw results count: ${results.length}');

    if (results.isEmpty) {
      print('[RAG-DIAG] No results from vector search → noAnswer');
      return RagResult.noAnswer();
    }

    // ── Scoring & Thresholding ──────────────────────────────────────────────
    final scored = results.map((result) {
      final chunk = result.object;
      final emb = chunk.embedding;

      double cosine = (emb != null && emb.isNotEmpty)
          ? _cosineSimilarity(queryEmbedding, emb)
          : (1.0 - result.score);

      final kwBoost = _computeKeywordBoost(chunk.text + ' ' + (chunk.question), expanded);
      final tagBoost = _tagBoost(chunk, expanded);
      
      // 1B model hybrid score
      double score = (cosine * 0.45) * kwBoost + (tagBoost * 0.20);
      if (chunk.isHardcoded) score *= 1.5;

      return ScoredChunk(chunk: chunk, score: score, cosine: cosine, kw: kwBoost, boost: tagBoost);
    }).toList();

    scored.sort((a, b) => b.score.compareTo(a.score));
    final top = scored.first;

    // CRITICAL: Low threshold for 1B model
    final threshold = resolvedScope != null ? 0.25 : 0.40;
    print('[RAG-DIAG] Top score: ${top.score.toStringAsFixed(3)} | Threshold: $threshold | Match: ${top.score >= threshold}');

    if (top.score < threshold) {
      print('[RAG-DIAG] → NO ANSWER (below threshold)');
      return RagResult.noAnswer();
    }

    // ── NEW: Aggressive Direct Bypass ──────────────────────────────────────
    // If we have a very strong match (especially when scoped), don't even ask the LLM.
    // This prevents the "shy LLM" problem where it says "No answer available" 
    // even when the context is perfect.
    final bool isKb = top.chunk.isHardcoded;
    final double bypassThreshold = resolvedScope != null ? 0.65 : 0.85;
    
    if (top.score >= bypassThreshold) {
      print('[RAG-DIAG] → HIGH CONFIDENCE BYPASS (score ${top.score.toStringAsFixed(2)})');
      return RagResult.directBypass(
        _sanitizeChunk(top.chunk.text),
        [_formatSource(top.chunk)],
        [top],
        isFromKb: isKb,
      );
    }

    // LLM Grounding
    final selected = scored.where((s) => s.score >= threshold).take(3).toList();
    final context = selected.map((s) => _sanitizeChunk(s.chunk.text)).join('\n\n');

    return RagResult.llmGrounded(context, selected.map((s) => _formatSource(s.chunk)).toList(), selected);
  }

  double _computeKeywordBoost(String chunkText, String query) {
    double boost = 1.0;
    final qLower = query.toLowerCase();
    final cLower = chunkText.toLowerCase();
    for (final intent in _intentKeywords.entries) {
      if (qLower.contains(intent.key)) {
        final matches = intent.value.where((kw) => cLower.contains(kw)).length;
        if (matches > 0) boost += (matches * 0.2);
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
