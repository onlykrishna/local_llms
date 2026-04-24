import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'dart:math';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../core/embedding_service.dart';
import '../data/document_chunk.dart';
import '../data/source_document.dart';
import '../domain/kb_domain.dart';
import '../objectbox.g.dart'; // From build_runner

class DocumentIngestionService extends GetxService {
  final Store store;
  final EmbeddingService embeddingService;
  late final Box<SourceDocument> docBox;
  late final Box<DocumentChunk> chunkBox;

  final RxDouble ingestionProgress = 0.0.obs;

  DocumentIngestionService(this.store, this.embeddingService) {
    docBox = store.box<SourceDocument>();
    chunkBox = store.box<DocumentChunk>();
  }

  Future<void> ingestDocument(File file, KbDomain domain) async {
    ingestionProgress.value = 0.0;
    final fileName = file.path.split('/').last;

    final sourceDoc = SourceDocument(
      fileName: fileName,
      filePath: file.path,
      domain: domain.name,
      pageCount: 0,
      chunkCount: 0,
      uploadedAt: DateTime.now(),
      status: 'processing',
    );
    final docId = docBox.put(sourceDoc);

    try {
      final bytes = await file.readAsBytes();
      // Offload extraction and chunking to background isolate
      final extractionResult = await compute(_extractAndChunkInIsolate, {
        'bytes': bytes,
        'fileName': fileName,
        'domain': domain.name,
        'docId': docId,
      });
      
      List<DocumentChunk> allChunks = extractionResult.chunks;
      sourceDoc.pageCount = extractionResult.pageCount;
      docBox.put(sourceDoc);
      
      debugPrint('[Ingestion] Background extraction complete. Generated ${allChunks.length} chunks.');
      ingestionProgress.value = 0.5;

      final int totalChunks = allChunks.length;
      debugPrint('[Ingestion] Total chunks generated: $totalChunks');
      if (totalChunks == 0) {
        debugPrint('[Ingestion] WARNING: No chunks generated for document $fileName');
      }
      final int batchSize = 16;
      for (int i = 0; i < totalChunks; i += batchSize) {
        final end = (i + batchSize < totalChunks) ? i + batchSize : totalChunks;
        final batch = allChunks.sublist(i, end);
        
        final textsToEmbed = batch.map((c) => c.text).toList();
        final embeddings = await embeddingService.embedBatch(textsToEmbed);
        
        for (int j = 0; j < batch.length; j++) {
          batch[j].embedding = embeddings[j];
        }
        
        chunkBox.putMany(batch);
        debugPrint('[Ingestion] Saved batch of ${batch.length} chunks. Total so far: ${i + batch.length}');
        ingestionProgress.value = 0.5 + ((end / totalChunks) * 0.5); // remaining 50%
      }

      sourceDoc.status = 'ready';
      sourceDoc.chunkCount = totalChunks;
      docBox.put(sourceDoc);
      debugPrint('[Ingestion] Document ready: $fileName with $totalChunks chunks in domain: ${domain.name}');
      ingestionProgress.value = 1.0;

    } catch (e) {
      sourceDoc.status = 'error';
      sourceDoc.errorMessage = e.toString();
      docBox.put(sourceDoc);
      ingestionProgress.value = 0.0;
      rethrow;
    }
  }

  String _cleanText(String text) {
    // Basic cleaning
    text = text.replaceAll(RegExp(r'\r\n'), '\n');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n'); // Max double newlines
    return text.trim();
  }
}

/// Helper classes and functions for Isolate processing
class _ExtractionResult {
  final List<DocumentChunk> chunks;
  final int pageCount;
  _ExtractionResult(this.chunks, this.pageCount);
}

_ExtractionResult _extractAndChunkInIsolate(Map<String, dynamic> params) {
  final Uint8List bytes = params['bytes'];
  final String fileName = params['fileName'];
  final String domain = params['domain'];
  final int docId = params['docId'];

  final PdfDocument document = PdfDocument(inputBytes: bytes);
  final int pageCount = document.pages.count;
  List<DocumentChunk> allChunks = [];
  int chunkIndex = 0;

  final extractor = PdfTextExtractor(document);
  
  for (int i = 0; i < pageCount; i++) {
    String text = extractor.extractText(startPageIndex: i, endPageIndex: i);
    
    // Minimal cleaning in isolate
    text = text.replaceAll(RegExp(r'\r\n'), '\n');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();

    if (text.isEmpty) continue;

    // STEP 1: Try paragraph-based splitting first
    final paragraphs = text
        .split(RegExp(r'\n{2,}'))           // double newline = paragraph
        .map((p) => p.replaceAll('\n', ' ').trim())
        .where((p) => p.length > 80)        // skip very short fragments
        .toList();

    List<String> pageChunks = [];
    if (paragraphs.length > 1) {
      // Multiple paragraphs found — use them as natural chunks
      for (final para in paragraphs) {
        if (para.length <= 600) {
          // Paragraph fits in one chunk
          pageChunks.add(para);
        } else {
          // Long paragraph — split at sentence boundaries
          pageChunks.addAll(_splitIntoSentences(para));
        }
      }
    } else {
      // No paragraph structure — split by sentences
      pageChunks.addAll(_splitIntoSentences(text));
    }

    for (final chunkText in pageChunks) {
      allChunks.add(DocumentChunk(
        sourceDocId: docId,
        domain: domain,
        chunkIndex: chunkIndex++,
        pageNumber: i + 1,
        text: chunkText,
        sourceLabel: '$fileName, p.${i + 1}',
        createdAt: DateTime.now(),
      ));
    }
  }
  document.dispose();
  return _ExtractionResult(allChunks, pageCount);
}

List<String> _splitIntoSentences(String text) {
  final chunks = <String>[];
  final sentences = text.split(RegExp(r'(?<=[.!?])\s+(?=[A-Z])'));
  final buffer = <String>[];
  int wordCount = 0;

  for (final sentence in sentences) {
    final cleanSentence = sentence.trim();
    if (cleanSentence.isEmpty) continue;

    final wordsInSentence = cleanSentence.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final wordCountInSentence = wordsInSentence.length;

    // Safety: If a single "sentence" is huge (e.g. no punctuation), split it by word count
    if (wordCountInSentence > 150) {
      if (buffer.isNotEmpty) {
        chunks.add(buffer.join(' '));
        buffer.clear();
        wordCount = 0;
      }
      for (int i = 0; i < wordsInSentence.length; i += 100) {
        int end = (i + 100 < wordsInSentence.length) ? i + 100 : wordsInSentence.length;
        chunks.add(wordsInSentence.sublist(i, end).join(' '));
      }
      continue;
    }

    if (wordCount + wordCountInSentence > 120 && buffer.isNotEmpty) {
      chunks.add(buffer.join(' '));
      buffer.clear();
      wordCount = 0;
    }

    buffer.add(cleanSentence);
    wordCount += wordCountInSentence;
  }

  if (buffer.isNotEmpty) {
    final remaining = buffer.join(' ').trim();
    if (remaining.length > 80) {
      chunks.add(remaining);
    }
  }

  return chunks;
}
