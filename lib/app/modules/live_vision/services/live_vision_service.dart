import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../../core/services/api_provider_service.dart';

/// Service managing the visual prompt LLM requests.
/// Relies on controller-managed loop for sequential execution.
class LiveVisionService extends GetxService {
  // ── Public reactive state ─────────────────────────────────────────────────

  /// The latest narration / Q&A text returned by the vision model.
  final RxString latestNarration = ''.obs;

  /// True while a vision LLM call is in-flight.
  final RxBool isFetching = false.obs;

  // ── Private state ─────────────────────────────────────────────────────────

  ApiProviderService? _api;

  /// Function the controller provides that snaps the current camera frame.
  /// Accepts a bool specifying if this is a high-quality Q&A query.
  Future<String?> Function({bool isQuery})? _captureFrameBase64;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
    _api = Get.find<ApiProviderService>();
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Register the frame-capture callback supplied by the controller.
  void registerFrameCapture(Future<String?> Function({bool isQuery}) captureCallback) {
    _captureFrameBase64 = captureCallback;
  }

  /// Triggers a single ambient narration query.
  Future<String> triggerAmbientNarration({
    required int generation,
    required int latestUserQueryGeneration,
  }) async {
    return _sendRequest(
      prompt: 'Describe what you currently see in the camera in 1–2 short, '
          'conversational sentences. Focus on the most notable thing in the frame.',
      systemInstruction: _ambientSystemPrompt,
      tag: 'Ambient',
      generation: generation,
      latestUserQueryGeneration: latestUserQueryGeneration,
      prioritizeGroq: false,
    );
  }

  /// Send a user Q&A query with the current camera frame.
  Future<String> sendVisionQuery(
    String userQuestion, {
    required int generation,
    required int latestUserQueryGeneration,
  }) async {
    return _sendRequest(
      prompt: userQuestion,
      systemInstruction: _qaSystemPrompt,
      tag: 'Q&A',
      generation: generation,
      latestUserQueryGeneration: latestUserQueryGeneration,
      prioritizeGroq: true,
      timeout: const Duration(seconds: 7),
    );
  }

  // ── Internal helpers ──────────────────────────────────────────────────────

  Future<String> _sendRequest({
    required String prompt,
    required String systemInstruction,
    required String tag,
    required int generation,
    required int latestUserQueryGeneration,
    required bool prioritizeGroq,
    Duration? timeout,
  }) async {
    if (_captureFrameBase64 == null) {
      debugPrint('👁️ LiveVisionService [$tag]: No frame capture callback registered');
      return '';
    }

    final isQuery = tag == 'Q&A';
    isFetching.value = true;
    try {
      final base64Image = await _captureFrameBase64!(isQuery: isQuery);
      if (base64Image == null || base64Image.isEmpty) {
        debugPrint('👁️ LiveVisionService [$tag]: Frame capture returned null');
        return '';
      }

      // Check generation before sending
      if (generation < latestUserQueryGeneration) {
        debugPrint('👁️ LiveVisionService [$tag]: Stale request cancelled before API call.');
        return '';
      }

      final response = await _api!.sendVisionRequest(
        base64Image: base64Image,
        prompt: prompt,
        systemInstruction: systemInstruction,
        prioritizeGroq: prioritizeGroq,
        timeout: timeout,
      );

      // Check generation after API returns
      if (generation < latestUserQueryGeneration) {
        debugPrint('👁️ LiveVisionService [$tag]: Stale response discarded after API returned.');
        return '';
      }

      final trimmed = response.trim();
      final upper = trimmed.toUpperCase();
      if (upper == 'NO_CHANGE' || upper == 'NO CHANGE' || upper.contains('NO_CHANGE')) {
        debugPrint('👁️ LiveVisionService [$tag]: Scene unchanged (NO_CHANGE).');
        return '';
      }

      if (trimmed.isNotEmpty) {
        latestNarration.value = trimmed;
      }
      debugPrint('👁️ LiveVisionService [$tag]: "$trimmed"');
      return trimmed;
    } catch (e) {
      debugPrint('❌ LiveVisionService [$tag] error: $e');
      return '';
    } finally {
      isFetching.value = false;
    }
  }

  // ── System prompts ─────────────────────────────────────────────────────────

  static const _ambientSystemPrompt =
      'You are a calm, observant AI assistant with vision looking through the user\'s live camera. '
      'Describe what you see in 1–2 short, natural spoken sentences. '
      'If the image contains readable text that poses a question, a problem, or something to solve '
      '(e.g., quiz questions, exam questions, math problems, worksheet items), do NOT describe that text exists — '
      'instead, read it and give the actual answer(s) directly and concisely, as if you were being asked the question yourself. '
      'If the same questions or scene are still visible and you have already answered them, output ONLY the exact text "NO_CHANGE". '
      'Only fall back to describing the general scene if there is no answerable question or task visible. '
      'Do NOT use bullet points or markdown.';

  static const _qaSystemPrompt =
      'You are a helpful AI assistant with vision looking through the user\'s live camera. '
      'Answer the user\'s question using what you see in the camera frame as context. '
      'If the user asks a generic question like "what does this say", "answer this", or similar, '
      'and the frame contains visible questions, problems, or tasks, prioritize solving and answering them directly. '
      'If the user asks a specific question unrelated to the text in frame, answer their actual question. '
      'Keep your answer to 2–3 short, natural spoken sentences. '
      'Do NOT use bullet points or markdown. Be direct and conversational.';
}
