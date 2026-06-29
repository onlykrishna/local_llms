import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:flutter_ai_chat_app/app/core/services/voice_service.dart';
import 'package:flutter_ai_chat_app/app/core/services/api_provider_service.dart';
import 'package:flutter_ai_chat_app/app/core/models/chat_message.dart';
import '../../chat/controllers/chat_controller.dart';
import '../../pdf_chat/controllers/pdf_chat_controller.dart';

/// Controls the full-screen live voice conversation loop.
///
/// Message routing:
///   • Messages are sent through the [_sendAndGetReply] callback supplied via
///     [Get.arguments], which wraps the active chat or PDF controller's send
///     function and returns the assistant reply directly.
///   • If no callback is supplied (navigation without arguments), falls back to
///     [Get.find<ChatController>] then [Get.find<PdfChatController>].
///
/// Bug fixes applied vs. original:
///   • Reply is obtained from the `Future<String>` return of the send callback —
///     no more guessing `messages.last.content`.
///   • Error messages are displayed in the status pill but NOT spoken aloud.
///   • [toggleLoop] lets users pause without exiting the screen.
class LiveVoiceController extends GetxController {
  // ── Reactive state ──────────────────────────────────────
  final RxString statusText = 'Tap to start...'.obs;
  final RxBool isListening = false.obs;
  final RxBool isSpeaking = false.obs;
  final RxBool isThinking = false.obs;
  final RxBool isLooping = false.obs;

  // ── Dependencies ─────────────────────────────────────────
  late final VoiceService _voice;

  /// Returns a `Future<String>` with the assistant reply for the given user text.
  /// Throws on API / model errors so we can surface the error in the status pill.
  late final Future<String> Function(String userText) _sendAndGetReply;

  @override
  void onInit() {
    super.onInit();
    _voice = Get.find<VoiceService>();
    _resolveSendCallback();
  }

  // ── Send callback resolution ─────────────────────────────

  void _resolveSendCallback() {
    final args = Get.arguments as Map<String, dynamic>? ?? {};
    final onVoiceSend = args['onVoiceSend'];

    if (onVoiceSend is Future<String> Function(String)) {
      // Preferred path: screen passed a typed Future<String> Function(String)
      _sendAndGetReply = onVoiceSend;
      debugPrint('🎙️ LiveVoiceController: Using typed onVoiceSend callback.');
      return;
    }

    if (onVoiceSend is Function) {
      // Legacy path: onSend passed as a dynamic callable
      _sendAndGetReply = (text) async {
        try {
          final result = await (onVoiceSend as dynamic)(text);
          if (result is String) return result;
        } catch (_) {}
        // Fallback: read last non-error message from controllers
        return _getLastReplyFromControllers();
      };
      debugPrint('🎙️ LiveVoiceController: Using dynamic onVoiceSend callback.');
      return;
    }

    // No callback supplied — resolve controller directly
    _sendAndGetReply = (text) async {
      try {
        final chatCtrl = Get.find<ChatController>();
        await chatCtrl.sendMessage(text);
        return _lastNonErrorContent(chatCtrl.messages
            .map((m) => (content: m.content, isError: m.isError))
            .toList());
      } catch (_) {}
      try {
        final pdfCtrl = Get.find<PdfChatController>();
        await pdfCtrl.sendQuestion(text);
        return _lastNonErrorContent(pdfCtrl.messages
            .map((m) => (content: m.content, isError: m.isError))
            .toList());
      } catch (_) {}
      return '';
    };
    debugPrint(
        '🎙️ LiveVoiceController: No callback — using direct controller lookup.');
  }

  /// Gets the last reply from whichever controller is currently active.
  /// Used as a fallback when the callback does not return a string.
  String _getLastReplyFromControllers() {
    try {
      return _lastNonErrorContent(Get.find<ChatController>()
          .messages
          .map((m) => (content: m.content, isError: m.isError))
          .toList());
    } catch (_) {}
    try {
      return _lastNonErrorContent(Get.find<PdfChatController>()
          .messages
          .map((m) => (content: m.content, isError: m.isError))
          .toList());
    } catch (_) {}
    return '';
  }

  /// Returns the content of the last non-error assistant message, or ''.
  String _lastNonErrorContent(
      List<({String content, bool isError})> messages) {
    for (final m in messages.reversed) {
      if (!m.isError) return m.content;
    }
    return '';
  }

  // ── Loop control ─────────────────────────────────────────

  Future<void> startLoop() async {
    if (isLooping.value) return;

    final apiService = Get.find<ApiProviderService>();
    if (!apiService.isReady) {
      statusText.value = apiService.readinessError ??
          'Provider not configured. Check Settings → AI Engine.';
      return;
    }

    isLooping.value = true;
    statusText.value = 'Listening...';
    _runLoop();
  }

  /// Stops the loop and resets state. Screen stays open so user can restart.
  Future<void> stopLoop() async {
    isLooping.value = false;
    isListening.value = false;
    isThinking.value = false;
    isSpeaking.value = false;
    await _voice.stopSpeaking();
    await _voice.stopListening();
    statusText.value = 'Tap to start...';
  }

  /// Toggles between running and paused. Bound to the main button in the view.
  Future<void> toggleLoop() async {
    if (isLooping.value) {
      await stopLoop();
    } else {
      await startLoop();
    }
  }

  bool _isMessageError(dynamic msg) {
    if (msg == null) return false;
    if (msg is ChatMessage) return msg.isError;
    if (msg is PdfChatMessage) return msg.isError;
    return false;
  }

  String _getMessageContent(dynamic msg) {
    if (msg == null) return '';
    if (msg is ChatMessage) return msg.content;
    if (msg is PdfChatMessage) return msg.content;
    return '';
  }

  // ── Core loop ────────────────────────────────────────────

  Future<void> _runLoop() async {
    while (isLooping.value) {
      try {
        // ── STEP 1: LISTEN ────────────────────────────────────────────
        isListening.value = true;
        isThinking.value = false;
        isSpeaking.value = false;
        statusText.value = 'Listening...';
        _voice.liveTranscript.value = '';
        String userText = '';

        // Use a Completer so we wait for the final STT result
        final completer = Completer<String>();

        await _voice.startListening(
          onResult: (text) {
            if (!completer.isCompleted) {
              completer.complete(text);
            }
          },
          onPartial: (partial) {
            _voice.liveTranscript.value = partial;
            statusText.value = partial.isNotEmpty ? partial : 'Listening...';
          },
        );

        // Wait for result with a timeout
        // If no speech in 10 seconds, treat as silence and loop
        try {
          userText = await completer.future.timeout(
            const Duration(seconds: 10),
            onTimeout: () => '',
          );
        } catch (_) {
          userText = '';
        }

        isListening.value = false;
        if (!isLooping.value) break;

        // ── RELEASE RECOGNIZER before doing anything else ─────────────
        // This is the critical step that prevents error_busy
        await _voice.releaseRecognizer();

        if (!isLooping.value) break;

        // If no speech detected, loop back to listening
        if (userText.trim().isEmpty) {
          statusText.value = 'Listening...';
          continue;
        }

        // ── STEP 2: SEND TO AI ────────────────────────────────────────
        isThinking.value = true;
        statusText.value = 'Thinking...';
        _voice.liveTranscript.value = '';

        final reply = await _sendAndGetReply(userText);

        isThinking.value = false;
        if (!isLooping.value) break;

        // Check for error in the last assistant message
        final lastMsg = _getLastAssistantMessage();
        if (_isMessageError(lastMsg)) {
          statusText.value = _getMessageContent(lastMsg);
          isLooping.value = false;
          break;
        }

        if (reply.trim().isEmpty) {
          statusText.value = 'No response — trying again';
          // Wait before next listen to avoid immediate error_busy
          await Future.delayed(const Duration(milliseconds: 1500));
          continue;
        }

        // ── STEP 4: SPEAK ─────────────────────────────────────────────
        isSpeaking.value = true;
        statusText.value = 'Speaking...';
        await _voice.speak(reply);
        isSpeaking.value = false;

        if (!isLooping.value) break;

        // ── WAIT before next listen cycle ─────────────────────────────
        // Give Android SpeechRecognizer time after TTS completes
        statusText.value = 'Listening...';
        await Future.delayed(const Duration(milliseconds: 800));

        // Loop continues to Step 1

      } catch (e) {
        isListening.value = false;
        isThinking.value = false;
        isSpeaking.value = false;
        debugPrint('🎙️ Voice loop error: $e');
        statusText.value = 'Error — retrying in 2s';
        // Wait longer on errors to let the system recover
        await Future.delayed(const Duration(seconds: 2));
        // continues loop
      }
    }

    isListening.value = false;
    isThinking.value = false;
    isSpeaking.value = false;
    statusText.value = 'Tap to start...';
    isLooping.value = false;
  }

  dynamic _getLastAssistantMessage() {
    try {
      final chatCtrl = Get.find<ChatController>();
      if (chatCtrl.messages.isNotEmpty) {
        return chatCtrl.messages.lastWhere((m) => m.role == MessageRole.assistant);
      }
    } catch (_) {}
    try {
      final pdfCtrl = Get.find<PdfChatController>();
      if (pdfCtrl.messages.isNotEmpty) {
        return pdfCtrl.messages.lastWhere((m) => m.role == PdfChatRole.assistant);
      }
    } catch (_) {}
    return null;
  }

  // ── Close ────────────────────────────────────────────────

  /// Stops the loop and navigates back.
  Future<void> close() async {
    await stopLoop();
    Get.back();
  }

  @override
  void onClose() {
    isLooping.value = false;
    _voice.stopSpeaking();
    _voice.stopListening();
    super.onClose();
  }
}
