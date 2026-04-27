import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/repositories/chat_repository.dart';
import '../../domain/services/inference_router.dart';
import '../../domain/services/domain_service.dart';
import '../../domain/services/expert_knowledge_base.dart';
import '../../core/services/settings_service.dart';
import '../../domain/models/inference_domain.dart';
import '../../domain/source_citation_service.dart';
import '../../domain/services/on_device_inference_service.dart';
import '../../domain/services/factual_hardening_service.dart';

enum MessageState { idle, thinking, streaming, cancelled, done, error }

class ChatController extends GetxController {
  final ChatRepository _repository;
  final InferenceRouterService _router = Get.find<InferenceRouterService>();
  final DomainService _domainService = Get.find<DomainService>();
  final SettingsService _settings = Get.find<SettingsService>();
  final RxString loadingStage = 'Ready'.obs;
  final SourceCitationService _citationService = Get.find<SourceCitationService>();
  final OnDeviceInferenceService _inferenceService = Get.find<OnDeviceInferenceService>();
  final FactualHardeningService _hardening = Get.find<FactualHardeningService>();
  final _uuid = const Uuid();

  // --- Reactive State -------------------------------------------------------
  final RxList<ChatMessage> messages = <ChatMessage>[].obs;
  final RxBool isGenerating = false.obs;
  final Rx<MessageState> currentMessageState = MessageState.idle.obs;
  final RxString currentResponseText = ''.obs;
  final RxBool isOllamaOnline = false.obs;
  final RxBool isModelInitializing = false.obs; 

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
    
    // Bind loading states from the inference service
    loadingStage.value = _inferenceService.loadingStage.value;
    ever(_inferenceService.loadingStage, (val) => loadingStage.value = val);
    
    isModelInitializing.value = _inferenceService.isLoading.value;
    ever(_inferenceService.isLoading, (val) => isModelInitializing.value = val);
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
  // SEND MESSAGE (Step 2: Domain Enforcement)
  // ---------------------------------------------------------------------------
  Future<void> sendMessage({bool skipGuard = false}) async {
    final text = inputController.text.trim();
    if (text.isEmpty) return;

    // SCENARIO 5: Greeting Interception (Scenario 5.1/5.2)
    // Runs before domain validation for < 50ms UX.
    if (_isCommonGreeting(text)) {
      _handleInterception(text);
      return;
    }

    if (!_inferenceService.isModelReady.value) {
      // warmup() now handles concurrency internally and waits for any in-progress init
      await _inferenceService.warmup();
      
      if (!_inferenceService.isModelReady.value) {
        Get.snackbar('Engine Offline', 'Local engine failed to initialize. Please check model settings or retry.',
            snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.redAccent, colorText: Colors.white);
        return;
      }
    }

    // STEP 2: Intent Validation (Before Inference)
    final validation = _domainService.detectQueryDomain(text);
    if (!skipGuard && _settings.enableDomainValidation.value) {
      // Lowered to 0.5 so single-keyword matches (e.g. 'coding', 'abstract class') trigger the prompt
      if (!validation.isMatched && validation.confidence >= 0.5) {
        _showDomainSwitchPrompt(text, validation.detectedDomain, validation.confidence);
        return;
      }
    }

    if (isGenerating.value) {
      _cancelCurrentResponse(keepPartial: true);
      await Future.delayed(const Duration(milliseconds: 150));
    }

    // SCENARIO 3: Neural Expert Knowledge Base (Disabled per user request to prioritize RAG)
    /*
    final expertAnswer = ExpertKnowledgeBase.probe(text, _domainService.selectedDomain.value);
    if (expertAnswer != null) {
        _handleExpertInterception(text, expertAnswer);
        return;
    }
    */

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

    // STEP 3: Domain-Aware Routing
    final selectedDomain = _domainService.selectedDomain.value;
    
    final stream = _router.probeAndRoute(
      userMessage: text,
      selectedDomain: selectedDomain,
      history: history,
    ).timeout(
      const Duration(seconds: 360),
      onTimeout: (sink) {
        sink.addError('Connection Timed Out.');
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
        
        final rawText = _responseBuffer.toString();
        // 1. Aggressive sanitization (remove [1], [Source: ...], etc.)
        String finalText = _hardening.sanitizeOutput(rawText);
        
        // 2. Programmatic Citations (Only if not already included in bypass)
        final bool hasSourcesAlready = finalText.contains('**Sources**');
        if (!hasSourcesAlready && _router.lastRetrievedChunks != null && _router.lastRetrievedChunks!.isNotEmpty) {
          final citations = _citationService.buildCitations(_router.lastRetrievedChunks!);
          if (citations.isNotEmpty) {
             final buffer = StringBuffer();
             buffer.writeln('\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
             for (final c in citations) {
                buffer.writeln('[${c.index}] ${c.fileName}, p.${c.pageNumber}');
             }
             finalText = '$finalText${buffer.toString()}';
          }
        }

        final aiMsg = ChatMessage(id: placeholderId, content: finalText, isUser: false);
        messages.insert(0, aiMsg);
        await _repository.saveMessage(aiMsg);
        currentResponseText.value = '';
        _currentPlaceholderId = null;
        _router.lastRetrievedChunks = null; // Clear for next turn
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

  void _showDomainSwitchPrompt(String text, InferenceDomain detected, double confidence) {
    Get.snackbar(
      'Expert Domain Mismatch',
      'This query fits the ${detected.label} Persona (Score: ${(confidence * 100).toInt()}). Switch for expert results?',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.indigoAccent.withOpacity(0.95),
      colorText: Colors.white,
      duration: const Duration(seconds: 8),
      mainButton: TextButton(
        onPressed: () {
          _domainService.changeDomain(detected);
          Get.back(); // Dismiss Snackbar
          inputController.text = text; // Restore for retry
          sendMessage(skipGuard: true); // Force bypass validation for the retried message
        },
        child: const Text('SWITCH', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  bool _isCommonGreeting(String text) {
    final greetings = {'hi', 'hello', 'hey', 'namaste', 'hlo', 'hii', 'hi there', 'hello there', 'greeting', 'greetings'};
    return greetings.contains(text.toLowerCase());
  }

  void _handleExpertInterception(String text, String response) async {
    inputController.clear();
    final userMsg = ChatMessage(id: _uuid.v4(), content: text, isUser: true);
    messages.insert(0, userMsg);
    _repository.saveMessage(userMsg);

    isGenerating.value = true;
    currentMessageState.value = MessageState.streaming;

    final words = response.split(' ');
    for (var i = 0; i < words.length; i++) {
        await Future.delayed(const Duration(milliseconds: 25));
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

  void _handleInterception(String text) async {
    inputController.clear();
    final userMsg = ChatMessage(id: _uuid.v4(), content: text, isUser: true);
    messages.insert(0, userMsg);
    _repository.saveMessage(userMsg);

    isGenerating.value = true;
    currentMessageState.value = MessageState.streaming;
    
    final domainName = _domainService.selectedDomain.value.name.capitalizeFirst;
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
