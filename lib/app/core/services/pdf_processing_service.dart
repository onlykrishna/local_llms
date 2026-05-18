import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:get/get.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'storage_service.dart';

class PdfProcessingService extends GetxService {

  final FirebaseStorage _storage = FirebaseStorage.instance;
  final StorageService _storageService = Get.find<StorageService>();

  // ── Upload PDF bytes to Firebase Storage ──
  // Returns the download URL.
  Future<String> uploadToStorage({
    required String localPath,
    required String docId,
    required String fileName,
    required void Function(double progress) onProgress,
  }) async {
    final uid = _storageService.getUid()!;
    final ref = _storage
        .ref()
        .child('users/$uid/pdfs/$docId/$fileName');

    final file = File(localPath);
    final uploadTask = ref.putFile(file);

    uploadTask.snapshotEvents.listen((snapshot) {
      final progress = snapshot.bytesTransferred / snapshot.totalBytes;
      onProgress(progress);
    });

    await uploadTask;
    return await ref.getDownloadURL();
  }

  // ── Extract text page-by-page from a PDF file ──
  // Returns a list of (pageNumber, pageText) tuples.
  // Uses syncfusion_flutter_pdf.
  List<MapEntry<int, String>> extractPages(String filePath) {
    final List<MapEntry<int, String>> pages = [];
    final document = PdfDocument(inputBytes: File(filePath).readAsBytesSync());
    final extractor = PdfTextExtractor(document);

    for (int i = 0; i < document.pages.count; i++) {
      final text = extractor
          .extractText(startPageIndex: i, endPageIndex: i)
          .trim();
      if (text.isNotEmpty) {
        pages.add(MapEntry(i + 1, text)); // 1-based page number
      }
    }

    document.dispose();
    return pages;
  }

  // ── Split page text into overlapping chunks ──
  // targetTokens: approximate tokens per chunk (~4 chars per token)
  // overlap: number of characters to repeat at start of next chunk
  List<MapEntry<int, String>> chunkPages(
    List<MapEntry<int, String>> pages, {
    int targetChars = 1000,  // ~250 tokens — more granular for better retrieval
    int overlapChars = 150,  // 15% overlap
  }) {
    final List<MapEntry<int, String>> chunks = [];

    for (final page in pages) {
      final pageNum = page.key;
      final text = page.value;

      if (text.length <= targetChars) {
        chunks.add(MapEntry(pageNum, text));
      } else {
        int start = 0;
        while (start < text.length) {
          final end = (start + targetChars).clamp(0, text.length);
          chunks.add(MapEntry(pageNum, text.substring(start, end).trim()));
          start += targetChars - overlapChars;
          if (start >= text.length) break;
        }
      }
    }

    return chunks.where((c) => c.value.trim().length > 50).toList();
  }

  // ── Generate a stable chunk ID using SHA-256 ──
  String chunkId(String docId, int chunkIndex) {
    final input = '$docId:$chunkIndex';
    return sha256.convert(utf8.encode(input)).toString().substring(0, 20);
  }
}
