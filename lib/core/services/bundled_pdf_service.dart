import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:hive/hive.dart';
import '../../data/models/pdf_document_meta.dart';
import '../constants/app_constants.dart';
import '../../domain/document_ingestion_service.dart';
import '../../domain/kb_domain.dart';

class BundledPdfService extends GetxService {
  static const List<String> _bundledPdfAssets = [
    // AUTO-GENERATED — do not edit manually
    'assets/pdfs/home_loan_faqs.pdf',
    'assets/pdfs/working_capital_loan_faqs.pdf',
    'assets/pdfs/unsecured_business_loan_faqs.pdf',
    'assets/pdfs/loan_against_property_faqs.pdf',
  ];

  final DocumentIngestionService _ingestionService =
      Get.find<DocumentIngestionService>();
  final _uuid = const Uuid();

  Future<void> init() async {
    await _syncBundledPdfs();
  }

  /// Main sync entry point.
  /// For each asset PDF:
  ///   - Computes SHA-256 hash of the asset bytes
  ///   - Compares against stored hash in Hive
  ///   - If changed/new → delete old embeddings, re-index, store new hash
  ///   - If unchanged → skip
  /// Also handles PDFs that were removed from the config (cleanup).
  Future<void> _syncBundledPdfs() async {
    try {
      final libraryBox =
          Hive.box<PdfDocumentMeta>(AppConstants.pdfLibraryBoxName);
      final hashBox = Hive.box<String>(AppConstants.bundledPdfHashesBoxName);

      final docsDir = await getApplicationDocumentsDirectory();
      final libraryDir =
          Directory(p.join(docsDir.path, 'pdf_library'));
      if (!await libraryDir.exists()) {
        await libraryDir.create(recursive: true);
      }

      // ── Discover asset PDFs ──────────────────────────────────────────────
      List<String> assetPaths = _bundledPdfAssets;

      // Fallback: scan AssetManifest if _bundledPdfAssets is empty
      if (assetPaths.isEmpty) {
        try {
          final manifestContent =
              await rootBundle.loadString('AssetManifest.json');
          final manifestMap =
              json.decode(manifestContent) as Map<String, dynamic>;
          assetPaths = manifestMap.keys
              .where((k) =>
                  k.startsWith('assets/pdfs/') && k.endsWith('.pdf'))
              .toList();
        } catch (_) {}
      }

      // ── Remove PDFs deleted from config ──────────────────────────────────
      final configFileNames = assetPaths
          .map((ap) => p.basename(ap))
          .toSet();

      final staleEntries = libraryBox.values
          .where((doc) =>
              doc.source == 'bundled' &&
              !configFileNames.contains(doc.fileName))
          .toList();

      for (final stale in staleEntries) {
        debugPrint(
            '[BundledPdfService] Removing stale bundled PDF: ${stale.fileName}');
        await _ingestionService.deleteFromObjectBox(stale.fileName);
        final file = File(stale.internalPath);
        if (await file.exists()) await file.delete();
        await libraryBox.delete(stale.id);
        await hashBox.delete(stale.fileName);
      }

      // ── Process each asset PDF ───────────────────────────────────────────
      for (final assetPath in assetPaths) {
        final fileName = p.basename(assetPath);

        // 1. Load asset bytes & compute hash
        late Uint8List assetBytes;
        try {
          final byteData = await rootBundle.load(assetPath);
          assetBytes = byteData.buffer
              .asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);
        } catch (e) {
          debugPrint(
              '[BundledPdfService] Could not load asset $assetPath: $e');
          continue;
        }

        final currentHash = sha256.convert(assetBytes).toString();
        final storedHash = hashBox.get(fileName);

        final existingMeta = libraryBox.values
            .cast<PdfDocumentMeta?>()
            .firstWhere((d) => d?.fileName == fileName, orElse: () => null);

        final isNew = existingMeta == null;
        final isChanged = !isNew && storedHash != currentHash;

        if (!isNew && !isChanged) {
          debugPrint(
              '[BundledPdfService] ✓ No change: $fileName (hash match)');
          continue;
        }

        if (isChanged) {
          debugPrint(
              '[BundledPdfService] 🔄 Content changed: $fileName — re-indexing...');
          // Delete old ObjectBox embeddings
          await _ingestionService.deleteFromObjectBox(fileName);
          // Delete old physical copy
          final oldFile = File(existingMeta!.internalPath);
          if (await oldFile.exists()) await oldFile.delete();
          // Remove old Hive entry
          await libraryBox.delete(existingMeta.id);
        } else {
          debugPrint(
              '[BundledPdfService] ➕ New bundled PDF: $fileName — indexing...');
        }

        // 2. Write bytes to a temp file then copy to library
        final tempFile =
            File(p.join(libraryDir.path, 'temp_$fileName'));
        await tempFile.writeAsBytes(assetBytes);

        final internalPath =
            await _ingestionService.copyFileToLibrary(tempFile);
        if (await tempFile.exists()) await tempFile.delete();

        // 3. Create Hive metadata entry (processing state)
        final id = _uuid.v4();
        final meta = PdfDocumentMeta(
          id: id,
          fileName: fileName,
          internalPath: internalPath,
          originalPath: assetPath,
          embeddedAt: DateTime.now(),
          pageCount: 0,
          chunkCount: 0,
          status: 'processing',
          source: 'bundled',
        );
        await libraryBox.put(id, meta);

        // 4. Run embedding pipeline
        try {
          final result = await _ingestionService.ingestDocument(
              File(internalPath), KbDomain.banking);

          await libraryBox.put(
              id,
              meta.copyWith(
                status: 'indexed',
                pageCount: result.pageCount,
                chunkCount: result.chunkCount,
              ));

          // 5. Store the new hash only after successful indexing
          await hashBox.put(fileName, currentHash);
          debugPrint(
              '[BundledPdfService] ✅ Indexed: $fileName (${result.pageCount} pages, ${result.chunkCount} chunks)');
        } catch (e) {
          await libraryBox.put(id, meta.copyWith(status: 'failed'));
          debugPrint('[BundledPdfService] ❌ Failed to index $fileName: $e');
        }
      }
    } catch (e) {
      debugPrint(
          '[BundledPdfService] Error during PDF sync: $e');
    }
  }
}
