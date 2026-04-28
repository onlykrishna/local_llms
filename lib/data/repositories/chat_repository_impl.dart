import 'dart:async';
import 'package:hive/hive.dart';
import '../../core/network/ollama_client.dart';
import '../../core/services/fallback_dataset_service.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/repositories/chat_repository.dart';

/// Simplified repository — inference routing is now handled by InferenceRouterService.
/// This impl handles: history (Hive), Ollama health check, and fallback dataset.
class ChatRepositoryImpl implements ChatRepository {
  final OllamaClient _ollama;
  final FallbackDatasetService _fallback;
  final Box<ChatMessage> _chatBox;

  ChatRepositoryImpl(this._ollama, this._fallback, this._chatBox);

  @override
  Stream<String> getStreamingResponse(String prompt, String model) async* {
    // Kept for backward compat — ChatController now calls InferenceRouterService directly
    yield* _fallback.getStreamingFallback(prompt);
  }

  @override
  Future<List<ChatMessage>> getChatHistory() async {
    return _chatBox.values.toList();
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
