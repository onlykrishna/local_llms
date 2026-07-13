import 'dart:io';
import 'dart:convert';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import '../../../core/models/ai_provider.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/services/api_provider_service.dart';
import '../../../core/services/chat_history_service.dart';
import '../../../core/services/pdf_processing_service.dart';
import '../views/widgets/message_input_bar.dart';
import '../../../routes/app_pages.dart';

class ChatController extends GetxController {

  final ApiProviderService apiProviderService = Get.find<ApiProviderService>();
  final ChatHistoryService chatHistoryService = Get.find<ChatHistoryService>();

  // Image attachment
  final Rx<String?> attachedImagePath = Rx<String?>(null);
  final Rx<String?> attachedImageBase64 = Rx<String?>(null);
  final Rx<String?> attachedImageMime = Rx<String?>(null);

  // PDF attachment
  final RxString attachedPdfText = ''.obs;
  final RxString attachedPdfName = ''.obs;
  final RxBool isExtractingPdf = false.obs;

  // Live Scan state
  final RxBool isLiveScanActive = false.obs;
  final RxString liveScanMode = 'ocr'.obs; // 'ocr' or 'object'
  void Function(String)? onAppendTextCallback;

  void appendText(String text) {
    onAppendTextCallback?.call(text);
  }

  void toggleLiveScan(bool active) {
    isLiveScanActive.value = active;
  }

  // Reactive state
  final RxList<ChatMessage> messages = <ChatMessage>[].obs;
  final RxBool isTyping = false.obs;
  final RxBool isLoadingHistory = false.obs;

  // Each controller instance owns one chat session
  late String chatId;

  @override
  void onInit() {
    super.onInit();
    chatId = const Uuid().v4();
    _loadHistory();
  }

  // ── Load history from Firestore on session start ──
  Future<void> _loadHistory() async {
    isLoadingHistory.value = true;
    try {
      final loaded = await chatHistoryService.loadMessages(chatId);
      messages.assignAll(loaded);
    } catch (e) {
      // Silently fail — history is non-critical
    } finally {
      isLoadingHistory.value = false;
    }
  }

  Future<void> setAttachment(String filePath, AttachmentType type) async {
    if (type == AttachmentType.liveScan) {
      Get.toNamed(AppRoutes.LIVE_SCAN);
      return;
    }

    if (type == AttachmentType.files) {
      // PDF: extract text and store as context — do NOT navigate away
      isExtractingPdf.value = true;
      try {
        final pdfService = Get.find<PdfProcessingService>();
        final pages = await pdfService.extractPagesAsync(filePath);
        final buffer = StringBuffer();
        int charCount = 0;
        for (final page in pages) {
          final pageText = '[Page ${page.key}]\n${page.value}\n\n';
          if (charCount + pageText.length > 8000) {
            buffer.write('[Document truncated — showing first 8000 characters]');
            break;
          }
          buffer.write(pageText);
          charCount += pageText.length;
        }
        attachedPdfText.value = buffer.toString();
        attachedPdfName.value = filePath.split('/').last;
      } catch (e) {
        Get.snackbar(
          'PDF Error',
          'Could not read this PDF: $e',
          snackPosition: SnackPosition.BOTTOM,
        );
      } finally {
        isExtractingPdf.value = false;
      }
      return;
    }

    // Image: read bytes and base64-encode off the main thread
    try {
      final bytes = await File(filePath).readAsBytes();
      final encoded = base64Encode(bytes);
      final mime = filePath.toLowerCase().endsWith('.png')
          ? 'image/png'
          : 'image/jpeg';
      attachedImageBase64.value = encoded;
      attachedImagePath.value = filePath;
      attachedImageMime.value = mime;
    } catch (e) {
      Get.snackbar(
        'Attachment Error',
        'Could not attach file: $e',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  Future<void> sendMessage(String text, {bool voiceMode = false}) async {
    if (isTyping.value) return;

    if (text.trim().isEmpty &&
        attachedImageBase64.value == null &&
        attachedPdfText.value.isEmpty) {
      return;
    }

    // Capture and immediately clear all attachment state
    final imgBase64 = attachedImageBase64.value;
    final imgMime = attachedImageMime.value;
    final pdfText = attachedPdfText.value;
    final pdfName = attachedPdfName.value;

    attachedImageBase64.value = null;
    attachedImageMime.value = null;
    attachedImagePath.value = null;
    attachedPdfText.value = '';
    attachedPdfName.value = '';

    // Build persistent user message (saved to history)
    final userMsg = ChatMessage(
      id: const Uuid().v4(),
      role: MessageRole.user,
      content: text,
      timestamp: DateTime.now(),
      imageBase64: imgBase64,
      imageMimeType: imgMime,
      attachedFileName: pdfName.isNotEmpty ? pdfName : null,
    );
    messages.add(userMsg);
    await chatHistoryService.saveMessage(chatId, userMsg);

    // Build EPHEMERAL API call list — NOT saved to Firestore, NOT added to messages
    final apiMessages = <ChatMessage>[];
    if (pdfText.isNotEmpty) {
      // Truncate to 3000 chars max to stay within free-tier token limits
      final truncated = pdfText.length > 3000
          ? '${pdfText.substring(0, 3000)}\n[...truncated to fit context limit]'
          : pdfText;
      apiMessages.add(ChatMessage(
        id: 'ephemeral-pdf',
        role: MessageRole.system,
        content: 'Document: "$pdfName"\n\n$truncated\n\nAnswer based on this document.',
        timestamp: DateTime.now(),
      ));
    }
    // Include last 6 messages only — prevents context overflow on free-tier APIs
    final recentHistory = messages.length > 6
        ? messages.sublist(messages.length - 6)
        : List<ChatMessage>.from(messages);
    apiMessages.addAll(recentHistory);

    isTyping.value = true;
    try {
      final reply = await apiProviderService.sendMessages(apiMessages, voiceMode: voiceMode);
      final assistantMsg = ChatMessage(
        id: const Uuid().v4(),
        role: MessageRole.assistant,
        content: reply,
        timestamp: DateTime.now(),
      );
      messages.add(assistantMsg);
      await chatHistoryService.saveMessage(chatId, assistantMsg);
    } catch (e) {
      final errorMsg = ChatMessage(
        id: const Uuid().v4(),
        role: MessageRole.assistant,
        content: 'Error: ${e.toString()}',
        timestamp: DateTime.now(),
        isError: true,
      );
      messages.add(errorMsg);
      await chatHistoryService.saveMessage(chatId, errorMsg);
    } finally {
      isTyping.value = false;
    }
  }

  // ── Clear conversation ──
  Future<void> clearConversation() async {
    messages.clear();
    apiProviderService.clearCache();
    await chatHistoryService.deleteChat(chatId);
    chatId = const Uuid().v4();
  }

  // ── Convenience getter for active provider name ──
  String get activeProviderName => apiProviderService.activeProvider.value.displayName;
  Rx<AiProvider> get activeProvider => apiProviderService.activeProvider;
}
