import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart' hide Condition;
import '../core/embedding_service.dart';
import '../data/document_chunk.dart';
import 'services/acronym_expander.dart';
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

  factory RagResult.noAnswer() =>
      RagResult(requiresLlm: false, content: 'No answer available.', sources: [], chunks: []);
}

class RagRetrievalService extends GetxService {
  final Store store;
  final EmbeddingService embeddingService;
  late final Box<DocumentChunk> chunkBox;

  RagRetrievalService(this.store, this.embeddingService) {
    chunkBox = store.box<DocumentChunk>();
  }

  Future<RagResult> retrieve(String rawQuery) async {
    // DIAGNOSTIC — runs before any scoring
    debugPrint('[DIAG] ========== NEW QUERY ==========');
    debugPrint('[DIAG] Raw query: "$rawQuery"');
    
    final normalized = _normalize(rawQuery);
    debugPrint('[DIAG] Normalized: "$normalized"');
    
    final expanded = AcronymExpander.expand(normalized);
    debugPrint('[DIAG] Expanded: "$expanded"');
    
    // Check if hl_06 even exists in DB
    final allKbChunks = chunkBox.query(
      DocumentChunk_.isHardcoded.equals(true)
    ).build().find();
    debugPrint('[DIAG] Total KB chunks in DB: ${allKbChunks.length}');
    
    final preEmiChunk = allKbChunks
        .where((c) => c.tags == 'hl_06')
        .firstOrNull;
    debugPrint('[DIAG] hl_06 exists: ${preEmiChunk != null}');
    if (preEmiChunk != null) {
      debugPrint('[DIAG] hl_06 question: "${preEmiChunk.question}"');
      debugPrint('[DIAG] hl_06 embedding norm: '
          '${_norm(preEmiChunk.embedding).toStringAsFixed(3)}');
      debugPrint('[DIAG] hl_06 keyword overlap with query: '
          '${_keywordOverlap(preEmiChunk.question ?? '' + preEmiChunk.text, rawQuery).toStringAsFixed(3)}');
    }
    
    final emiChunk = allKbChunks
        .where((c) => c.tags == 'hl_05')
        .firstOrNull;
    if (emiChunk != null) {
      debugPrint('[DIAG] hl_05 keyword overlap with query: '
          '${_keywordOverlap(emiChunk.question ?? '' + emiChunk.text, rawQuery).toStringAsFixed(3)}');
    }

    final queryEmbedding = await embeddingService.embed(expanded);

    // Get top-60 from HNSW (increased for absolute recall safety)
    final condition = DocumentChunk_.embedding.nearestNeighborsF32(queryEmbedding, 60);
    final dbQuery = chunkBox.query(condition).build();
    final results = dbQuery.findWithScores();
    dbQuery.close();

    if (results.isEmpty) return RagResult.noAnswer();

    final scored = results.map((result) {
      final chunk = result.object;
      final emb = chunk.embedding;
      
      double cosine = (emb != null && emb.isNotEmpty)
          ? _cosineSimilarity(queryEmbedding, emb)
          : (1.0 - result.score);

      final normalizedQuery = _normalize(rawQuery);
      final kw = _keywordOverlap(chunk.text + ' ' + (chunk.question ?? ''), rawQuery);
      final tagBoost = _tagBoost(chunk, rawQuery);
      final phraseBonus = _exactPhraseBonus(chunk, rawQuery);

      double rawScore = (cosine * 0.45) + (kw * 0.35) + (tagBoost * 0.10) + (phraseBonus * 0.10);
      double score = rawScore;

      // KB entries get double scoring weight — they are ground truth
      final bool isKb = chunk.isHardcoded == true;
      if (isKb) score *= 2.0;

      final chunkId = isKb
          ? chunk.tags        // KB entry ID like "hl_05"
          : '${chunk.source ?? 'doc'}_p${chunk.pageNumber}';

      debugPrint('[RAG_SCORE] $chunkId: '
                 'cosine=${cosine.toStringAsFixed(3)} '
                 'kw=${kw.toStringAsFixed(3)} '
                 'phrase=${phraseBonus.toStringAsFixed(3)} '
                 'rawScore=${rawScore.toStringAsFixed(3)} '
                 'finalScore=${score.toStringAsFixed(3)} '
                 'isKB=$isKb');

      return ScoredChunk(
        chunk: chunk,
        score: score,
        cosine: cosine,
        kw: kw,
        boost: tagBoost,
      );
    }).toList();

    scored.sort((a, b) => b.score.compareTo(a.score));
    final top = scored.first;

    final bool isKb = top.chunk.isHardcoded == true;

    if (shouldDirectBypass(top, expanded)) {
      debugPrint('[RAG] DIRECT BYPASS — score=${top.score.toStringAsFixed(3)} isKB=$isKb');
      return RagResult.directBypass(
        _sanitizeChunk(top.chunk.text),
        [_formatSource(top.chunk)],
        [top],
        isFromKb: isKb,
      );
    } else if (shouldCallLlm(top)) {
      debugPrint('[RAG] LLM GROUNDED — score=${top.score.toStringAsFixed(3)}');
      final topChunks = scored.take(2).toList();
      final context = topChunks
          .map((s) => _sanitizeChunk(s.chunk.text))
          .join('\n\n');
      return RagResult.llmGrounded(
        context,
        topChunks.map((s) => _formatSource(s.chunk)).toList(),
        topChunks,
      );
    } else {
      debugPrint('[RAG] NO ANSWER — score=${top.score.toStringAsFixed(3)} below all thresholds');
      return RagResult.noAnswer();
    }
  }

  bool shouldDirectBypass(ScoredChunk top, String query) {
    if (top.chunk.isHardcoded != true) {
      return top.score >= 1.20;
    }
    
    // For KB chunks: require BOTH score threshold AND
    // at least some keyword relevance
    final hasKeywordSignal = top.kw >= 0.14 || top.boost > 0.0;
    
    // High-confidence bypass: score >= 0.85 with keywords
    if (top.score >= 0.85 && hasKeywordSignal) return true;
    
    // Very high confidence: bypass even without keywords
    // (cosine alone is strong enough at this level)
    if (top.score >= 1.10) return true;
    
    return false;
  }

  bool shouldCallLlm(ScoredChunk top) {
    if (top.chunk.isHardcoded != true) {
      return top.score >= 0.75;
    }
    // KB candidates need minimum keyword signal to trigger LLM
    // to prevent hallucinating from unrelated KB chunks
    return top.score >= 0.60 && top.kw >= 0.14;
  }

  double _keywordOverlap(String chunkText, String query) {
    final qLower = _normalize(query);
    final cLower = _normalize(chunkText);

    final queryTerms = qLower.split(RegExp(r'\s+'))
        .where((w) => w.length > 2)
        .toSet();

    if (queryTerms.isEmpty) return 0.0;

    int matches = 0;
    for (final term in queryTerms) {
      // CRITICAL: whole-word match only — prevents "emi" matching inside "pre-emi"
      final pattern = RegExp(r'\b' + RegExp.escape(term) + r'\b');
      if (pattern.hasMatch(cLower)) matches++;
    }
    return matches / queryTerms.length;
  }

  double _exactPhraseBonus(DocumentChunk chunk, String rawQuery) {
    if (chunk.question == null) return 0.0;
    
    final q = _normalize(rawQuery);
    final cq = _normalize(chunk.question!);
    
    // Extract bigrams and trigrams from query
    final words = q.split(RegExp(r'\s+'));
    for (int n = 3; n >= 2; n--) {
      for (int i = 0; i <= words.length - n; i++) {
        final phrase = words.sublist(i, i + n).join(' ');
        if (phrase.length > 4 && cq.contains(phrase)) {
          return 1.0; // Return full bonus unit, weighted by formula
        }
      }
    }
    return 0.0;
  }

  String _normalize(String text) {
    return text
      .toLowerCase()
      .replaceAll('-', ' ')        // hyphen → space: "pre-emi" → "pre emi"
      .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  }

  double _tagBoost(DocumentChunk chunk, String query) {
    if (chunk.tags == null || chunk.tags!.isEmpty) return 0.0;
    final tags = chunk.tags!.toLowerCase().split(',');
    final queryLower = query.toLowerCase();
    
    int matches = 0;
    for (final tag in tags) {
      if (queryLower.contains(tag.trim())) matches++;
    }
    
    return min(1.0, matches * 0.4); // 0.4 boost per matching tag
  }

  String _formatSource(DocumentChunk chunk) {
    if (chunk.isHardcoded == true) {
      return '📄 Knowledge Base — ${chunk.category ?? "FAQ"}';
    }
    return '${chunk.source ?? chunk.sourceLabel}, p.${chunk.pageNumber}';
  }

  String _sanitizeChunk(String raw) {
    String sanitized = raw.replaceAll(RegExp(r'^[A-Z\s\?\.\-\/]+\?\s*', multiLine: true), '');
    sanitized = sanitized.replaceAll(RegExp(r'^\d+[\.\)]\s*', multiLine: true), '');
    sanitized = sanitized.replaceAll(RegExp(r'[■●•▪︎➤]'), '');
    sanitized = sanitized.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    return sanitized;
  }

  double _norm(List<double>? v) {
    if (v == null || v.isEmpty) return 0.0;
    return sqrt(v.fold(0.0, (sum, x) => sum + x * x));
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
    if (denom == 0 || denom.isNaN || denom.isInfinite) return 0.0;
    return (dot / denom).clamp(-1.0, 1.0);
  }
}
