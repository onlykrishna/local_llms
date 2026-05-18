import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/pdf_document.dart';
import '../../../core/models/pdf_chunk.dart';
import '../../../core/services/pdf_chat_service.dart';
import '../../../core/services/embedding_service.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../routes/app_pages.dart';

enum PdfChatRole { user, assistant }

class PdfChatMessage {
  final String id;
  final PdfChatRole role;
  final String content;
  final List<ChunkCitation> citations;
  final DateTime timestamp;
  final bool isError;

  PdfChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.citations = const [],
    required this.timestamp,
    this.isError = false,
  });
}

class PdfChatController extends GetxController {

  final PdfChatService _service = Get.find<PdfChatService>();

  // ── Documents ──
  final RxList<PdfDocument> documents = <PdfDocument>[].obs;
  final RxBool isLoadingDocs = false.obs;

  // ── Upload state ──
  final RxBool isUploading = false.obs;
  final RxString uploadStage = ''.obs;
  final RxDouble uploadProgress = 0.0.obs;

  // ── Chat state ──
  final RxList<PdfChatMessage> messages = <PdfChatMessage>[].obs;
  final RxBool isThinking = false.obs;

  // ── Selected documents filter (empty = all docs) ──
  final RxList<String> selectedDocIds = <String>[].obs;

  @override
  void onInit() {
    super.onInit();
    _initialize();
  }

  Future<void> _initialize() async {
    await _clearStaleChunksIfProviderChanged();
    await _initWithValidation();
    loadDocuments();
  }

  Future<void> _clearStaleChunksIfProviderChanged() async {
    final storage = Get.find<StorageService>();
    final embeddingService = Get.find<EmbeddingService>();

    // Store which provider was last used
    final lastProvider =
        storage.getString('lastEmbeddingProvider') ?? '';
    final currentProvider = embeddingService.activeProviderName;

    if (lastProvider != currentProvider && lastProvider.isNotEmpty) {
      // Provider changed — old chunks have wrong dimensions
      debugPrint(
        '🔄 Embedding provider changed: '
        '$lastProvider → $currentProvider. '
        'Clearing stale chunks...'
      );
      await _service.clearAllChunks();
      documents.clear();
      Get.snackbar(
        'Embedding provider updated',
        'Your PDFs need to be re-uploaded to use '
        '$currentProvider embeddings.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 6),
      );
    }

    // Save current provider for next launch comparison
    await storage.setString(
        'lastEmbeddingProvider', currentProvider);
  }

  // ── Init: validate connection then load docs ──
  Future<void> _initWithValidation() async {
    try {
      final embeddingService = Get.find<EmbeddingService>();
      final validation = await embeddingService.validateAndLog();
      debugPrint('🔍 Embedding validation: $validation');
    } catch (e) {
      debugPrint('⚠️ Embedding validation failed: $e');
    }
  }

  Future<void> loadDocuments() async {
    isLoadingDocs.value = true;
    try {
      final docs = await _service.loadDocuments();
      documents.assignAll(docs);
      if (docs.isNotEmpty) {
        final storage = Get.find<StorageService>();
        await storage.setBool('setupComplete', true);
        if (Get.currentRoute == AppRoutes.SETUP) {
          Get.offAllNamed(AppRoutes.CHAT);
        }
      }
    } catch (e) {
      Get.snackbar('Error', 'Failed to load documents: $e',
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      isLoadingDocs.value = false;
    }
  }

  // ── Pick and upload a PDF ──
  Future<void> pickAndUploadPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: false,
      withReadStream: false,
    );

    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path == null) return;

    final fileName = file.name;

    // Check for duplicate
    final isDuplicate = documents.any((d) => d.fileName == fileName);
    if (isDuplicate) {
      Get.snackbar(
        'Already uploaded',
        '$fileName has already been indexed.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    isUploading.value = true;
    uploadProgress.value = 0;
    uploadStage.value = 'Starting...';

    try {
      final doc = await _service.uploadAndIndex(
        filePath: file.path!,
        fileName: fileName,
        onProgress: (stage, progress) {
          uploadStage.value = stage;
          uploadProgress.value = progress;
        },
      );
      documents.insert(0, doc);

      try {
        final storage = Get.find<StorageService>();
        await storage.setBool('setupComplete', true);
      } catch (e) {
        debugPrint("⚠️ Failed to write setupComplete on upload: $e");
      }

      HapticFeedback.mediumImpact();

      try {
        Get.find<AnalyticsService>().logPdfUploaded(doc.pageCount);
      } catch (_) {}

      final provider = Get.find<EmbeddingService>().activeProviderName;
      Get.snackbar(
        'Success ✓',
        '"$fileName" indexed with $provider embeddings.',
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar('Upload failed', e.toString(),
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      isUploading.value = false;
      uploadProgress.value = 0;
      uploadStage.value = '';
    }
  }

  // ── Delete a document ──
  Future<void> deleteDocument(PdfDocument doc) async {
    await _service.deleteDocument(doc.id);
    documents.remove(doc);
    selectedDocIds.remove(doc.id);
    Get.snackbar('Deleted', '"${doc.fileName}" removed.',
        snackPosition: SnackPosition.BOTTOM);
  }

  // ── Re-index a document with current embedding model ──
  Future<void> reIndexDocument(PdfDocument doc) async {
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Re-index PDF?'),
        content: Text(
          'This will re-generate embeddings for "${doc.fileName}" '
          'using the current embedding model (${Get.find<EmbeddingService>().activeProviderName}). '
          'Existing chunks will be replaced.',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Get.back(result: true),
            child: const Text('Re-index'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _service.deleteChunksForDocument(doc.id);
    documents.remove(doc);
    selectedDocIds.remove(doc.id);

    Get.snackbar(
      'Chunks cleared',
      'Please re-upload "${doc.fileName}" to re-index it.',
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  // ── Toggle a doc in the selection filter ──
  void toggleDocSelection(String docId) {
    if (selectedDocIds.contains(docId)) {
      selectedDocIds.remove(docId);
    } else {
      selectedDocIds.add(docId);
    }
  }

  // ── Purge all data (emergency) ──
  Future<void> purgeAllData() async {
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Purge all data?'),
        content: const Text(
          'This will delete ALL uploaded PDFs and ALL indexed chunks from '
          'your account. This is recommended if you are seeing incorrect answers '
          'after an app update.',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Get.back(result: true),
            child: const Text('Purge Everything', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    isThinking.value = true;
    try {
      await _service.clearAllChunks();
      documents.clear();
      selectedDocIds.clear();
      messages.clear();
      Get.snackbar('System Purge', 'All PDF data has been wiped.',
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('Purge failed', e.toString(),
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      isThinking.value = false;
    }
  }

  // ── Send a question to the RAG pipeline ──
  Future<void> sendQuestion(String question) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty || isThinking.value) return;

    messages.add(PdfChatMessage(
      id: const Uuid().v4(),
      role: PdfChatRole.user,
      content: trimmed,
      timestamp: DateTime.now(),
    ));

    isThinking.value = true;

    try {
      final (chunks, citations) = await _service.retrieveChunks(
        query: trimmed,
        filterDocIds: selectedDocIds.isEmpty ? null : selectedDocIds.toList(),
      );

      final answer = await _service.generateAnswer(
        question: trimmed,
        chunks: chunks,
      );

      messages.add(PdfChatMessage(
        id: const Uuid().v4(),
        role: PdfChatRole.assistant,
        content: answer,
        citations: citations,
        timestamp: DateTime.now(),
      ));

      try {
        Get.find<AnalyticsService>().logPdfQueried();
      } catch (_) {}

    } catch (e) {
      messages.add(PdfChatMessage(
        id: const Uuid().v4(),
        role: PdfChatRole.assistant,
        content: e.toString().replaceFirst('Exception: ', ''),
        timestamp: DateTime.now(),
        isError: true,
      ));
    } finally {
      isThinking.value = false;
    }
  }
}
