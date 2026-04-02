import 'dart:async';
import 'package:hive/hive.dart';
import '../../core/network/ollama_client.dart';
import '../../core/services/fallback_dataset_service.dart';
import '../../core/services/hardware_inference_service.dart';
import '../../core/services/settings_service.dart';
import 'package:get/get.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/repositories/chat_repository.dart';

class ChatRepositoryImpl implements ChatRepository {
  final OllamaClient _ollama;
  final FallbackDatasetService _fallback;
  final HardwareInferenceService _hardware; // New!
  final Box<ChatMessage> _chatBox;

  ChatRepositoryImpl(this._ollama, this._fallback, this._hardware, this._chatBox);

  @override
  Stream<String> getStreamingResponse(String prompt, String model) async* {
    try {
      final settings = Get.find<SettingsService>();
      final isUp = await _ollama.checkServer();
      if (settings.useOfflineMode.value || !isUp) {
        // Priority 1: Real On-Device Hardware AI (Gemma 2B)
        if (_hardware.isReady) {
          yield* _hardware.getHardwareStream(prompt);
        } else {
          // Priority 2: Smart Knowledge Engine (Synthesized JSON)
          yield* _fallback.getStreamingFallback(prompt);
        }
      } else {
        // Use local LLM server
        yield* _ollama.streamChat(prompt, model);
      }
    } catch (e) {
      // Catch-all: always return something offline
      yield* _fallback.getStreamingFallback(prompt);
    }
  }

  @override
  Future<List<ChatMessage>> getChatHistory() async {
    return _chatBox.values.toList().reversed.toList();
  }

  @override
  Future<void> saveMessage(ChatMessage message) async {
    await _chatBox.put(message.id, message);
  }

  @override
  Future<void> clearHistory() async {
    await _chatBox.clear();
  }

  @override
  Future<bool> isOllamaUp() => _ollama.checkServer();
}
