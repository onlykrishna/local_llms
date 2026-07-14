import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/ai_provider.dart';
import '../models/chat_message.dart';
import 'analytics_service.dart';
import 'local_llm_service.dart';

/// Central service that manages the active AI provider, API key storage/retrieval,
/// and message routing to the correct backend (OpenAI, Groq, Gemini, or on-device llama.cpp).
class ApiProviderService extends GetxService {
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // ── Reactive state ──────────────────────────────────────
  final Rx<AiProvider> activeProvider = AiProvider.groq.obs;

  /// Reactive key observers for settings UI binding.
  final RxString openAiKey = ''.obs;
  final RxString groqKey = ''.obs;
  final RxString geminiKey = ''.obs;

  /// In-memory key cache mapping provider name to api key.
  final RxMap<String, String> _cachedKeys = <String, String>{}.obs;

  // ── Response cache ──────────────────────────────────────
  final Map<String, String> _cache = {};

  // ── Lifecycle ───────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
    _loadKeysAndInit();
  }

  /// Loads keys from secure storage (falling back to .env), then selects the
  /// best available provider. Called on service init and after key save/delete.
  Future<void> _loadKeysAndInit() async {
    await _refreshKeysFromAllSources();
    _selectDefaultProvider();
  }

  /// Reads keys from secure storage first, falls back to .env.
  Future<void> _refreshKeysFromAllSources() async {
    try {
      final secureOpenAi = await _secureStorage.read(key: 'OPENAI_API_KEY');
      final secureGroq = await _secureStorage.read(key: 'GROQ_API_KEY');
      final secureGemini = await _secureStorage.read(key: 'GEMINI_API_KEY');

      _cachedKeys['openai'] = (secureOpenAi?.isNotEmpty == true)
          ? secureOpenAi!
          : (dotenv.env['OPENAI_API_KEY'] ?? '');
      _cachedKeys['groq'] = (secureGroq?.isNotEmpty == true)
          ? secureGroq!
          : (dotenv.env['GROQ_API_KEY'] ?? '');
      _cachedKeys['gemini'] = (secureGemini?.isNotEmpty == true)
          ? secureGemini!
          : (dotenv.env['GEMINI_API_KEY'] ?? '');
    } catch (e) {
      _cachedKeys['openai'] = dotenv.env['OPENAI_API_KEY'] ?? '';
      _cachedKeys['groq'] = dotenv.env['GROQ_API_KEY'] ?? '';
      _cachedKeys['gemini'] = dotenv.env['GEMINI_API_KEY'] ?? '';
    }

    // Sync reactive variables
    openAiKey.value = _cachedKeys['openai'] ?? '';
    groqKey.value = _cachedKeys['groq'] ?? '';
    geminiKey.value = _cachedKeys['gemini'] ?? '';
  }

  /// Picks the default provider based on available keys.
  void _selectDefaultProvider() {
    if (openAiKey.value.isNotEmpty && openAiKey.value.startsWith('sk-')) {
      activeProvider.value = AiProvider.openai;
    } else if (groqKey.value.isNotEmpty) {
      activeProvider.value = AiProvider.groq;
    } else if (geminiKey.value.isNotEmpty) {
      activeProvider.value = AiProvider.gemini;
    } else {
      activeProvider.value = AiProvider.groq; // Default fallback
    }
  }

  // ── Key management ──────────────────────────────────────

  /// Public reload — called after [saveKey] / [deleteKey] and from tests.
  Future<void> loadKeys() => _refreshKeysFromAllSources();

  /// Saves [key] to secure storage for [provider], then refreshes in-memory cache.
  Future<void> saveKey(AiProvider provider, String key) async {
    final storageKey = provider == AiProvider.openai
        ? 'OPENAI_API_KEY'
        : provider == AiProvider.groq
            ? 'GROQ_API_KEY'
            : 'GEMINI_API_KEY';
    await _secureStorage.write(key: storageKey, value: key.trim());
    await _refreshKeysFromAllSources();
  }

  /// Deletes the stored key for [provider] from secure storage.
  Future<void> deleteKey(AiProvider provider) async {
    final storageKey = provider == AiProvider.openai
        ? 'OPENAI_API_KEY'
        : provider == AiProvider.groq
            ? 'GROQ_API_KEY'
            : 'GEMINI_API_KEY';
    await _secureStorage.delete(key: storageKey);
    await _refreshKeysFromAllSources();
  }

  // ── Provider readiness checks ───────────────────────────

  /// Synchronous readiness check using cached reactive key values.
  bool get isReady {
    switch (activeProvider.value) {
      case AiProvider.offline:
        try {
          return Get.find<LocalLlmService>().isModelReady.value;
        } catch (_) {
          return false;
        }
      case AiProvider.groq:
      case AiProvider.gemini:
      case AiProvider.openai:
        final k = _sanitizeKey(
          _cachedKeys[activeProvider.value.name] ??
          dotenv.env[activeProvider.value.envKeyName]
        );
        return k.isNotEmpty;
    }
  }

  /// Human-readable reason why [isReady] returned false for the current provider.
  String? get readinessError {
    if (isReady) return null;
    if (activeProvider.value == AiProvider.offline) {
      return 'Offline model not downloaded. Go to Settings → AI Engine.';
    }
    return '${activeProvider.value.displayName} API key not configured. '
           'Add it in Settings → AI Engine.';
  }

  // ── Provider switching ──────────────────────────────────

  void switchProvider(AiProvider provider) {
    final previous = activeProvider.value;
    activeProvider.value = provider;

    try {
      Get.find<AnalyticsService>().logProviderSwitched(provider.displayName);
    } catch (_) {}

    // Unload offline model from RAM when switching away to free memory
    if (previous == AiProvider.offline && provider != AiProvider.offline) {
      try {
        Get.find<LocalLlmService>().unloadModel();
      } catch (_) {}
    }
  }

  // ── Cache ───────────────────────────────────────────────

  void clearCache() => _cache.clear();


  // ── Message routing ─────────────────────────────────────

  String _sanitizeKey(String? raw) {
    if (raw == null) return '';
    return raw.trim().replaceAll('\r', '').replaceAll('"', '').replaceAll("'", '');
  }

  Future<String> sendMessages(
    List<ChatMessage> messages, {
    bool voiceMode = false,
  }) async {
    final provider = activeProvider.value;

    final apiMessages = List<ChatMessage>.from(messages);
    if (voiceMode) {
      apiMessages.insert(0, ChatMessage(
        id: 'voice-instruction',
        role: MessageRole.system,
        content: 'You are responding to a voice query. '
                 'Keep your answer to 2-3 short sentences. '
                 'Use plain conversational language. '
                 'No bullet points, no headers, no markdown formatting.',
        timestamp: DateTime.now(),
      ));
    } else {
      final hasSystem = apiMessages.any((m) => m.role == MessageRole.system);
      if (!hasSystem) {
        apiMessages.insert(0, ChatMessage(
          id: 'system',
          role: MessageRole.system,
          content: 'You are a helpful, concise, and friendly AI assistant. '
                   'Format responses in Markdown.',
          timestamp: DateTime.now(),
        ));
      }
    }

    // ── OFFLINE ──────────────────────────────────────────────────────────────
    if (provider == AiProvider.offline) {
      final localLlm = Get.find<LocalLlmService>();
      if (!localLlm.isModelReady.value) {
        throw Exception(
          'Offline model not downloaded. Go to Settings → AI Engine.');
      }
      return localLlm.generate(messages: apiMessages);
    }

    // ── CLOUD PROVIDERS ───────────────────────────────────────────────────────
    final apiKey = _sanitizeKey(
      _cachedKeys[provider.name] ?? dotenv.env[provider.envKeyName]
    );
    if (apiKey.isEmpty) {
      throw Exception(
        '${provider.displayName} API key is not configured. '
        'Add it in Settings → AI Engine.');
    }

    final hasImage = apiMessages.any(
      (m) => m.imageBase64 != null && m.imageBase64!.isNotEmpty);
    final modelId = provider.modelIdForRequest(hasImage: hasImage);

    // ── GEMINI ────────────────────────────────────────────────────────────────
    if (provider == AiProvider.gemini) {
      return _sendGemini(apiMessages, modelId, apiKey, hasImage);
    }

    // ── GROQ / OPENAI (OpenAI-compatible format) ──────────────────────────────
    return _sendOpenAiCompatible(apiMessages, modelId, apiKey, provider);
  }
  /// Sends a vision-specific request. If [prioritizeGroq] is true, tries Groq first
  /// with an optional [timeout] before falling back to Gemini.
  Future<String> sendVisionRequest({
    required String base64Image,
    required String prompt,
    required String systemInstruction,
    bool prioritizeGroq = false,
    Duration? timeout,
  }) async {
    final messages = [
      ChatMessage(
        id: 'system',
        role: MessageRole.system,
        content: systemInstruction,
        timestamp: DateTime.now(),
      ),
      ChatMessage(
        id: 'user',
        role: MessageRole.user,
        content: prompt,
        timestamp: DateTime.now(),
        imageBase64: base64Image,
        imageMimeType: 'image/jpeg',
      ),
    ];

    Future<String> attemptGemini() async {
      final geminiApiKey = _sanitizeKey(
        geminiKey.value.isNotEmpty ? geminiKey.value : dotenv.env['GEMINI_API_KEY']
      );
      if (geminiApiKey.isEmpty) {
        throw Exception('Gemini API key is not configured.');
      }
      final modelId = 'gemini-1.5-flash';
      final startTime = DateTime.now();
      debugPrint('👁️ Live Vision: Attempting Gemini 1.5 Flash...');
      
      Future<String> call = _sendGemini(messages, modelId, geminiApiKey, true);
      if (timeout != null) {
        call = call.timeout(timeout);
      }
      final response = await call;
      final latency = DateTime.now().difference(startTime).inMilliseconds;
      debugPrint('👁️ Live Vision [Gemini]: Success in ${latency}ms');
      return response;
    }

    Future<String> attemptGroq() async {
      final groqApiKey = _sanitizeKey(
        groqKey.value.isNotEmpty ? groqKey.value : dotenv.env['GROQ_API_KEY']
      );
      if (groqApiKey.isEmpty) {
        throw Exception('Groq API key is not configured.');
      }
      final modelId = 'meta-llama/llama-4-scout-17b-16e-instruct';
      final startTime = DateTime.now();
      debugPrint('👁️ Live Vision: Attempting Groq llama-4-scout...');
      
      Future<String> call = _sendOpenAiCompatible(messages, modelId, groqApiKey, AiProvider.groq);
      if (timeout != null) {
        call = call.timeout(timeout);
      }
      final response = await call;
      final latency = DateTime.now().difference(startTime).inMilliseconds;
      debugPrint('👁️ Live Vision [Groq]: Success in ${latency}ms');
      return response;
    }

    if (prioritizeGroq) {
      try {
        return await attemptGroq();
      } catch (e) {
        debugPrint('⚠️ Live Vision: Groq failed/timed out ($e). Falling back to Gemini...');
        try {
          return await attemptGemini();
        } catch (e2) {
          throw Exception('Vision call failed: both Groq and Gemini failed. (Groq: $e, Gemini: $e2)');
        }
      }
    } else {
      try {
        return await attemptGemini();
      } catch (e) {
        debugPrint('⚠️ Live Vision: Gemini failed/timed out ($e). Falling back to Groq...');
        try {
          return await attemptGroq();
        } catch (e2) {
          throw Exception('Vision call failed: both Gemini and Groq failed. (Gemini: $e, Groq: $e2)');
        }
      }
    }
  }

  Future<String> _sendOpenAiCompatible(
    List<ChatMessage> messages,
    String modelId,
    String apiKey,
    AiProvider provider,
  ) async {
    final body = jsonEncode({
      'model': modelId,
      'messages': messages.map((m) => m.toApiMap()).toList(),
      'max_tokens': 1024,
    });

    final response = await http.post(
      Uri.parse(provider.endpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: body,
    ).timeout(
      const Duration(seconds: 120),
      onTimeout: () => throw TimeoutException(
        'The request timed out after 2 minutes. '
        'The API may be under load — please try again.',
      ),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['choices'][0]['message']['content'] as String;
    }
    final err = jsonDecode(response.body);
    throw Exception(
      '${provider.displayName} error: ${err['error']?['message'] ?? response.body}');
  }

  Future<String> _sendGemini(
    List<ChatMessage> messages,
    String modelId,
    String apiKey,
    bool hasImage,
  ) async {
    // Convert messages to Gemini format
    final contents = <Map<String, dynamic>>[];
    String? systemInstruction;

    for (final msg in messages) {
      if (msg.role == MessageRole.system) {
        // Gemini uses systemInstruction, not a system role message
        systemInstruction = msg.content;
        continue;
      }
      contents.add(msg.toApiMap(useGeminiFormat: true));
    }

    final requestBody = <String, dynamic>{
      'contents': contents,
      if (systemInstruction != null)
        'systemInstruction': {
          'parts': [{'text': systemInstruction}]
        },
      'generationConfig': {
        'maxOutputTokens': 1024,
        'temperature': 0.7,
      },
    };

    final uri = Uri.parse(
      '${AiProvider.gemini.endpoint}/$modelId:generateContent?key=$apiKey');

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(requestBody),
    ).timeout(
      const Duration(seconds: 120),
      onTimeout: () => throw TimeoutException(
        'Gemini request timed out after 2 minutes. Please try again.',
      ),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['candidates'][0]['content']['parts'][0]['text'] as String;
    }
    final err = jsonDecode(response.body);
    throw Exception(
      'Gemini error: ${err['error']?['message'] ?? response.body}');
  }
}
