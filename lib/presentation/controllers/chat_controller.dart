import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/repositories/chat_repository.dart';
import '../../core/services/settings_service.dart';
import 'package:uuid/uuid.dart';

class ChatController extends GetxController {
  final ChatRepository _repository;
  final SettingsService _settings = Get.find<SettingsService>();
  final Uuid _uuid = const Uuid();

  // Observable state
  final RxList<ChatMessage> messages = <ChatMessage>[].obs;
  final RxBool isLoading = false.obs;
  final RxBool isOllamaOnline = false.obs;
  final RxString currentResponseText = ''.obs;

  final TextEditingController inputController = TextEditingController();
  final ScrollController scrollController = ScrollController();

  ChatController(this._repository);

  @override
  void onInit() {
    super.onInit();
    _loadHistory();
    _checkServerStatusLoop();
  }

  void _loadHistory() async {
    final history = await _repository.getChatHistory();
    messages.assignAll(history);
  }

  void _checkServerStatusLoop() {
    Timer.periodic(const Duration(seconds: 10), (timer) async {
      isOllamaOnline.value = await _repository.isOllamaUp();
    });
  }

  /// Send message and handle streaming response
  Future<void> sendMessage() async {
    final String query = inputController.text.trim();
    if (query.isEmpty || isLoading.isTrue) return;

    inputController.clear();
    
    // Add user message
    final userMsg = ChatMessage(id: _uuid.v4(), content: query, isUser: true);
    messages.insert(0, userMsg);
    await _repository.saveMessage(userMsg);

    // Prepare AI response message
    isLoading.value = true;
    currentResponseText.value = '';
    final aiId = _uuid.v4();
    
    try {
      final String model = _settings.selectedModel.value;
      final responseStream = _repository.getStreamingResponse(query, model);
      
      await for (final chunk in responseStream) {
        currentResponseText.value += chunk;
        _scrollToBottom();
      }

      // Finalize message and save
      final aiMsg = ChatMessage(id: aiId, content: currentResponseText.value, isUser: false);
      messages.insert(0, aiMsg);
      await _repository.saveMessage(aiMsg);
    } catch (e) {
      Get.snackbar('Error', 'Communication failed: $e', snackPosition: SnackPosition.BOTTOM);
    } finally {
      isLoading.value = false;
      currentResponseText.value = '';
    }
  }

  void _scrollToBottom() {
    if (scrollController.hasClients) {
      scrollController.animateTo(
        0.0, // Because standard list is reversed
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void clearChat() async {
    await _repository.clearHistory();
    messages.clear();
    Get.back(); // close drawer/menu
  }
}
