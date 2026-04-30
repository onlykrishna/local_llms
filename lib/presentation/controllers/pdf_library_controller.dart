import 'dart:io';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import '../../data/models/pdf_document_meta.dart';
import '../../core/constants/app_constants.dart';
import '../../domain/document_ingestion_service.dart';
import '../../domain/kb_domain.dart';

class PdfLibraryController extends GetxController {
  final DocumentIngestionService _ingestionService = Get.find<DocumentIngestionService>();
  final _uuid = const Uuid();
  
  final RxList<PdfDocumentMeta> documents = <PdfDocumentMeta>[].obs;
  final RxBool isLoading = false.obs;
  
  late Box<PdfDocumentMeta> _box;

  @override
  void onInit() {
    super.onInit();
    _box = Hive.box<PdfDocumentMeta>(AppConstants.pdfLibraryBoxName);
    loadDocuments();
  }

  void loadDocuments() {
    documents.assignAll(_box.values.toList());
    // Sort by date descending
    documents.sort((a, b) => b.embeddedAt.compareTo(a.embeddedAt));
  }

  Future<void> addNewPdf() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final fileName = result.files.single.name;

        // 1. Create ID and metadata
        final id = _uuid.v4();
        
        // 2. Copy file to library
        final internalPath = await _ingestionService.copyFileToLibrary(file);

        final meta = PdfDocumentMeta(
          id: id,
          fileName: fileName,
          internalPath: internalPath,
          originalPath: file.path,
          embeddedAt: DateTime.now(),
          pageCount: 0,
          chunkCount: 0,
          status: 'processing',
          source: 'user_uploaded',
        );

        await _box.put(id, meta);
        loadDocuments();

        // 3. Start ingestion
        _ingestInBackground(id, internalPath);
      }
    } catch (e) {
      Get.snackbar('Error', 'Failed to add PDF: $e');
    }
  }

  Future<void> _ingestInBackground(String id, String path) async {
    try {
      final meta = _box.get(id);
      if (meta == null) return;

      final result = await _ingestionService.ingestDocument(File(path), KbDomain.banking);
      
      final updatedMeta = meta.copyWith(
        status: 'indexed',
        pageCount: result.pageCount,
        chunkCount: result.chunkCount,
      );
      
      await _box.put(id, updatedMeta);
      loadDocuments();
    } catch (e) {
      final meta = _box.get(id);
      if (meta != null) {
        await _box.put(id, meta.copyWith(status: 'failed'));
        loadDocuments();
      }
    }
  }

  Future<void> deletePdf(String id) async {
    try {
      final meta = _box.get(id);
      if (meta == null) return;

      // 1. Delete from ObjectBox (RAG chunks)
      await _ingestionService.deleteFromObjectBox(meta.fileName);

      // 2. Delete physical file
      final file = File(meta.internalPath);
      if (await file.exists()) {
        await file.delete();
      }

      // 3. Delete from Hive
      await _box.delete(id);
      loadDocuments();
      
      Get.snackbar('Success', 'PDF removed from library');
    } catch (e) {
      Get.snackbar('Error', 'Failed to delete PDF: $e');
    }
  }

  Future<void> reIndexPdf(String id) async {
    final meta = _box.get(id);
    if (meta == null) return;

    // Set status to processing
    await _box.put(id, meta.copyWith(status: 'processing'));
    loadDocuments();

    // Re-run ingestion
    _ingestInBackground(id, meta.internalPath);
  }
}
