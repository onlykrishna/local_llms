import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

import 'storage_service.dart';
import 'pdf_processing_service.dart';
import 'embedding_service.dart';
import 'api_provider_service.dart';

import '../models/pdf_document.dart';
import '../models/pdf_chunk.dart';
import '../models/chat_message.dart';

class PdfChatService extends GetxService {

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final StorageService _storage = Get.find<StorageService>();
  final PdfProcessingService _processing = Get.find<PdfProcessingService>();
  final EmbeddingService _embedding = Get.find<EmbeddingService>();
  final ApiProviderService _api = Get.find<ApiProviderService>();

  String get _uid => _storage.getUid()!;

  CollectionReference<Map<String, dynamic>> get _docsRef =>
      _db.collection('users').doc(_uid).collection('pdf_documents');

  CollectionReference<Map<String, dynamic>> get _chunksRef =>
      _db.collection('users').doc(_uid).collection('pdf_chunks');

  // ── UPLOAD & INDEX a PDF ──────────────────────────────────────
  // Full pipeline: upload → extract → chunk → embed → store
  // Calls onProgress(stage, 0.0 to 1.0) throughout for UI feedback.
  Future<PdfDocument> uploadAndIndex({
    required String filePath,
    required String fileName,
    required void Function(String stage, double progress) onProgress,
  }) async {
    final docId = const Uuid().v4();
    final provider = 'OpenAI';

    // Stage 1: Upload to Firebase Storage (0% → 30%)
    onProgress('Uploading to Firebase...', 0.0);
    final downloadUrl = await _processing.uploadToStorage(
      localPath: filePath,
      docId: docId,
      fileName: fileName,
      onProgress: (p) => onProgress('Uploading to Firebase...', p * 0.3),
    );

    // Stage 2: Extract text page by page (30% → 50%)
    onProgress('Extracting text from PDF...', 0.3);
    final pages = _processing.extractPages(filePath);
    final pageCount = pages.map((p) => p.key).fold(0, max);

    // Stage 3: Chunk text (50% → 60%)
    onProgress('Splitting into chunks...', 0.5);
    final rawChunks = _processing.chunkPages(pages);

    // Stage 4: Embed all chunks (60% → 90%)
    // Build plain text list for batch embedding
    final chunkTexts = rawChunks.map((c) => c.value).toList();

    // Embed all chunks with progress callback
    final embeddings = await _embedding.embedBatch(
      chunkTexts,
      onProgress: (current, total) {
        onProgress(
          'Embedding chunk $current of $total...',
          0.6 + (current / total) * 0.3,
        );
      },
    );

    // Build PdfChunk objects with their embeddings
    final List<PdfChunk> chunks = [];
    for (int i = 0; i < rawChunks.length; i++) {
      chunks.add(PdfChunk(
        id: _processing.chunkId(docId, i),
        docId: docId,
        fileName: fileName,
        pageNumber: rawChunks[i].key,
        chunkIndex: i,
        text: rawChunks[i].value,
        embedding: embeddings[i],
      ));
    }

    // Stage 5: Write chunks to Firestore in batches of 400 (90% → 95%)
    onProgress('Saving to database...', 0.9);
    final batches = <WriteBatch>[];
    WriteBatch currentBatch = _db.batch();
    int opCount = 0;

    for (final chunk in chunks) {
      currentBatch.set(_chunksRef.doc(chunk.id), chunk.toFirestore());
      opCount++;
      if (opCount == 400) {
        batches.add(currentBatch);
        currentBatch = _db.batch();
        opCount = 0;
      }
    }
    if (opCount > 0) batches.add(currentBatch);
    for (final batch in batches) { await batch.commit(); }

    // Stage 6: Save document metadata (95% → 100%)
    onProgress('Saving to database...', 0.95);
    final doc = PdfDocument(
      id: docId,
      fileName: fileName,
      storagePath: 'users/$_uid/pdfs/$docId/$fileName',
      downloadUrl: downloadUrl,
      pageCount: pageCount,
      chunkCount: chunks.length,
      uploadedAt: DateTime.now(),
      status: ProcessingStatus.ready,
    );
    await _docsRef.doc(docId).set(doc.toFirestore());

    onProgress('Ready!', 1.0);
    return doc;
  }

  // ── LOAD all uploaded PDFs for the user ──
  Future<List<PdfDocument>> loadDocuments() async {
    final snapshot = await _docsRef
        .where('status', isEqualTo: ProcessingStatus.ready.name)
        .orderBy('uploadedAt', descending: true)
        .get();

    return snapshot.docs
        .map((d) => PdfDocument.fromFirestore(d.data()))
        .toList();
  }

  // ── DELETE a PDF and all its chunks ──
  Future<void> deleteDocument(String docId) async {
    final chunks = await _chunksRef
        .where('docId', isEqualTo: docId)
        .get();
    final batch = _db.batch();
    for (final doc in chunks.docs) { batch.delete(doc.reference); }
    batch.delete(_docsRef.doc(docId));
    await batch.commit();
  }

  // ── DELETE only the chunks for a specific document (for re-indexing) ──
  Future<void> deleteChunksForDocument(String docId) async {
    final snapshot = await _chunksRef
        .where('docId', isEqualTo: docId)
        .get();
    final batch = _db.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    // Also remove the document metadata so it shows as needing re-upload
    batch.delete(_docsRef.doc(docId));
    await batch.commit();
  }

  // ── QUERY: retrieve top-K relevant chunks ──
  // Returns (List<PdfChunk> topChunks, List<ChunkCitation> citations)
  Future<(List<PdfChunk>, List<ChunkCitation>)> retrieveChunks({
    required String query,
    required List<String>? filterDocIds, // null = search all docs
    int topK = 4,
    double threshold = 0.30,
  }) async {
    // 1. Embed the query — use RETRIEVAL_QUERY for asymmetric accuracy
    final queryVec = await _embedding.embedText(
      query,
      taskType: 'RETRIEVAL_QUERY',
    );

    // 2. Load all chunks (optionally filtered by docId)
    Query<Map<String, dynamic>> chunksQuery = _chunksRef;
    if (filterDocIds != null && filterDocIds.isNotEmpty) {
      chunksQuery = chunksQuery.where('docId', whereIn: filterDocIds);
    }
    final snapshot = await chunksQuery.get();
    final allChunks = snapshot.docs
        .map((d) => PdfChunk.fromFirestore(d.data()))
        .toList();

    if (allChunks.isEmpty) {
      debugPrint('⚠️ No chunks found in Firestore for search.');
      return (<PdfChunk>[], <ChunkCitation>[]);
    }

    // 3. Score each chunk
    final scored = allChunks.map((chunk) {
      final score = _embedding.cosineSimilarity(queryVec, chunk.embedding);
      return (chunk, score);
    }).toList();

    // 4. Sort descending, apply threshold, take topK
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    
    debugPrint('🔍 RAG Search: found ${allChunks.length} total chunks.');
    if (scored.isNotEmpty) {
      debugPrint('🔍 Top score: ${scored.first.$2.toStringAsFixed(3)}');
    }

    final filtered = scored
        .where((s) => s.$2 >= threshold)
        .take(topK)
        .toList();

    final topChunks = filtered.map((s) => s.$1).toList();
    final citations = filtered.map((s) => ChunkCitation(
      fileName: s.$1.fileName,
      pageNumber: s.$1.pageNumber,
      score: s.$2,
    )).toList();

    return (topChunks, citations);
  }

  // ── GENERATE a cited answer using retrieved chunks ──
  Future<String> generateAnswer({
    required String question,
    required List<PdfChunk> chunks,
  }) async {
    if (chunks.isEmpty) {
      return 'I could not find relevant information in your uploaded PDFs '
             'to answer that question. Try rephrasing, or upload a PDF '
             'that contains information about this topic.';
    }

    final contextBlock = chunks.asMap().entries.map((entry) {
      final i = entry.key + 1;
      final chunk = entry.value;
      return '[Source $i: ${chunk.fileName}, page ${chunk.pageNumber}]\n'
             '${chunk.text}';
    }).join('\n\n---\n\n');

    const systemPrompt =
      'You are a precise document assistant. Answer questions using ONLY '
      'the provided context. If the answer is not in the context, say so '
      'clearly. Do not fabricate information. '
      'Format your response in Markdown. '
      'At the end of your response, include a "Sources used:" section '
      'that lists each source you actually used, formatted as:\n'
      '- [Source N] FileName, page X\n'
      'Only list sources whose content you referenced in your answer.';

    final userPrompt =
      'Context:\n$contextBlock\n\n'
      'Question: $question\n\n'
      'Answer based on the context above:';

    final messages = [
      ChatMessage(
        id: 'system',
        role: MessageRole.system,
        content: systemPrompt,
        timestamp: DateTime.now(),
      ),
      ChatMessage(
        id: 'user',
        role: MessageRole.user,
        content: userPrompt,
        timestamp: DateTime.now(),
      ),
    ];

    return await _api.sendMessages(messages);
  }

  // ── ONE-TIME CLEANUP: wipe ALL chunks + docs for full re-indexing ──
  // Kept here for emergency use. Do NOT call from onInit() in production.
  Future<void> clearAllChunks() async {
    final chunksSnapshot = await _chunksRef.get();
    if (chunksSnapshot.docs.isNotEmpty) {
      final batch = _db.batch();
      for (final doc in chunksSnapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }

    final docsSnapshot = await _docsRef.get();
    if (docsSnapshot.docs.isNotEmpty) {
      final batch = _db.batch();
      for (final doc in docsSnapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }
}
