import 'dart:io';
import 'package:get/get.dart';
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
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      final int pageCount = document.pages.count;
      sourceDoc.pageCount = pageCount;
      docBox.put(sourceDoc);

      List<DocumentChunk> allChunks = [];
      
      // Extract and chunk text
      for (int i = 0; i < pageCount; i++) {
        final PdfTextExtractor extractor = PdfTextExtractor(document);
        String text = extractor.extractText(startPageIndex: i, endPageIndex: i);
        text = _cleanText(text);

        final chunks = _chunkText(text, i + 1, fileName, domain.name, docId);
        allChunks.addAll(chunks);
        ingestionProgress.value = (i / pageCount) * 0.5; // 50% for extraction
      }
      document.dispose();

      // Embed chunks
      final int totalChunks = allChunks.length;
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
        ingestionProgress.value = 0.5 + ((end / totalChunks) * 0.5); // remaining 50%
      }

      sourceDoc.status = 'ready';
      sourceDoc.chunkCount = totalChunks;
      docBox.put(sourceDoc);
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

  List<DocumentChunk> _chunkText(String text, int pageNumber, String fileName, String domain, int docId) {
    List<DocumentChunk> chunks = [];
    int chunkIndex = 0;

    // FAQ detection: lines starting with "Q:", "Question:", or "?"
    final faqRegex = RegExp(r'^(Q:|Question:|\?|Q\d+:)\s*(.*)', multiLine: true, caseSensitive: false);
    final matches = faqRegex.allMatches(text).toList();

    if (matches.isNotEmpty) {
      // It's a FAQ document
      for (int i = 0; i < matches.length; i++) {
        final currentMatch = matches[i];
        final nextMatch = (i + 1 < matches.length) ? matches[i + 1] : null;
        
        int startIndex = currentMatch.start;
        int endIndex = nextMatch?.start ?? text.length;
        
        String pairText = text.substring(startIndex, endIndex).trim();
        
        if (pairText.split(' ').length > 400) {
           // Split long Q&A pair using sliding window, keeping the question first
           String questionPart = currentMatch.group(0) ?? '';
           final slidingChunks = _slidingWindowChunk(pairText, 300, 50);
           for (var sc in slidingChunks) {
             String chunkText = sc;
             if (!sc.startsWith(questionPart)) {
                chunkText = '$questionPart\n...\n$sc';
             }
             chunks.add(_createChunk(chunkText, pageNumber, fileName, domain, docId, chunkIndex++));
           }
        } else {
           chunks.add(_createChunk(pairText, pageNumber, fileName, domain, docId, chunkIndex++));
        }
      }
    } else {
      // Normal sliding window chunking
      final slidingChunks = _slidingWindowChunk(text, 300, 50);
      for (var sc in slidingChunks) {
        chunks.add(_createChunk(sc, pageNumber, fileName, domain, docId, chunkIndex++));
      }
    }

    return chunks;
  }

  List<String> _slidingWindowChunk(String text, int maxWords, int overlapWords) {
    List<String> results = [];
    final sentences = text.split(RegExp(r'(?<=[.!?\n])\s+'));
    
    List<String> currentChunk = [];
    int currentWordCount = 0;

    for (var sentence in sentences) {
      final words = sentence.split(RegExp(r'\s+'));
      
      if (currentWordCount + words.length > maxWords && currentChunk.isNotEmpty) {
        results.add(currentChunk.join(' '));
        
        // Keep overlap sentences
        List<String> overlapChunk = [];
        int overlapCount = 0;
        for (int i = currentChunk.length - 1; i >= 0; i--) {
           final sWords = currentChunk[i].split(RegExp(r'\s+')).length;
           if (overlapCount + sWords <= overlapWords) {
             overlapChunk.insert(0, currentChunk[i]);
             overlapCount += sWords;
           } else {
             break;
           }
        }
        currentChunk = List.from(overlapChunk);
        currentWordCount = overlapCount;
      }
      
      currentChunk.add(sentence);
      currentWordCount += words.length;
    }
    
    if (currentChunk.isNotEmpty) {
      results.add(currentChunk.join(' '));
    }
    
    return results;
  }

  DocumentChunk _createChunk(String text, int pageNumber, String fileName, String domain, int docId, int chunkIndex) {
    return DocumentChunk(
      sourceDocId: docId,
      domain: domain,
      chunkIndex: chunkIndex,
      pageNumber: pageNumber,
      text: text,
      sourceLabel: '$fileName, p.$pageNumber',
      createdAt: DateTime.now(),
    );
  }
}
