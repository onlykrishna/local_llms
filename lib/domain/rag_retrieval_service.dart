import 'package:get/get.dart' hide Condition;
import '../core/embedding_service.dart';
import '../data/document_chunk.dart';
import '../domain/kb_domain.dart';
import '../objectbox.g.dart';

class RetrievedChunk {
  final String text;
  final String sourceLabel;
  final double similarity;

  RetrievedChunk(this.text, this.sourceLabel, this.similarity);
}

class RagRetrievalService extends GetxService {
  final Store store;
  final EmbeddingService embeddingService;
  late final Box<DocumentChunk> chunkBox;

  RagRetrievalService(this.store, this.embeddingService) {
    chunkBox = store.box<DocumentChunk>();
  }

  Future<List<RetrievedChunk>> retrieve(String query, String? domainName, {int topK = 5}) async {
    final queryVector = await embeddingService.embed(query);

    Condition<DocumentChunk>? condition;
    if (domainName != null) {
      condition = DocumentChunk_.domain.equals(domainName);
    }

    final queryBuilder = chunkBox.query(condition);
    final dbQuery = queryBuilder.build();
    dbQuery.param(DocumentChunk_.embedding).nearestNeighborsF32(queryVector, 10);
    final results = dbQuery.findWithScores();
    dbQuery.close();

    List<RetrievedChunk> candidateChunks = [];
    
    for (var result in results) {
      final chunk = result.object;
      // ObjectBox returns distance, for cosine similarity: similarity = 1 - distance
      // Actually objectbox returns distance. We want high similarity (low distance).
      // Assuming distance is cosine distance (0 to 2, where 0 is identical)
      double similarity = 1.0 - result.score;
      
      if (similarity > 0.35) {
        candidateChunks.add(RetrievedChunk(chunk.text, chunk.sourceLabel, similarity));
      }
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

    return finalChunks;
  }
}
