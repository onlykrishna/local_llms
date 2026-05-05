import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:hive/hive.dart' as hive;
import '../../data/models/pdf_document_meta.dart';
import '../../data/document_chunk.dart';
import '../constants/app_constants.dart';
import '../../domain/document_ingestion_service.dart';
import '../../domain/kb_domain.dart';
import '../../objectbox.g.dart';
import '../services/log_service.dart';

class BundledPdfService extends GetxService {
  static const List<String> _bundledPdfAssets = [
    'assets/pdfs/home_loan_faqs.pdf',
    'assets/pdfs/working_capital_loan_faqs.pdf',
    'assets/pdfs/unsecured_business_loan_faqs.pdf',
    'assets/pdfs/loan_against_property_faqs.pdf',
  ];

  final DocumentIngestionService _ingestionService = Get.find<DocumentIngestionService>();
  final Store _store = Get.find<Store>();
  final _uuid = const Uuid();
  late final hive.Box<PdfDocumentMeta> _libraryBox;
  late final hive.Box<String> _hashBox;
  late final hive.Box<dynamic> _settingsBox;

  Future<void> init() async {
    _libraryBox = hive.Hive.box<PdfDocumentMeta>(AppConstants.pdfLibraryBoxName);
    _hashBox = hive.Hive.box<String>(AppConstants.bundledPdfHashesBoxName);
    _settingsBox = hive.Hive.box(AppConstants.settingsBoxName);

    await _syncBundledPdfs();
  }

  Future<void> _syncBundledPdfs() async {
    LogService.to.log('[DIAG] ========= BUNDLED PDF SERVICE START =========');
    
    // Check 1: Version-based Force Re-index
    final storedVersion = _settingsBox.get('kb_version');
    LogService.to.log('[DIAG] Stored KB version: $storedVersion');
    LogService.to.log('[DIAG] Current KB version: ${AppConstants.kbVersion}');

    final bool forceReindex = storedVersion != AppConstants.kbVersion;
    if (forceReindex) {
      LogService.to.log('[DIAG] !!! KB Version mismatch. Triggering forced re-index.');
    }

    // Check 2: ObjectBox chunk count BEFORE indexing
    final chunkBox = _store.box<DocumentChunk>();
    final beforeCount = chunkBox.count();
    LogService.to.log('[DIAG] ObjectBox chunks BEFORE indexing: $beforeCount');

    // Check 3: Asset loading
    final List<String> assetPaths = _bundledPdfAssets;
    for (final assetPath in assetPaths) {
      try {
        final bytes = await rootBundle.load(assetPath);
        LogService.to.log('[DIAG] Asset loaded OK: $assetPath (${bytes.lengthInBytes} bytes)');
      } catch (e) {
        LogService.to.log('[DIAG] ASSET LOAD FAILED: $assetPath → $e');
      }
    }

    if (forceReindex) {
      await _safeReIndex();
    } else {
      LogService.to.log('[BUNDLED] Normal sync: Version matches, skipping.');
    }

    // Check 4: ObjectBox chunk count AFTER indexing  
    final afterCount = chunkBox.count();
    LogService.to.log('[DIAG] ObjectBox chunks AFTER indexing: $afterCount');
    
    LogService.to.log('[DIAG] ========= BUNDLED PDF SERVICE END =========');
  }

  Future<void> _safeReIndex() async {
    LogService.to.log('[BUNDLED] Starting safe re-index...');
    
    final newChunks = <DocumentChunk>[];
    
    for (final assetPath in _bundledPdfAssets) {
      try {
        final byteData = await rootBundle.load(assetPath);
        final bytes = byteData.buffer.asUint8List();
        
        final chunks = await _ingestionService.ingestBytesWithTag(
          bytes: bytes,
          fileName: p.basename(assetPath),
          sourceTag: DocumentIngestionService.extractTag(p.basename(assetPath)),
        );
        
        newChunks.addAll(chunks);
        LogService.to.log('[BUNDLED] Indexed: $assetPath → ${chunks.length} chunks');
      } catch (e) {
        LogService.to.log('[BUNDLED] FAILED to index: $assetPath → $e');
      }
    }
    
    if (newChunks.isEmpty) {
      LogService.to.log('[BUNDLED] ERROR: No chunks generated! Aborting re-index. Old data preserved.');
      return; 
    }
    
    final chunkBox = _store.box<DocumentChunk>();
    final oldBundledQuery = chunkBox.query(
      DocumentChunk_.isHardcoded.equals(false)
      .and(DocumentChunk_.source.contains('faqs'))
    ).build();
    final oldIds = oldBundledQuery.findIds();
    chunkBox.removeMany(oldIds);
    LogService.to.log('[BUNDLED] Removed ${oldIds.length} old bundled chunks');
    oldBundledQuery.close();
    
    chunkBox.putMany(newChunks);
    LogService.to.log('[BUNDLED] Saved ${newChunks.length} new chunks');
    
    await _settingsBox.put('kb_version', AppConstants.kbVersion);
    LogService.to.log('[BUNDLED] Version updated to ${AppConstants.kbVersion}');
  }

  Future<void> nuclearReset() async {
    LogService.to.log('[RESET] Wiping entire ObjectBox database chunks...');
    _store.box<DocumentChunk>().removeAll();
    
    LogService.to.log('[RESET] Clearing KB version from settings...');
    await _settingsBox.delete('kb_version');
    
    LogService.to.log('[RESET] Re-initializing bundled PDFs...');
    await _syncBundledPdfs();
    
    LogService.to.log('[RESET] Done. Chunk count: ${_store.box<DocumentChunk>().count()}');
  }
}
