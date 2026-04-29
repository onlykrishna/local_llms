import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/document_chunk.dart';
import '../data/hardcoded_kb.dart';
import '../core/embedding_service.dart';
import '../objectbox.g.dart';

class KbEmbeddingService {
  final EmbeddingService _embedder;
  final Box<DocumentChunk> _box;
  static const String _kbVersionKey = 'kb_version';
  
  final _statusController = StreamController<KbInitStatus>.broadcast();
  Stream<KbInitStatus> get statusStream => _statusController.stream;
  
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  KbEmbeddingService(this._embedder, this._box);

  Future<void> initializeKb() async {
    if (_isInitialized) return;

    debugPrint('[KB_EMBED] initializeKb() called');

    final prefs = await SharedPreferences.getInstance();
    final storedVersion = prefs.getString(_kbVersionKey);
    
    final existing = _box.query(
      DocumentChunk_.isHardcoded.equals(true)
    ).build().find();

    debugPrint('[KB_EMBED] Existing KB chunks in DB: ${existing.length}');
    debugPrint('[KB_EMBED] Expected KB chunks: ${kKnowledgeBase.length}');
    debugPrint('[KB_EMBED] EmbeddingService ready: ${_embedder.isInitialized}');

    final isUpToDate = storedVersion == kKbVersion &&
                       existing.length >= kKnowledgeBase.length;

    if (isUpToDate) {
      debugPrint('[KB_EMBED] KB up-to-date (version=$kKbVersion, chunks=${existing.length}) — skipping re-embed');
      
      final hl06 = _box.query(DocumentChunk_.tags.equals('hl_06')).build().findFirst();
      if (hl06 != null) {
        debugPrint('[KB_DIAG] hl_06 is in DB. Embedding size: ${hl06.embedding?.length}');
      } else {
        debugPrint('[KB_DIAG] hl_06 MISSING from DB despite being "up-to-date"!');
      }

      _isInitialized = true;
      _statusController.add(KbInitStatus.ready(
        message: '${kKnowledgeBase.length} facts ready',
      ));
      return;
    }

    debugPrint('[KB_EMBED] KB version mismatch or missing chunks — re-embedding (stored=$storedVersion, current=$kKbVersion)');

    // Remove old KB chunks
    _statusController.add(KbInitStatus.loading(
      message: 'Preparing knowledge base...',
      progress: 0.0,
    ));
    _box.removeMany(existing.map((c) => c.id).toList());

    // Embed each KB entry
    final total = kKnowledgeBase.length;
    for (int i = 0; i < total; i++) {
      final entry = kKnowledgeBase[i];

      _statusController.add(KbInitStatus.loading(
        message: 'Embedding: ${entry.category} (${i + 1}/$total)',
        progress: (i + 1) / total,
        currentEntry: entry.question,
      ));

      debugPrint('[KB_EMBED] Embedding ${i+1}/$total: ${entry.id}');
      final embedding = await _embedder.embed(entry.embeddingText);

      final norm = _computeNorm(embedding);
      final allZero = embedding.every((v) => v == 0.0);
      debugPrint('[KB_EMBED] ✅ Embedded ${entry.id}: dims=${embedding.length} norm=${norm.toStringAsFixed(3)} allZero=$allZero');

      if (allZero || embedding.isEmpty) {
        debugPrint('[KB_EMBED] ❌ FAILED embedding for ${entry.id} — skipping');
        continue;
      }

      final chunk = DocumentChunk(
        text: entry.answer,
        question: entry.question,
        source: 'hardcoded_kb',
        pageNumber: 0,
        tags: entry.id,
        embedding: embedding,
        isHardcoded: true,
        category: entry.category,
        sourceDocId: -1,
        domain: 'finance',
        chunkIndex: i,
        sourceLabel: 'Knowledge Base',
        createdAt: DateTime.now(),
      );
      final savedId = _box.put(chunk);
      debugPrint('[KB_EMBED] 💾 Saved chunk id=$savedId for entry=${entry.id}');
    }

    await prefs.setString(_kbVersionKey, kKbVersion);
    _isInitialized = true;
    
    final finalCount = _box.query(DocumentChunk_.isHardcoded.equals(true)).build().count();
    debugPrint('[KB_EMBED] ✅ DONE. Total KB chunks in DB: $finalCount');
    
    _statusController.add(KbInitStatus.ready(
      message: 'Knowledge base initialized — $finalCount facts loaded',
    ));
  }

  double _computeNorm(List<double> v) {
    if (v.isEmpty) return 0.0;
    return sqrt(v.fold(0.0, (sum, x) => sum + x * x));
  }
}

// Status model for UI
class KbInitStatus {
  final KbInitStage stage;
  final String message;
  final double progress;        // 0.0 to 1.0
  final String? currentEntry;

  const KbInitStatus._({
    required this.stage,
    required this.message,
    this.progress = 0.0,
    this.currentEntry,
  });

  factory KbInitStatus.loading({
    required String message,
    required double progress,
    String? currentEntry,
  }) => KbInitStatus._(
    stage: KbInitStage.loading,
    message: message,
    progress: progress,
    currentEntry: currentEntry,
  );

  factory KbInitStatus.ready({required String message}) =>
      KbInitStatus._(stage: KbInitStage.ready, message: message,
                     progress: 1.0);

  factory KbInitStatus.error({required String message}) =>
      KbInitStatus._(stage: KbInitStage.error, message: message);
}

enum KbInitStage { loading, ready, error }
