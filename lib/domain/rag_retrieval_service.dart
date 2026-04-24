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
}

class RagRetrievalService extends GetxService {
  final Store store;
  final EmbeddingService embeddingService;
  late final Box<DocumentChunk> chunkBox;

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
    Condition<DocumentChunk> condition = DocumentChunk_.embedding.nearestNeighborsF32(queryVector, 50);
    if (domainName != null) {
      condition = condition.and(DocumentChunk_.domain.equals(domainName));
    }

    debugPrint('[RAG] Querying ObjectBox (Domain: $domainName)...');
    final dbQuery = chunkBox.query(condition).build();
    final results = dbQuery.findWithScores();
    dbQuery.close();

    debugPrint('[RAG] Raw ObjectBox results (after domain filter): ${results.length}');

    // 2. If domain query returned 0 but we have chunks, check if it's a domain mismatch
    if (results.isEmpty && domainName != null) {
      final domainCount = chunkBox.query(DocumentChunk_.domain.equals(domainName)).build().count();
      debugPrint('[RAG] Diagnostic: Found $domainCount chunks stored for domain "$domainName".');
      
      if (domainCount == 0) {
        debugPrint('[RAG] WARNING: You are querying domain "$domainName" but no documents are ingested in this domain.');
      } else {
        debugPrint('[RAG] INFO: Chunks exist for this domain, but none matched the query vectors. Checking global similarity...');
        // Fallback to global search for diagnostic purposes
        final globalQuery = chunkBox.query(DocumentChunk_.embedding.nearestNeighborsF32(queryVector, 5)).build();
        final globalResults = globalQuery.findWithScores();
        for (var res in globalResults) {
          debugPrint('[RAG] Global Top Match Similarity: ${(1.0 - res.score).toStringAsFixed(3)} (Domain: ${res.object.domain})');
        }
        globalQuery.close();
      }
    }

    List<RetrievedChunk> candidateChunks = [];
    
    for (var result in results) {
      final chunk = result.object;
      double similarity = 1.0 - result.score;
      
      debugPrint('[RAG] Candidate: ${chunk.sourceLabel}, Similarity: ${similarity.toStringAsFixed(3)} (Raw Score: ${result.score.toStringAsFixed(3)})');

      // Lowered threshold to 0.18 to ensure we get results even with slight model drift or low-confidence matches
      if (similarity > 0.18) { 
        candidateChunks.add(RetrievedChunk(
          text: chunk.text,
          sourceLabel: chunk.sourceLabel,
          similarity: similarity,
          pageNumber: chunk.pageNumber,
          domain: chunk.domain,
        ));
      }
    }

    if (candidateChunks.isEmpty && results.isNotEmpty) {
      debugPrint('[RAG] Found ${results.length} neighbors, but all were below the 0.18 similarity threshold.');
    }

    // Deduplicate: if two chunks from same page, keep higher-scored one
    Map<String, RetrievedChunk> pageBestMap = {};
    for (var chunk in candidateChunks) {
      if (!pageBestMap.containsKey(chunk.sourceLabel) || 
          pageBestMap[chunk.sourceLabel]!.similarity < chunk.similarity) {
        pageBestMap[chunk.sourceLabel] = chunk;
      }
    }

    List<RetrievedChunk> finalChunks = pageBestMap.values.toList();
    finalChunks.sort((a, b) => b.similarity.compareTo(a.similarity)); // descending

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
}
