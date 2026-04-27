import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart' hide Condition;
import '../core/embedding_service.dart';
import '../data/document_chunk.dart';
import '../domain/kb_domain.dart';
import '../objectbox.g.dart';

class RetrievedChunk {
  final String text;
  final String sourceLabel;
  final double similarity;
  final int pageNumber;
  final String domain;

  RetrievedChunk({
    required this.text,
    required this.sourceLabel,
    required this.similarity,
    required this.pageNumber,
    required this.domain,
  });

  RetrievedChunk copyWith({double? similarity}) {
    return RetrievedChunk(
      text: text,
      sourceLabel: sourceLabel,
      similarity: similarity ?? this.similarity,
      pageNumber: pageNumber,
      domain: domain,
    );
  }
}

class RagRetrievalService extends GetxService {
  final Store store;
  final EmbeddingService embeddingService;
  late final Box<DocumentChunk> chunkBox;

  static const double _similarityThreshold = 0.60;

  RagRetrievalService(this.store, this.embeddingService) {
    chunkBox = store.box<DocumentChunk>();
  }

  Future<List<RetrievedChunk>> retrieve(String query, String? domainName, {int topK = 5}) async {
    final totalInBox = chunkBox.count();
    debugPrint('[RAG] Database state: $totalInBox total chunks in store.');
    
    if (totalInBox == 0) {
      debugPrint('[RAG] CRITICAL: No chunks found in database. Please upload and ingest a document first.');
      return [];
    }

    final queryVector = await embeddingService.embed(query);

    // 1. First, try the domain-filtered query
    Condition<DocumentChunk> condition = DocumentChunk_.embedding.nearestNeighborsF32(queryVector, 8);
    if (domainName != null) {
      condition = condition.and(DocumentChunk_.domain.equals(domainName));
    }

    debugPrint('[RAG] Querying ObjectBox (Domain: $domainName)...');
    final dbQuery = chunkBox.query(condition).build();
    final results = dbQuery.findWithScores();
    dbQuery.close();

    debugPrint('[RAG] Raw ObjectBox results (after domain filter): ${results.length}');

    // 2. If domain query returned 0, diagnostic check
    if (results.isEmpty && domainName != null) {
      final domainCount = chunkBox.query(DocumentChunk_.domain.equals(domainName)).build().count();
      debugPrint('[RAG] Diagnostic: Found $domainCount chunks stored for domain "$domainName".');
    }

    List<RetrievedChunk> candidateChunks = [];
    
    for (var result in results) {
      final chunk = result.object;
      final emb = chunk.embedding;
      
      double similarity;
      if (emb != null && emb.isNotEmpty) {
        similarity = _cosineSimilarity(queryVector, emb);
      } else {
        similarity = 1.0 - result.score;
      }
      
      debugPrint('[RAG] Candidate: ${chunk.sourceLabel}, Similarity: ${similarity.toStringAsFixed(3)}');

      if (similarity > _similarityThreshold) { 
        candidateChunks.add(RetrievedChunk(
          text: chunk.text,
          sourceLabel: chunk.sourceLabel,
          similarity: similarity,
          pageNumber: chunk.pageNumber,
          domain: chunk.domain,
        ));
      }
    }

    // ── STEP 2: KEYWORD SCAN (Critical Fallback) ────────────────────────────
    // HNSW fails when all domain text has similar embeddings (0.93+ similarity).
    // Scan ALL chunks for exact keyword matches and promote them to the top.
    final keywordMatches = _keywordScan(query, domainName);
    debugPrint('[RAG] Keyword scan found: ${keywordMatches.length} direct matches');
    
    // Merge: keyword matches override HNSW with an elevated score
    final Map<String, RetrievedChunk> mergedMap = {};
    for (final chunk in candidateChunks) {
      final key = '${chunk.sourceLabel}_p${chunk.pageNumber}';
      mergedMap[key] = chunk;
    }
    for (final chunk in keywordMatches) {
      final key = '${chunk.sourceLabel}_p${chunk.pageNumber}';
      // Keyword match always wins or adds if not present from HNSW
      if (!mergedMap.containsKey(key) || mergedMap[key]!.similarity < chunk.similarity) {
        mergedMap[key] = chunk;
        debugPrint('[RAG] Keyword promoted: ${chunk.sourceLabel} (Score: ${chunk.similarity.toStringAsFixed(3)})');
      }
    }

    // Re-rank with keyword boost on the merged set
    List<RetrievedChunk> reRanked = _reRankChunks(query, mergedMap.values.toList());

    List<RetrievedChunk> finalChunks = reRanked;
    finalChunks.sort((a, b) => b.similarity.compareTo(a.similarity));

    if (finalChunks.length > topK) {
      finalChunks = finalChunks.sublist(0, topK);
    }

    for (var chunk in finalChunks) {
      debugPrint('[RAG] Final Match: ${chunk.sourceLabel} (Score: ${chunk.similarity.toStringAsFixed(3)})');
    }

    if (finalChunks.isEmpty && totalInBox > 0) {
      debugPrint('[RAG] TIP: If you just changed the tokenizer/embedding logic, you MUST delete and RE-UPLOAD your documents to refresh the vector index.');
    }

    return finalChunks;
  }

  /// Keyword scan: searches ALL chunks in the DB for exact keyword matches.
  /// This is the critical fallback when HNSW returns semantically-similar-but-wrong chunks.
  List<RetrievedChunk> _keywordScan(String query, String? domainName) {
    // Get all chunks for the domain
    List<DocumentChunk> allChunks;
    if (domainName != null) {
      allChunks = chunkBox.query(DocumentChunk_.domain.equals(domainName)).build().find();
    } else {
      allChunks = chunkBox.getAll();
    }

    // Extract meaningful keywords (3+ chars, exclude stop words)
    final stopWords = {'what', 'is', 'are', 'the', 'for', 'how', 'can', 'you', 'tell', 'me', 'about'};
    final queryWords = query.toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3 && !stopWords.contains(w))
        .toList();

    if (queryWords.isEmpty) return [];

    final List<RetrievedChunk> matches = [];

    for (final chunk in allChunks) {
      final chunkLower = chunk.text.toLowerCase();
      int hits = queryWords.where((w) => chunkLower.contains(w)).length;
      
      if (hits > 0) {
        // Score: 1.0 offset + actual coverage (0.0 to 1.0)
        // This allows inference_router to distinguish keyword matches from HNSW.
        final coverage = hits / queryWords.length;
        final score = 1.0 + coverage;
        
        matches.add(RetrievedChunk(
          text: chunk.text,
          sourceLabel: chunk.sourceLabel,
          similarity: score, // Range 1.0 to 2.0
          pageNumber: chunk.pageNumber,
          domain: chunk.domain,
        ));
      }
    }

    matches.sort((a, b) => b.similarity.compareTo(a.similarity));
    return matches.take(3).toList();
  }

  /// Diagnostic tool to check for corrupted or identical embeddings.
  Future<void> diagnoseEmbeddings() async {
    final box = store.box<DocumentChunk>();
    final allChunks = box.getAll();
    
    debugPrint('[DIAG] Total chunks in DB: ${allChunks.length}');
    
    for (int i = 0; i < allChunks.length && i < 5; i++) {
      final chunk = allChunks[i];
      final emb = chunk.embedding;
      
      if (emb == null || emb.isEmpty) {
        debugPrint('[DIAG] Chunk $i: ❌ NULL embedding!');
        continue;
      }
      
      // Check if all values are zero (corrupted)
      final allZero = emb.every((v) => v == 0.0);
      // Check if all values are identical (corrupted)
      final allSame = emb.every((v) => v == emb.first);
      // Check L2 norm (should be ~1.0 after normalization)
      double norm = 0;
      for (final v in emb) norm += v * v;
      norm = sqrt(norm);
      
      debugPrint('[DIAG] Chunk $i: '
        'len=${emb.length} '
        'norm=${norm.toStringAsFixed(3)} '
        'allZero=$allZero '
        'allSame=$allSame '
        'preview=${emb.take(5).map((v) => v.toStringAsFixed(3)).toList()}'
      );
      debugPrint('[DIAG] Text preview: '
        '${chunk.text.substring(0, min(80, chunk.text.length))}');
    }
    
    // Check if top-2 chunks are too similar to each other
    if (allChunks.length >= 2) {
      final e1 = allChunks[0].embedding!;
      final e2 = allChunks[1].embedding!;
      double sim = _cosineSimilarity(e1, e2);
      debugPrint('[DIAG] Similarity chunk0 vs chunk1: '
        '${sim.toStringAsFixed(3)} '
        '(if > 0.99 → embeddings are corrupted)');
    }
  }

  // Fix 4A: Guard all similarity calculations against NaN/Infinity
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
    final result = dot / denom;
    if (result.isNaN || result.isInfinite) return 0.0;
    return result.clamp(-1.0, 1.0);
  }

  // Fix 3D: Keyword boost re-ranking
  List<RetrievedChunk> _reRankChunks(String query, List<RetrievedChunk> chunks) {
    final queryWords = query.toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3)
        .toSet();

    if (queryWords.isEmpty) return chunks;

    return chunks.map((chunk) {
      final chunkLower = chunk.text.toLowerCase();
      int keywordHits = queryWords
          .where((word) => chunkLower.contains(word))
          .length;
      // Boost score by 0.02 per keyword hit (max 0.10)
      final boostedScore = chunk.similarity + (min(keywordHits, 5) * 0.02);
      return chunk.copyWith(similarity: boostedScore);
    }).toList();
  }
}
