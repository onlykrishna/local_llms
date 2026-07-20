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

/// Utility function to strip internal reasoning content wrapped in `<think>...</think>` tags.
String cleanReasoningText(String text) {
  if (text.isEmpty) return text;
  final thinkRegex = RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false);
  var cleaned = text.replaceAll(thinkRegex, '').trim();
  cleaned = cleaned.replaceAll(RegExp(r'</?think>', caseSensitive: false), '').trim();
  return cleaned;
}

/// Central service that manages active AI providers, API key storage/retrieval,
/// dynamic Groq model resolution, and Hugging Face vision fallback.
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

  /// Loads keys from secure storage (falling back to .env), then selects default provider.
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

    final hfKeyPresent = (dotenv.env['HF_API_KEY'] ?? '').trim().isNotEmpty;

    debugPrint('🔑 ApiProviderService: Groq API key loaded? ${groqKey.value.trim().isNotEmpty}');
    debugPrint('🔑 ApiProviderService: Hugging Face API key loaded? $hfKeyPresent');
    debugPrint('👁️ Vision Config: Groq primary (dynamic discovery) -> Hugging Face Serverless fallback');
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
      activeProvider.value = AiProvider.groq;
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

    if (provider == AiProvider.offline) {
      final localLlm = Get.find<LocalLlmService>();
      if (!localLlm.isModelReady.value) {
        throw Exception(
          'Offline model not downloaded. Go to Settings → AI Engine.');
      }
      return localLlm.generate(messages: apiMessages);
    }

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

    if (provider == AiProvider.gemini) {
      return _sendGemini(apiMessages, modelId, apiKey, hasImage);
    }

    return _sendOpenAiCompatible(apiMessages, modelId, apiKey, provider);
  }

  // ── DYNAMIC GROQ VISION MODEL RESOLUTION ─────────────────────────────────

  /// Queries GET https://api.groq.com/openai/v1/models to verify active models.
  /// Dynamically selects an active vision model, or falls back to 'qwen/qwen3.6-27b'.
  Future<String> getActiveGroqVisionModel(String groqApiKey) async {
    try {
      final response = await http.get(
        Uri.parse('https://api.groq.com/openai/v1/models'),
        headers: {'Authorization': 'Bearer $groqApiKey'},
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = (data['data'] as List?) ?? [];
        final modelIds = list.map((m) => m['id'] as String).toList();
        debugPrint('📋 Groq Models Endpoint returned ${modelIds.length} active models: $modelIds');

        // Look for vision-capable models (e.g. qwen/qwen3.6-27b, qwen, vision, or scout)
        final candidate = modelIds.firstWhere(
          (id) => id.contains('qwen3.6-27b') || id.contains('qwen') || id.contains('vision') || id.contains('scout'),
          orElse: () => '',
        );

        if (candidate.isNotEmpty) {
          debugPrint('👁️ Groq Vision Model dynamically resolved: "$candidate"');
          return candidate;
        }
      }
    } catch (e) {
      debugPrint('⚠️ Groq Models API query failed ($e). Falling back to default qwen/qwen3.6-27b.');
    }
    return 'qwen/qwen3.6-27b';
  }

  /*
  ─────────────────────────────────────────────────────────────────────────────
  ⚠️ IMPORTANT NOTICE ON VISION PROVIDER MODELS:
  Groq and Hugging Face model lineups change frequently and preview models may be
  decommissioned without prior notice. If a "[MODEL DEPRECATED]" error appears:
    • Check Groq Models: https://console.groq.com/docs/models
    • Check Hugging Face Models: https://huggingface.co/models?pipeline_tag=image-text-to-text
  ─────────────────────────────────────────────────────────────────────────────
  */

  /// Sends a vision request. Primary: Groq (`qwen/qwen3.6-27b` or dynamic vision model).
  /// Fallback: Hugging Face Inference API (`sendVisionRequestHuggingFace`).
  Future<String> sendVisionRequest({
    required String base64Image,
    required String prompt,
    required String systemInstruction,
    bool prioritizeGroq = true,
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

    // ── GROQ CONSTRAINTS REFERENCE ──
    // • Max images per request: 5 (App sends 1 frame)
    // • Max payload size: 20MB (Compressed app JPEG frames are ~100-300KB)
    // • Data format: data:image/jpeg;base64,{base64string}

    Future<String> attemptGroq() async {
      final groqApiKey = _sanitizeKey(
        groqKey.value.isNotEmpty ? groqKey.value : dotenv.env['GROQ_API_KEY']
      );
      if (groqApiKey.isEmpty) {
        throw Exception('Groq API key is not configured in .env or settings.');
      }

      // Fetch dynamic vision model ID or fallback to qwen/qwen3.6-27b
      final modelId = await getActiveGroqVisionModel(groqApiKey);
      final startTime = DateTime.now();
      debugPrint('👁️ Live Vision: Attempting Groq $modelId...');

      Future<String> call = _sendOpenAiCompatible(messages, modelId, groqApiKey, AiProvider.groq);
      if (timeout != null) {
        call = call.timeout(timeout);
      }

      try {
        final response = await call;
        final latency = DateTime.now().difference(startTime).inMilliseconds;
        debugPrint('👁️ Live Vision [Groq]: Success in ${latency}ms using model "$modelId"');
        return response;
      } catch (e) {
        final errString = e.toString();
        if (errString.contains('decommissioned') ||
            errString.contains('does not exist') ||
            errString.contains('model_not_found') ||
            errString.contains('404')) {
          debugPrint('❌ [MODEL DEPRECATED] Groq model "$modelId" error: $errString');
          throw Exception('[MODEL DEPRECATED] Groq model "$modelId" is decommissioned. ($errString)');
        }
        rethrow;
      }
    }

    try {
      final raw = await attemptGroq();
      return cleanReasoningText(raw);
    } catch (groqErr) {
      debugPrint('⚠️ Live Vision: Groq failed ($groqErr). Falling back to Hugging Face...');
      try {
        final raw = await sendVisionRequestHuggingFace(messages, timeout);
        return cleanReasoningText(raw);
      } catch (hfErr) {
        throw Exception(
          'Vision call failed: both Groq and Hugging Face failed.\n'
          '• Groq Error: $groqErr\n'
          '• Hugging Face Error: $hfErr'
        );
      }
    }
  }

  /// Sends a vision request to Hugging Face Inference API as a free-tier fallback.
  Future<String> sendVisionRequestHuggingFace(List<ChatMessage> messages, Duration? timeout) async {
    final hfKey = _sanitizeKey(dotenv.env['HF_API_KEY']);
    if (hfKey.isEmpty) {
      throw Exception('Hugging Face API key (HF_API_KEY) is not configured in .env.');
    }

    final modelId = 'Qwen/Qwen2-VL-7B-Instruct';
    final startTime = DateTime.now();
    debugPrint('👁️ Live Vision: Attempting Hugging Face Serverless Vision API ($modelId)...');

    final body = jsonEncode({
      'model': modelId,
      'messages': messages.map((m) => m.toApiMap()).toList(),
      'max_tokens': 512,
    });

    Future<http.Response> call = http.post(
      Uri.parse('https://router.huggingface.co/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $hfKey',
      },
      body: body,
    );

    if (timeout != null) {
      call = call.timeout(timeout);
    }

    final response = await call;
    final latency = DateTime.now().difference(startTime).inMilliseconds;

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final text = data['choices'][0]['message']['content'] as String;
      debugPrint('👁️ Live Vision [HuggingFace]: Success in ${latency}ms using $modelId');
      return cleanReasoningText(text);
    }

    final errBody = response.body;
    if (response.statusCode == 404 ||
        errBody.contains('decommissioned') ||
        errBody.contains('does not exist') ||
        errBody.contains('not found')) {
      debugPrint('❌ [MODEL DEPRECATED] Hugging Face vision model "$modelId" error: $errBody');
      throw Exception('[MODEL DEPRECATED] Hugging Face model "$modelId" is unavailable.');
    }

    throw Exception('Hugging Face Vision API error (${response.statusCode}): $errBody');
  }

  Future<String> _sendOpenAiCompatible(
    List<ChatMessage> messages,
    String modelId,
    String apiKey,
    AiProvider provider,
  ) async {
    final bodyMap = <String, dynamic>{
      'model': modelId,
      'messages': messages.map((m) => m.toApiMap()).toList(),
      'max_tokens': 1024,
      if (provider == AiProvider.groq) 'reasoning_format': 'hidden',
    };
    final body = jsonEncode(bodyMap);

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
      final rawText = data['choices'][0]['message']['content'] as String;
      return cleanReasoningText(rawText);
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
    final contents = <Map<String, dynamic>>[];
    String? systemInstruction;

    for (final msg in messages) {
      if (msg.role == MessageRole.system) {
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
      final rawText = data['candidates'][0]['content']['parts'][0]['text'] as String;
      return cleanReasoningText(rawText);
    }
    final err = jsonDecode(response.body);
    throw Exception(
      'Gemini error: ${err['error']?['message'] ?? response.body}');
  }
}
