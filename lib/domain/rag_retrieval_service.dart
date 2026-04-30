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

  factory RagResult.directBypass(
          String content, List<String> sources, List<ScoredChunk> chunks,
          {bool isFromKb = false}) =>
      RagResult(
          requiresLlm: false,
          content: content,
          sources: sources,
          chunks: chunks,
          isFromKb: isFromKb);

  factory RagResult.llmGrounded(
          String context, List<String> sources, List<ScoredChunk> chunks) =>
      RagResult(
          requiresLlm: true,
          content: '',
          context: context,
          sources: sources,
          chunks: chunks);

  factory RagResult.noAnswer() => RagResult(
      requiresLlm: false,
      content: 'No answer available.',
      sources: [],
      chunks: []);
}

class RagRetrievalService extends GetxService {
  final Store store;
  final EmbeddingService embeddingService;
  late final Box<DocumentChunk> chunkBox;

  // ── Tunable thresholds ────────────────────────────────────────────────────
  // Direct bypass: answer returned as-is, no LLM
  static const double _bypassThresholdKb = 0.85;
  static const double _bypassThresholdDoc = 1.20;

  // LLM grounding: answer synthesized from context
  static const double _llmThresholdKb = 0.60;
  static const double _llmThresholdDoc = 0.75;

  // Context cap to prevent model from being overwhelmed
  static const int _maxContextChars = 1500;
  static const int _maxContextChunks = 3;

  RagRetrievalService(this.store, this.embeddingService) {
    chunkBox = store.box<DocumentChunk>();
  }

  Future<RagResult> retrieve(String rawQuery) async {
    debugPrint('[RAG] ========== NEW QUERY ==========');
    debugPrint('[RAG] Raw query: "$rawQuery"');

    final expanded = AcronymExpander.expand(_normalize(rawQuery));
    debugPrint('[RAG] Expanded: "$expanded"');

    final allKbChunks =
        chunkBox.query(DocumentChunk_.isHardcoded.equals(true)).build().find();
    debugPrint('[RAG] Total KB chunks in DB: ${allKbChunks.length}');

    final queryEmbedding = await embeddingService.embed(expanded);

    // Retrieve top-60 candidates from HNSW index
    final condition =
        DocumentChunk_.embedding.nearestNeighborsF32(queryEmbedding, 60);
    final dbQuery = chunkBox.query(condition).build();
    final results = dbQuery.findWithScores();
    dbQuery.close();

    if (results.isEmpty) {
      debugPrint('[RAG] No results from vector search → noAnswer');
      return RagResult.noAnswer();
    }

    // ── Score candidates ───────────────────────────────────────────────────
    final scored = results.map((result) {
      final chunk = result.object;
      final emb = chunk.embedding;

      double cosine = (emb != null && emb.isNotEmpty)
          ? _cosineSimilarity(queryEmbedding, emb)
          : (1.0 - result.score);

      final kw =
          _keywordOverlap(chunk.text + ' ' + (chunk.question ?? ''), rawQuery);
      final tagBoost = _tagBoost(chunk, rawQuery);
      final phraseBonus = _exactPhraseBonus(chunk, rawQuery);

      double rawScore =
          (cosine * 0.45) + (kw * 0.35) + (tagBoost * 0.10) + (phraseBonus * 0.10);
      double score = rawScore;

      final bool isKb = chunk.isHardcoded == true;
      if (isKb) score *= 2.0; // KB entries get double weight — ground truth

      final chunkId = isKb
          ? (chunk.tags ?? '${chunk.source}_p${chunk.pageNumber}')
          : '${chunk.source ?? 'doc'}_p${chunk.pageNumber}';

      debugPrint('[SCORE] $chunkId: '
          'cos=${cosine.toStringAsFixed(3)} '
          'kw=${kw.toStringAsFixed(3)} '
          'phrase=${phraseBonus.toStringAsFixed(3)} '
          'raw=${rawScore.toStringAsFixed(3)} '
          'final=${score.toStringAsFixed(3)} '
          'isKB=$isKb');

      return ScoredChunk(
          chunk: chunk,
          score: score,
          cosine: cosine,
          kw: kw,
          boost: tagBoost);
    }).toList();

    scored.sort((a, b) => b.score.compareTo(a.score));
    final top = scored.first;
    final bool isKb = top.chunk.isHardcoded == true;

    debugPrint('[RAG] Top chunk score=${top.score.toStringAsFixed(3)} isKB=$isKb');

    if (_shouldDirectBypass(top, isKb)) {
      debugPrint('[RAG] → DIRECT BYPASS');
      return RagResult.directBypass(
        _sanitizeChunk(top.chunk.text),
        [_formatSource(top.chunk)],
        [top],
        isFromKb: isKb,
      );
    } else if (_shouldCallLlm(top, isKb)) {
      debugPrint('[RAG] → LLM GROUNDED');

      // ── Select unique chunks, cap at _maxContextChunks ──────────────────
      final selected = <ScoredChunk>[];
      final seenTexts = <String>{};
      int totalChars = 0;

      for (final s in scored) {
        if (selected.length >= _maxContextChunks) break;
        final clean = _sanitizeChunk(s.chunk.text);
        
        // Aggressive normalization for deduplication key:
        // Remove all non-alphanumeric chars to catch duplicates with different formatting.
        final key = clean.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

        if (key.length < 10) continue; // Skip very short/noisy chunks
        if (seenTexts.contains(key)) {
          debugPrint('[RAG] Deduplicated redundant chunk: "${clean.substring(0, min(20, clean.length))}..."');
          continue;
        }
        
        if (totalChars + clean.length > _maxContextChars) break;

        selected.add(s);
        seenTexts.add(key);
        totalChars += clean.length;
      }

      final context = selected.map((s) => _sanitizeChunk(s.chunk.text)).join('\n\n');

      debugPrint('[RAG] Context: ${selected.length} chunk(s), $totalChars chars');
      debugPrint('[RAG] Context preview:\n${context.substring(0, min(300, context.length))}...');

      return RagResult.llmGrounded(
        context,
        selected.map((s) => _formatSource(s.chunk)).toList(),
        selected,
      );
    } else {
      debugPrint('[RAG] → NO ANSWER (score too low)');
      return RagResult.noAnswer();
    }
  }

  // ── Decision Logic ─────────────────────────────────────────────────────────
  bool _shouldDirectBypass(ScoredChunk top, bool isKb) {
    if (!isKb) return top.score >= _bypassThresholdDoc;
    final hasKw = top.kw >= 0.14 || top.boost > 0.0;
    if (top.score >= _bypassThresholdKb && hasKw) return true;
    if (top.score >= 1.10) return true;
    return false;
  }

  bool _shouldCallLlm(ScoredChunk top, bool isKb) {
    if (!isKb) return top.score >= _llmThresholdDoc;
    return top.score >= _llmThresholdKb && top.kw >= 0.14;
  }

  // ── Scoring Helpers ────────────────────────────────────────────────────────
  double _keywordOverlap(String chunkText, String query) {
    final qLower = _normalize(query);
    final cLower = _normalize(chunkText);
    final queryTerms =
        qLower.split(RegExp(r'\s+')).where((w) => w.length > 2).toSet();
    if (queryTerms.isEmpty) return 0.0;
    int matches = 0;
    for (final term in queryTerms) {
      final pattern = RegExp(r'\b' + RegExp.escape(term) + r'\b');
      if (pattern.hasMatch(cLower)) matches++;
    }
    return matches / queryTerms.length;
  }

  double _exactPhraseBonus(DocumentChunk chunk, String rawQuery) {
    if (chunk.question == null) return 0.0;
    final q = _normalize(rawQuery);
    final cq = _normalize(chunk.question!);
    final words = q.split(RegExp(r'\s+'));
    for (int n = 3; n >= 2; n--) {
      for (int i = 0; i <= words.length - n; i++) {
        final phrase = words.sublist(i, i + n).join(' ');
        if (phrase.length > 4 && cq.contains(phrase)) return 1.0;
      }
    }
    return 0.0;
  }

  String _normalize(String text) {
    return text
        .toLowerCase()
        .replaceAll('-', ' ')
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
    return min(1.0, matches * 0.4);
  }

  String _formatSource(DocumentChunk chunk) {
    if (chunk.isHardcoded == true) {
      return '📄 Knowledge Base — ${chunk.category ?? "FAQ"}';
    }
    return '${chunk.source ?? chunk.sourceLabel}, p.${chunk.pageNumber}';
  }

  String _sanitizeChunk(String raw) {
    String s = raw.replaceAll(RegExp(r'^[A-Z\s\?\.\-\/]+\?\s*', multiLine: true), '');
    s = s.replaceAll(RegExp(r'^\d+[\.)] \s*', multiLine: true), '');
    s = s.replaceAll(RegExp(r'[■●•▪︎➤]'), '');
    s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    return s;
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
