import '../../domain/entities/chat_message.dart';

abstract class ChatRepository {
  /// Stream response from LLM, or fallback if offline
  Stream<String> getStreamingResponse(String prompt, String model);

  /// Fetch previous messages from Hive
  Future<List<ChatMessage>> getChatHistory();

  /// Save message to Hive
  Future<void> saveMessage(ChatMessage message);

  /// Clear all messages
  Future<void> clearHistory();

  /// Check connectivity to Ollama
  Future<bool> isOllamaUp();
}
