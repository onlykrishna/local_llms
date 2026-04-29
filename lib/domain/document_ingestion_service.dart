import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'dart:math';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../core/embedding_service.dart';
import '../data/document_chunk.dart';
import '../data/source_document.dart';
import 'kb_domain.dart';
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

    // STEP 1: Clear existing chunks for this domain first to prevent duplicates/stale data
    final existingIds = chunkBox
        .query(DocumentChunk_.domain.equals(domain.name))
        .build()
        .findIds();
    chunkBox.removeMany(existingIds);
    debugPrint('[Ingestion] Cleared ${existingIds.length} old chunks for domain: ${domain.name}');

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

      final List<DocumentChunk> validChunks = [];
      final int batchSize = 16;
      
      for (int i = 0; i < totalChunks; i += batchSize) {
        final end = (i + batchSize < totalChunks) ? i + batchSize : totalChunks;
        final batch = allChunks.sublist(i, end);
        
        final textsToEmbed = batch.map((c) => '${c.question} ${c.text}').toList();
        final List<List<double>> embeddings = await embeddingService.embedBatch(textsToEmbed);
        
        for (int j = 0; j < batch.length; j++) {
          final vector = embeddings[j];
          
          // STEP 2: Validate embedding is not corrupted (norm should be ~1.0)
          double norm = 0;
          for (final v in vector) norm += v * v;
          norm = sqrt(norm);
          
          if (norm < 0.5 || norm > 1.5) {
            debugPrint('[Ingestion] ⚠️ Bad embedding chunk $i+$j, norm=$norm, skipping');
            continue;
          }

          // ✅ Store as List<double> explicitly
          batch[j].embedding = vector.map((v) => v.toDouble()).toList();
          validChunks.add(batch[j]);
          
          if (i + j < 5) {
            debugPrint('[Ingestion] ✅ Chunk ${i + j}: norm=${norm.toStringAsFixed(3)} text="${batch[j].text.substring(0, min(30, batch[j].text.length))}..."');
          }
        }
        
        chunkBox.putMany(batch);
        debugPrint('[Ingestion] Saved batch of ${batch.length} chunks. Total so far: ${i + batch.length}');
        
        // Fix 4B: Prevent NaN in progress calculation
        final progress = 0.5 + ((end / (totalChunks > 0 ? totalChunks : 1)) * 0.5);
        ingestionProgress.value = progress.isNaN || progress.isInfinite ? 0.5 : progress;
      }

      sourceDoc.status = 'ready';
      sourceDoc.chunkCount = validChunks.length;
      docBox.put(sourceDoc);
      debugPrint('[Ingestion] Document ready: $fileName with ${validChunks.length} valid chunks in domain: ${domain.name}');
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

  // Fix 3B: Aggressively clean chunks to remove similarity-poisoning noise
  // Fix 3B: Aggressively clean chunks to remove similarity-poisoning noise
  static String _cleanChunkText(String text) {
    return text
        .replaceAll(RegExp(r'[\u{1F600}-\u{1F64F}\u{1F300}-\u{1F5FF}\u{1F680}-\u{1F6FF}\u{1F1E6}-\u{1F1FF}]', unicode: true), '') // Emojis
        .replaceAll(RegExp(r'(FAQs|Terms & Conditions|Privacy Policy|Page \d+|Confidential)', caseSensitive: false), '') // Generic headers
        .replaceAll(RegExp(r'\s+'), ' ') // Normalize whitespace
        .trim();
  }

  static String? detectAcronymTag(String chunkText) {
    // Pattern 1: "ACRONYM stands for" / "ACRONYM means"
    final p1 = RegExp(
      r'\b([A-Z]{2,5})\b[^.]{0,50}(?:stands for|means|refers to)',
      caseSensitive: true,
    );
    
    // Pattern 2: "Full Name (ACRONYM)" — parenthetical form
    // e.g. "Loan to Value (LTV)", "Equated Monthly Instalment (EMI)"
    final p2 = RegExp(
      r'\b[A-Z][a-z]+(?:\s+[A-Za-z]+){1,4}\s+\(([A-Z]{2,5})\)',
    );
    
    final m1 = p1.firstMatch(chunkText);
    if (m1 != null) return m1.group(1)!.toLowerCase();
    
    final m2 = p2.firstMatch(chunkText);
    if (m2 != null) return m2.group(1)!.toLowerCase();
    
    return null;
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

    // ── FAQ-BOUNDARY SPLITTER ────────────────────────────────────────────────
    // Strategy: detect numbered FAQ question patterns like "01.", "09.", "1️0."
    // and treat each as a hard chunk boundary so Q + A stay together.
    //
    // Pattern matches:
    //   "01. WHAT IS EMI?"      → standard numbered FAQ
    //   "1️0. WHAT IS LTV?"    → emoji-prefixed numbers (unicode digit variants)
    //   "Q1.", "Q.1", etc.     → other common FAQ numbering
    //
    // We collect all Q+A pairs as discrete chunks per page.
    // ────────────────────────────────────────────────────────────────────────

    // Normalize unicode digit variants (emoji keycaps like 1️⃣ → 1)
    String normalizedText = text
        .replaceAll('\u0031\uFE0F\u20E3', '1')  // 1️⃣
        .replaceAll('\u0032\uFE0F\u20E3', '2')  // 2️⃣
        .replaceAll('\u0033\uFE0F\u20E3', '3')  // 3️⃣
        .replaceAll('\u0034\uFE0F\u20E3', '4')  // 4️⃣
        .replaceAll('\u0035\uFE0F\u20E3', '5')  // 5️⃣
        .replaceAll('\u0036\uFE0F\u20E3', '6')  // 6️⃣
        .replaceAll('\u0037\uFE0F\u20E3', '7')  // 7️⃣
        .replaceAll('\u0038\uFE0F\u20E3', '8')  // 8️⃣
        .replaceAll('\u0039\uFE0F\u20E3', '9')  // 9️⃣
        .replaceAll('\u{1F51F}', '10');          // 🔟

    // Split by FAQ boundary: lines starting with number pattern like "01.", "1.", "10."
    // The regex uses a lookahead so we keep the delimiter at the start of each segment
    final faqBoundary = RegExp(r'(?=(?:^|\n)\s*\d{1,2}[\.。]\s+[A-Z])', multiLine: true);
    List<String> faqSegments = normalizedText.split(faqBoundary)
        .map((s) => s.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((s) => s.isNotEmpty)
        .toList();

    // If no FAQ boundaries found (plain prose page), fall back to paragraph split
    if (faqSegments.length <= 1) {
      faqSegments = normalizedText
          .split(RegExp(r'\n{2,}'))
          .map((p) => p.replaceAll('\n', ' ').trim())
          .where((p) => p.isNotEmpty)
          .toList();
    }

    // Now emit each segment as its own chunk (split large ones by sentences)
    List<String> pageChunks = [];
    for (final seg in faqSegments) {
      if (seg.length <= 900) {
        pageChunks.add(seg);
      } else {
        // Large answer block — split further by sentence
        pageChunks.addAll(_splitIntoSentences(seg));
      }
    }

    for (final rawChunkText in pageChunks) {
      final cleanChunkText = DocumentIngestionService._cleanChunkText(rawChunkText);
      if (cleanChunkText.length < 20) continue;

      String question = '';
      String answer = cleanChunkText;
      
      final qMarkIndex = cleanChunkText.indexOf('?');
      if (qMarkIndex != -1 && qMarkIndex < cleanChunkText.length * 2) {
        question = cleanChunkText.substring(0, qMarkIndex + 1).trim();
        answer = cleanChunkText.substring(qMarkIndex + 1).trim();
      } else {
        final firstPeriod = cleanChunkText.indexOf('. ');
        if (firstPeriod != -1 && firstPeriod < 100) {
          question = cleanChunkText.substring(0, firstPeriod + 1).trim();
          answer = cleanChunkText.substring(firstPeriod + 1).trim();
        }
      }

      final tags = DocumentIngestionService.detectAcronymTag(answer);

      final chunk = DocumentChunk(
        sourceDocId: docId,
        domain: domain,
        chunkIndex: chunkIndex++,
        pageNumber: i + 1,
        question: question,
        text: answer,
        sourceLabel: '$fileName, p.${i + 1}',
        source: fileName,
        createdAt: DateTime.now(),
        tags: tags,
      );
      allChunks.add(chunk);
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

    if (wordCount + wordCountInSentence > 80 && buffer.isNotEmpty) {
      chunks.add(buffer.join(' '));
      buffer.clear();
      wordCount = 0;
    }

    buffer.add(cleanSentence);
    wordCount += wordCountInSentence;
  }

  if (buffer.isNotEmpty) {
    final remaining = buffer.join(' ').trim();
    if (remaining.length > 20) {
      chunks.add(remaining);
    }
  }

  return chunks;
}
