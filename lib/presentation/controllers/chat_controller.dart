import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/repositories/chat_repository.dart';
import '../../domain/services/inference_router.dart';
import '../../core/services/settings_service.dart';
import '../../domain/source_citation_service.dart';
import '../../domain/services/on_device_inference_service.dart';

enum MessageState { idle, thinking, streaming, cancelled, done, error }

class ChatController extends GetxController {
  final ChatRepository _repository;
  final InferenceRouterService _router = Get.find<InferenceRouterService>();
  final SettingsService _settings = Get.find<SettingsService>();
  final RxString loadingStage = 'Ready'.obs;
  final SourceCitationService _citationService = Get.find<SourceCitationService>();
  final OnDeviceInferenceService _inferenceService = Get.find<OnDeviceInferenceService>();
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
  // SEND MESSAGE
  // ---------------------------------------------------------------------------
  Future<void> sendMessage() async {
    final text = inputController.text.trim();
    if (text.isEmpty) return;

    if (!_inferenceService.isModelReady.value) {
      await _inferenceService.warmup();
      if (!_inferenceService.isModelReady.value) {
        Get.snackbar('Engine Offline', 'Local engine failed to initialize. Please check model settings or retry.',
            snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.redAccent, colorText: Colors.white);
        return;
      }
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
        .toList();

    final stream = _router.probeAndRoute(text, history).timeout(
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
        
        String finalText = _responseBuffer.toString();
        
        // Add subtle hint if no answer available
        if (finalText.contains('No answer available.')) {
           finalText = '$finalText\n\n*This question could not be answered from the uploaded document.*';
        }

        // Programmatic Citations (Only if not already included in bypass)
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

        final aiMsg = ChatMessage(
          id: placeholderId, 
          content: finalText, 
          isUser: false,
          isFromKb: _router.lastIsFromKb,
        );
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
