import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/repositories/chat_repository.dart';
import '../../domain/services/inference_router.dart';
import '../../domain/services/domain_service.dart';
import '../../core/services/settings_service.dart';

enum MessageState { idle, thinking, streaming, cancelled, done, error }

class ChatController extends GetxController {
  final ChatRepository _repository;
  final InferenceRouterService _router = Get.find<InferenceRouterService>();
  final DomainService _domainService = Get.find<DomainService>();
  final SettingsService _settings = Get.find<SettingsService>();
  final _uuid = const Uuid();

  // --- Reactive State -------------------------------------------------------
  final RxList<ChatMessage> messages = <ChatMessage>[].obs;
  final RxBool isGenerating = false.obs;
  final Rx<MessageState> currentMessageState = MessageState.idle.obs;
  final RxString currentResponseText = ''.obs;
  final RxBool isOllamaOnline = false.obs; // kept for backward UI compat

  final TextEditingController inputController = TextEditingController();
  final ScrollController scrollController = ScrollController();

  // --- Internal State -------------------------------------------------------
  final StringBuffer _responseBuffer = StringBuffer();
  StreamSubscription<String>? _currentSubscription;
  String? _currentPlaceholderId;
  Timer? _statusTimer;

  ChatController(this._repository);

  @override
  void onInit() {
    super.onInit();
    _loadHistory();
    _startOllamaStatusLoop();
  }

  @override
  void onClose() {
    _statusTimer?.cancel();
    _currentSubscription?.cancel();
    inputController.dispose();
    scrollController.dispose();
    super.onClose();
  }

  // ---------------------------------------------------------------------------
  // SEND MESSAGE (cancel-safe)
  // ---------------------------------------------------------------------------
  Future<void> sendMessage() async {
    final text = inputController.text.trim();
    if (text.isEmpty) return;

    // If already generating → cancel first, wait for cleanup
    if (isGenerating.value) {
      _cancelCurrentResponse(keepPartial: true);
      await Future.delayed(const Duration(milliseconds: 150));
    }

    inputController.clear();

    // 1. Add user message
    final userMsg = ChatMessage(id: _uuid.v4(), content: text, isUser: true);
    messages.insert(0, userMsg);
    _repository.saveMessage(userMsg);

    // 2. Placeholder for AI response
    final placeholderId = _uuid.v4();
    _currentPlaceholderId = placeholderId;
    _responseBuffer.clear();
    currentResponseText.value = '';
    currentMessageState.value = MessageState.thinking;
    isGenerating.value = true;

    // 3. Build history for context window
    final contextWindow = _settings.contextWindow.value;
    final history = messages
        .skip(1) // skip the user message we just added
        .take(contextWindow)
        .map((m) => {'isUser': m.isUser, 'content': m.content})
        .toList()
        .reversed
        .toList();

    // 4. Stream inference
    final systemPrompt = _domainService.getSystemPrompt();
    final stream = _router.respond(
      userMessage: text,
      systemPrompt: systemPrompt,
      history: history,
    );

    currentMessageState.value = MessageState.streaming;

    _currentSubscription = stream.listen(
      (token) {
        _responseBuffer.write(token);
        currentResponseText.value = _responseBuffer.toString();
        _scrollToBottom();
      },
      onDone: () async {
        currentMessageState.value = MessageState.done;
        isGenerating.value = false;

        final aiMsg = ChatMessage(
          id: placeholderId,
          content: _responseBuffer.toString(),
          isUser: false,
        );
        messages.insert(0, aiMsg);
        await _repository.saveMessage(aiMsg);
        currentResponseText.value = '';
        _currentPlaceholderId = null;
      },
      onError: (e) {
        currentMessageState.value = MessageState.error;
        isGenerating.value = false;
        final errMsg = ChatMessage(
          id: placeholderId,
          content: '⚠️ Error: ${e.toString()}',
          isUser: false,
        );
        messages.insert(0, errMsg);
        _repository.saveMessage(errMsg);
        currentResponseText.value = '';
        _currentPlaceholderId = null;
      },
      cancelOnError: true,
    );
  }

  // ---------------------------------------------------------------------------
  // CANCEL (stop button)
  // ---------------------------------------------------------------------------
  void stopGeneration() => _cancelCurrentResponse(keepPartial: true);

  void _cancelCurrentResponse({bool keepPartial = true}) {
    _currentSubscription?.cancel();
    _currentSubscription = null;
    _router.cancelCurrentRequest();

    final partial = _responseBuffer.toString();
    if (keepPartial && partial.isNotEmpty) {
      // Show partial with [stopped] marker
      final cancelledMsg = ChatMessage(
        id: _currentPlaceholderId ?? _uuid.v4(),
        content: '$partial [stopped]',
        isUser: false,
      );
      messages.insert(0, cancelledMsg);
      _repository.saveMessage(cancelledMsg);
    }

    currentResponseText.value = '';
    _responseBuffer.clear();
    _currentPlaceholderId = null;
    currentMessageState.value = MessageState.cancelled;
    isGenerating.value = false;
  }

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------
  void _loadHistory() async {
    final history = await _repository.getChatHistory();
    messages.assignAll(history.reversed.toList());
  }

  void _startOllamaStatusLoop() {
    _statusTimer = Timer.periodic(const Duration(seconds: 8), (_) async {
      isOllamaOnline.value = await _repository.isOllamaUp();
    });
  }

  void _scrollToBottom() {
    if (scrollController.hasClients) {
      scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void clearChat() async {
    await _repository.clearHistory();
    messages.clear();
    Get.back();
  }
}
