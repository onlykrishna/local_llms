import 'dart:math';
import 'package:get/get.dart';
import '../../core/embedding_service.dart';
import '../../data/document_chunk.dart';
import '../../objectbox.g.dart';
import '../../core/services/log_service.dart';

class TopicGuardService extends GetxService {
  final Store _store;
  final EmbeddingService _embedding;
  late final Box<DocumentChunk> _chunkBox;

  final Map<String, List<double>> _centroids = {};
  bool _isInitialized = false;

  TopicGuardService(this._store, this._embedding) {
    _chunkBox = _store.box<DocumentChunk>();
  }

  Future<void> init() async {
    await refresh();
    _isInitialized = true;
  }

  /// Recomputes centroids for all document categories.
  /// Call this after new documents are indexed.
  Future<void> refresh() async {
    LogService.to.log('[TopicGuard] Refreshing topic centroids...');
    
    final allChunks = _chunkBox.getAll();
    if (allChunks.isEmpty) {
      _centroids.clear();
      return;
    }

    final Map<String, List<List<double>>> groupings = {};

    for (final chunk in allChunks) {
      if (chunk.embedding == null || chunk.embedding!.isEmpty) continue;
      
      // key = category name (derived from the PDF filename without extension)
      String category = 'General';
      if (chunk.source != null && chunk.source!.isNotEmpty) {
        category = chunk.source!.split('/').last.split('.').first;
      } else if (chunk.category != null && chunk.category!.isNotEmpty) {
        category = chunk.category!;
      }

      groupings.putIfAbsent(category, () => []).add(chunk.embedding!);
    }

    _centroids.clear();
    groupings.forEach((category, embeddings) {
      if (embeddings.isEmpty) return;
      
      final dim = embeddings.first.length;
      final centroid = List<double>.filled(dim, 0.0);
      
      for (final emb in embeddings) {
        for (int i = 0; i < dim; i++) {
          centroid[i] += emb[i];
        }
      }
      
      for (int i = 0; i < dim; i++) {
        centroid[i] /= embeddings.length;
      }
      
      _centroids[category] = centroid;
      LogService.to.log('[TopicGuard] Computed centroid for "$category" (${embeddings.length} chunks)');
    });
  }

  Future<bool> isOnTopic(String query, {double threshold = 0.35}) async {
    if (_chunkBox.count() == 0) {
      LogService.to.log('[TopicGuard] Fail open: No documents indexed');
      return true;
    }

    if (!_isInitialized) await init();
    if (_centroids.isEmpty) return true; // Fail open if centroids couldn't be computed

    final queryEmbedding = await _embedding.embed(query);
    
    double maxSimilarity = -1.0;
    String? closestTopic;

    _centroids.forEach((category, centroid) {
      final sim = _cosineSimilarity(queryEmbedding, centroid);
      if (sim > maxSimilarity) {
        maxSimilarity = sim;
        closestTopic = category;
      }
    });

    LogService.to.log('[TopicGuard] Query: "$query" | Max Similarity: ${maxSimilarity.toStringAsFixed(3)} ($closestTopic)');

    return maxSimilarity >= threshold;
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
