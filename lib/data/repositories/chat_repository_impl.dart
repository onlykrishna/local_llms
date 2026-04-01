import 'dart:async';
import 'package:hive/hive.dart';
import '../../core/network/ollama_client.dart';
import '../../core/services/fallback_dataset_service.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/repositories/chat_repository.dart';
import '../../core/constants/app_constants.dart';

class ChatRepositoryImpl implements ChatRepository {
  final OllamaClient _ollama;
  final FallbackDatasetService _fallback;
  final Box<ChatMessage> _chatBox;

  ChatRepositoryImpl(this._ollama, this._fallback, this._chatBox);

  @override
  Stream<String> getStreamingResponse(String prompt, String model) async* {
    try {
      final isUp = await _ollama.checkServer();
      if (!isUp) {
        // Use local fallback dataset if server is down
        yield* _fallback.getStreamingFallback(prompt);
      } else {
        // Use local LLM
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
