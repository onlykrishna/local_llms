import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart' hide Condition;
import '../core/embedding_service.dart';
import '../data/document_chunk.dart';
import '../domain/kb_domain.dart';
import '../domain/services/acronym_expander.dart';
import '../objectbox.g.dart';

class RetrievedChunk {
  final String text;
  final String sourceLabel;
  final double similarity;
  final int pageNumber;
  final String domain;
  final double kwScore;
  final double tagBoost;

  RetrievedChunk({
    required this.text,
    required this.sourceLabel,
    required this.similarity,
    required this.pageNumber,
    required this.domain,
    this.kwScore = 0.0,
    this.tagBoost = 0.0,
  });
}

enum RetrievalResultType { directBypass, llmGrounded, noAnswer }

class RetrievalResult {
  final RetrievalResultType type;
  final String content;
  final List<String> sources;

  RetrievalResult({
    required this.type,
    required this.content,
    required this.sources,
  });

  factory RetrievalResult.noAnswer() => RetrievalResult(
    type: RetrievalResultType.noAnswer,
    content: 'No answer available.',
    sources: [],
  );
}

class RagRetrievalService extends GetxService {
  final Store store;
  final EmbeddingService embeddingService;
  late final Box<DocumentChunk> chunkBox;

  RagRetrievalService(this.store, this.embeddingService) {
    chunkBox = store.box<DocumentChunk>();
  }

  Future<RetrievalResult> retrieve(String query, String? domainName) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return RetrievalResult.noAnswer();

    // TIER 1: EXACT TEXT SEARCH (Primary)
    final exactMatches = await exactTextSearch(cleanQuery, domainName);
    
    if (exactMatches.isNotEmpty) {
      debugPrint('[RAG] Tier 1: Found ${exactMatches.length} exact matches');
      
      final topMatch = exactMatches.first;
      final termCoverage = _calculateTermCoverage(cleanQuery, topMatch.text);
      
      // SPECIAL: Definition Bypass
      // If it's a "What is X" query and we have a chunk that defines it, bypass LLM
      if (isDefinitionQuery(cleanQuery) && chunkContainsDefinition(topMatch, cleanQuery)) {
        debugPrint('[RAG] Definition Bypass triggered');
        return RetrievalResult(
          type: RetrievalResultType.directBypass,
          content: _sanitizeChunk(topMatch.text),
          sources: exactMatches.map((c) => c.sourceLabel).toList(),
        );
      }

      // If single very high confidence match → Direct Bypass
      if (exactMatches.length == 1 && termCoverage >= 0.8) {
        return RetrievalResult(
          type: RetrievalResultType.directBypass,
          content: _sanitizeChunk(topMatch.text),
          sources: exactMatches.map((c) => c.sourceLabel).toList(),
        );
      }
      
      // Otherwise, use exact matches as grounded context for LLM
      final context = exactMatches
          .map((c) => _sanitizeChunk(c.text))
          .join('\n\n---\n\n');
          
      return RetrievalResult(
        type: RetrievalResultType.llmGrounded,
        content: context,
        sources: exactMatches.map((c) => c.sourceLabel).toList(),
      );
    }

    // TIER 2: VECTOR SEARCH (Fallback)
    debugPrint('[RAG] Tier 1 failed. Falling back to Tier 2 (Vector)');
    final vectorMatches = await _vectorSearch(cleanQuery, domainName);
    
    if (vectorMatches.isNotEmpty) {
      final topScore = vectorMatches.first.similarity;
      debugPrint('[RAG] Tier 2 top score: $topScore');
      
      if (topScore >= 0.75) {
        final context = vectorMatches
            .take(2)
            .map((c) => _sanitizeChunk(c.text))
            .join('\n\n---\n\n');
            
        return RetrievalResult(
          type: RetrievalResultType.llmGrounded,
          content: context,
          sources: vectorMatches.take(2).map((c) => c.sourceLabel).toList(),
        );
      }
    }

    // TIER 3: NO ANSWER
    debugPrint('[RAG] Both tiers failed to find confident results');
    return RetrievalResult.noAnswer();
  }

  Future<List<DocumentChunk>> exactTextSearch(String rawQuery, String? domainName) async {
    final expanded = AcronymExpander.expand(rawQuery);
    
    final stopWords = {'what', 'is', 'are', 'the', 'a', 'an', 'does', 
                       'do', 'how', 'why', 'when', 'for', 'stand', 'me',
                       'tell', 'about', 'explain', 'define', 'meaning'};
    
    final queryTerms = expanded.toLowerCase()
        .split(RegExp(r'\W+'))
        .where((w) => w.length > 3 && !stopWords.contains(w))
        .toSet();
    
    if (queryTerms.isEmpty) return [];
    
    final allChunks = chunkBox.getAll();
    final scored = <MapEntry<DocumentChunk, int>>[];
    
    for (final chunk in allChunks) {
      if (domainName != null && chunk.domain != domainName) continue;
      
      final chunkLower = chunk.text.toLowerCase();
      int matches = 0;
      for (final term in queryTerms) {
        if (chunkLower.contains(term)) matches++;
      }
      
      if (matches > 0) {
        scored.add(MapEntry(chunk, matches));
      }
    }
    
    scored.sort((a, b) => b.value.compareTo(a.value));
    
    final threshold = (queryTerms.length * 0.5).ceil();
    return scored
        .where((e) => e.value >= threshold)
        .take(3)
        .map((e) => e.key)
        .toList();
  }

  Future<List<RetrievedChunk>> _vectorSearch(String query, String? domainName) async {
    final expandedQuery = AcronymExpander.expandQuery(query);
    final queryVector = await embeddingService.embed(expandedQuery);

    Condition<DocumentChunk> condition = DocumentChunk_.embedding.nearestNeighborsF32(queryVector, 10);
    if (domainName != null) {
      condition = condition.and(DocumentChunk_.domain.equals(domainName));
    }

    final dbQuery = chunkBox.query(condition).build();
    final results = dbQuery.findWithScores();
    dbQuery.close();

    List<RetrievedChunk> finalChunks = [];
    for (var result in results) {
      final chunk = result.object;
      final emb = chunk.embedding;
      double cosine = (emb != null && emb.isNotEmpty) 
          ? _cosineSimilarity(queryVector, emb) 
          : (1.0 - result.score);

      finalChunks.add(RetrievedChunk(
        text: chunk.text,
        sourceLabel: chunk.sourceLabel,
        similarity: cosine,
        pageNumber: chunk.pageNumber,
        domain: chunk.domain,
      ));
    }

    finalChunks.sort((a, b) => b.similarity.compareTo(a.similarity));
    return finalChunks;
  }

  bool isDefinitionQuery(String query) {
    return RegExp(
      r'^(what (is|are|does|do)|define|explain|tell me about|what stands for)',
      caseSensitive: false,
    ).hasMatch(query.trim());
  }
  
  bool chunkContainsDefinition(DocumentChunk chunk, String query) {
    final lowerText = chunk.text.toLowerCase();
    // Try to find the core subject of the query
    final subject = query.toLowerCase()
        .replaceAll(RegExp(r'^(what (is|are|does|do)|define|explain|tell me about|what)\s+'), '')
        .replaceAll(RegExp(r'\s+stand for.*$'), '')
        .trim();
        
    if (subject.isEmpty) return false;
    
    return lowerText.contains('$subject stands for') ||
           lowerText.contains('$subject is a') ||
           lowerText.contains('$subject means') ||
           lowerText.contains('$subject refers to');
  }

  double _calculateTermCoverage(String query, String text) {
    final qTerms = query.toLowerCase().split(RegExp(r'\W+')).where((w) => w.length > 3).toSet();
    if (qTerms.isEmpty) return 0.0;
    final textLower = text.toLowerCase();
    int matches = qTerms.where((t) => textLower.contains(t)).length;
    return matches / qTerms.length;
  }

  String _sanitizeChunk(String raw) {
    String sanitized = raw.replaceAll(RegExp(r'^[A-Z\s\?\.\-\/]+\?\s*', multiLine: true), '');
    sanitized = sanitized.replaceAll(RegExp(r'^\d+[\.\)]\s*', multiLine: true), '');
    sanitized = sanitized.replaceAll(RegExp(r'[■●•▪︎➤]'), '');
    sanitized = sanitized.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    return sanitized;
  }

  // FIX 3: Bidirectional Acronym Matching
  double _keywordOverlap(String content, String rawQuery) {
    // Expand acronyms in BOTH directions for accurate matching
    final expandedQuery = AcronymExpander.expand(rawQuery);
    final expandedContent = AcronymExpander.expand(content);

    final stopWords = {'what', 'is', 'are', 'the', 'for', 'how', 'can', 'you', 'tell', 'me', 'about'};
    
    final queryWords = expandedQuery.toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3 && !stopWords.contains(w))
        .toSet();

    if (queryWords.isEmpty) return 0.0;

    final contentLower = expandedContent.toLowerCase();
    int hits = queryWords.where((w) => contentLower.contains(w)).length;
    return hits / queryWords.length;
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
    final result = dot / denom;
    return result.clamp(-1.0, 1.0);
  }

  /// Diagnostic tool to check for corrupted or identical embeddings.
  Future<void> diagnoseEmbeddings() async {
    final allChunks = chunkBox.getAll();
    debugPrint('[DIAG] Total chunks in DB: ${allChunks.length}');
    
    for (int i = 0; i < allChunks.length && i < 5; i++) {
      final chunk = allChunks[i];
      final emb = chunk.embedding;
      
      if (emb == null || emb.isEmpty) {
        debugPrint('[DIAG] Chunk $i: ❌ NULL embedding!');
        continue;
      }
      
      final allZero = emb.every((v) => v == 0.0);
      final allSame = emb.every((v) => v == emb.first);
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
  }
}
