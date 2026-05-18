import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/ai_provider.dart';
import '../models/chat_message.dart';
import 'analytics_service.dart';

class ApiProviderService extends GetxService {

  // Active provider — reactive so UI can observe it
  final Rx<AiProvider> activeProvider = AiProvider.groq.obs;

  // In-memory cache — keyed by SHA-256(provider + message history)
  final Map<String, String> _cache = {};

  // Read API keys from .env at runtime
  String get _openAiKey => dotenv.env['OPENAI_API_KEY'] ?? '';
  String get _groqKey   => dotenv.env['GROQ_API_KEY'] ?? '';

  void switchProvider(AiProvider provider) {
    activeProvider.value = provider;
    // Analytics
    try {
      Get.find<AnalyticsService>().logProviderSwitched(provider.displayName);
    } catch (_) {}
  }

  void clearCache() => _cache.clear();

  String _cacheKey(List<ChatMessage> messages) {
    final content = messages
        .map((m) => '${m.role.name}:${m.content}')
        .join('|');
    return sha256.convert(utf8.encode(content)).toString();
  }

  /// Send a list of messages and return the assistant reply string.
  /// Throws an Exception with a user-friendly message on failure.
  Future<String> sendMessages(List<ChatMessage> messages) async {
    final key = _cacheKey(messages);
    if (_cache.containsKey(key)) return _cache[key]!;

    final provider = activeProvider.value;
    final apiKey = provider == AiProvider.openai ? _openAiKey : _groqKey;

    if (apiKey.isEmpty) {
      throw Exception(
        '${provider.displayName} API key is not configured. '
        'Add it to your .env file.'
      );
    }

    final payload = {
      'model': provider.modelId,
      'messages': messages.map((m) => m.toApiMap()).toList(),
      'max_tokens': 1024,
      'temperature': 0.7,
    };

    final response = await http.post(
      Uri.parse(provider.endpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode(payload),
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = data['choices'] as List<dynamic>;
      if (choices.isEmpty) throw Exception('Empty response from AI.');
      final message = choices[0]['message'] as Map<String, dynamic>;
      final reply = (message['content'] as String).trim();
      _cache[key] = reply;
      return reply;
    } else if (response.statusCode == 401) {
      throw Exception('Invalid API key for ${provider.displayName}.');
    } else if (response.statusCode == 429) {
      throw Exception('Rate limit reached. Please wait and try again.');
    } else {
      final body = jsonDecode(response.body);
      final errorMsg = body['error']?['message'] ?? 'Unknown error';
      throw Exception('${provider.displayName} error: $errorMsg');
    }
  }
}
