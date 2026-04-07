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
  final RxBool isOllamaOnline = false.obs; 

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

    // FEATURE 3: Greeting interception for All domain categories
    if (_isCommonGreeting(text)) {
      _handleInterception(text);
      return;
    }

    if (isGenerating.value) {
      _cancelCurrentResponse(keepPartial: true);
      await Future.delayed(const Duration(milliseconds: 150));
    }

    inputController.clear();
    final userMsg = ChatMessage(id: _uuid.v4(), content: text, isUser: true);
    messages.insert(0, userMsg);
    _repository.saveMessage(userMsg);

    final placeholderId = _uuid.v4();
    _currentPlaceholderId = placeholderId;
    _responseBuffer.clear();
    currentResponseText.value = '';
    currentMessageState.value = MessageState.thinking;
    isGenerating.value = true;

    final contextWindow = _settings.contextWindow.value;
    final history = messages
        .skip(1)
        .take(contextWindow)
        .map((m) => {'isUser': m.isUser, 'content': m.content})
        .toList()
        .reversed
        .toList();

    final systemPrompt = _domainService.getSystemPrompt();
    
    final stream = _router.respond(
      userMessage: text,
      systemPrompt: systemPrompt,
      history: history,
    ).timeout(
      const Duration(seconds: 360),
      onTimeout: (sink) {
        sink.addError('Response timed out. Please check your connectivity or model status.');
        sink.close();
      },
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
        final aiMsg = ChatMessage(id: placeholderId, content: _responseBuffer.toString(), isUser: false);
        messages.insert(0, aiMsg);
        await _repository.saveMessage(aiMsg);
        currentResponseText.value = '';
        _currentPlaceholderId = null;
      },
      onError: (e, _) {
        currentMessageState.value = MessageState.error;
        isGenerating.value = false;
        final errMsg = ChatMessage(id: placeholderId, content: '⚠️ $e', isUser: false);
        messages.insert(0, errMsg);
        _repository.saveMessage(errMsg);
        currentResponseText.value = '';
        _currentPlaceholderId = null;
      },
      cancelOnError: true,
    );
  }

  // Intercept common greetings to avoid unnecessary AI routing latency
  bool _isCommonGreeting(String text) {
    final greetings = {'hi', 'hello', 'hey', 'namaste', 'hlo', 'hii', 'hi there', 'hello there', 'greeting', 'greetings'};
    return greetings.contains(text.toLowerCase());
  }

  void _handleInterception(String text) async {
    inputController.clear();
    final userMsg = ChatMessage(id: _uuid.v4(), content: text, isUser: true);
    messages.insert(0, userMsg);
    _repository.saveMessage(userMsg);

    isGenerating.value = true;
    currentMessageState.value = MessageState.streaming;
    
    final domainName = _domainService.selectedDomain.value.name.capitalizeFirst;
    // Virtual streaming for instant feedback
    final response = 'Hello! I am your Ethereal Intelligence. How can I assist you in the $domainName domain today?';
    final words = response.split(' ');
    
    for (var i = 0; i < words.length; i++) {
        await Future.delayed(const Duration(milliseconds: 30));
        _responseBuffer.write('${words[i]} ');
        currentResponseText.value = _responseBuffer.toString();
        _scrollToBottom();
    }

    final aiMsg = ChatMessage(id: _uuid.v4(), content: response, isUser: false);
    messages.insert(0, aiMsg);
    await _repository.saveMessage(aiMsg);
    
    currentResponseText.value = '';
    _responseBuffer.clear();
    isGenerating.value = false;
    currentMessageState.value = MessageState.done;
  }

  void stopGeneration() => _cancelCurrentResponse(keepPartial: true);

  void _cancelCurrentResponse({bool keepPartial = true}) {
    _currentSubscription?.cancel();
    _currentSubscription = null;
    _router.cancelCurrentRequest();

    final partial = _responseBuffer.toString();
    if (keepPartial && partial.isNotEmpty) {
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
      scrollController.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  void clearChat() async {
    await _repository.clearHistory();
    messages.clear();
    Get.back();
  }
}
