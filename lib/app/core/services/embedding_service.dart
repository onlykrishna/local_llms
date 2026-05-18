import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

class EmbeddingService extends GetxService {

  // ── Provider detection ──
  // Priority: OpenAI if key present → HuggingFace otherwise
  // TO SWITCH TO OPENAI: just add OPENAI_API_KEY=sk-... to .env
  // No code change needed ever.
  String get _openAiKey => dotenv.env['OPENAI_API_KEY'] ?? '';
  String get _hfKey     => dotenv.env['HF_API_KEY'] ?? '';

  bool get isOpenAiActive =>
      _openAiKey.isNotEmpty && _openAiKey.startsWith('sk-');

  String get activeProviderName =>
      isOpenAiActive ? 'OpenAI' : 'HuggingFace';

  int get embeddingDimension => isOpenAiActive ? 1536 : 384;

  // ── OpenAI config ──
  static const String _openAiEndpoint =
      'https://api.openai.com/v1/embeddings';
  static const String _openAiModel = 'text-embedding-3-small';

  // ── HuggingFace config ──
  static const String _hfEndpoint =
      'https://router.huggingface.co/hf-inference/models/'
      'sentence-transformers/all-MiniLM-L6-v2/pipeline/feature-extraction';

  // ────────────────────────────────────
  // PUBLIC API — called by PdfChatService
  // ────────────────────────────────────

  /// Embed a single string.
  /// Automatically routes to OpenAI or HuggingFace based on .env.
  /// taskType is used by OpenAI-compatible APIs (ignored by HF).
  Future<List<double>> embedText(
    String text, {
    String taskType = 'RETRIEVAL_DOCUMENT',
  }) async {
    if (isOpenAiActive) {
      return await _embedOpenAi(text, taskType: taskType);
    } else {
      return await _embedHuggingFace(text);
    }
  }

  /// Embed a batch of strings with progress callback.
  Future<List<List<double>>> embedBatch(
    List<String> texts, {
    void Function(int current, int total)? onProgress,
  }) async {
    final results = <List<double>>[];
    for (int i = 0; i < texts.length; i++) {
      onProgress?.call(i + 1, texts.length);
      results.add(await embedText(texts[i]));
      if (i < texts.length - 1) {
        // OpenAI paid: 100ms is fine (500 RPM limit)
        // HuggingFace free: 200ms to be polite
        final delay = isOpenAiActive ? 100 : 200;
        await Future.delayed(Duration(milliseconds: delay));
      }
    }
    return results;
  }

  /// Cosine similarity between two vectors.
  /// Returns 0.0 safely on dimension mismatch (stale chunks).
  double cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;
    double dot = 0, normA = 0, normB = 0;
    for (int i = 0; i < a.length; i++) {
      dot   += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0 || normB == 0) return 0.0;
    return dot / (sqrt(normA) * sqrt(normB));
  }

  /// Validate the active provider on startup.
  /// Prints result to Flutter console.
  Future<Map<String, dynamic>> validateConnection() async {
    try {
      final vec = await embedText('test connection');
      final result = {
        'success': true,
        'dimensions': vec.length,
        'provider': activeProviderName,
        'model': isOpenAiActive
            ? _openAiModel
            : 'all-MiniLM-L6-v2',
        'switchToOpenAI': isOpenAiActive
            ? 'already active'
            : 'add OPENAI_API_KEY=sk-... to .env to switch',
      };
      debugPrint('✅ Embedding provider: $activeProviderName '
          '(${vec.length} dimensions)');
      return result;
    } catch (e) {
      debugPrint('❌ Embedding validation failed: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Non-blocking connection check. Logs invalid API keys on startup instead of throwing.
  Future<Map<String, dynamic>> validateAndLog() async {
    try {
      final vec = await embedText('test connection');
      final result = {
        'success': true,
        'dimensions': vec.length,
        'provider': activeProviderName,
        'model': isOpenAiActive ? _openAiModel : 'all-MiniLM-L6-v2',
      };
      debugPrint('✅ Embedding startup validation successful: $activeProviderName (${vec.length} dimensions)');
      return result;
    } catch (e) {
      debugPrint('❌ Startup Embedding API key validation failed (Non-Fatal): $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // ────────────────────────────────────
  // PRIVATE — OpenAI implementation
  // ────────────────────────────────────
  Future<List<double>> _embedOpenAi(
    String text, {
    String taskType = 'RETRIEVAL_DOCUMENT',
    int maxRetries = 5,
  }) async {
    final truncated =
        text.length > 8000 ? text.substring(0, 8000) : text;

    int attempt = 0;
    while (attempt < maxRetries) {
      final response = await http.post(
        Uri.parse(_openAiEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_openAiKey',
        },
        body: jsonEncode({
          'model': _openAiModel,
          'input': truncated,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data =
            jsonDecode(response.body) as Map<String, dynamic>;
        final raw = (data['data'] as List<dynamic>)[0]['embedding']
            as List<dynamic>;
        return raw.map((e) => (e as num).toDouble()).toList();

      } else if (response.statusCode == 429) {
        attempt++;
        if (attempt >= maxRetries) {
          throw Exception(
            'OpenAI rate limit reached after $maxRetries retries. '
            'Your plan may need upgrading at '
            'platform.openai.com/account/billing',
          );
        }
        final waitSeconds = pow(2, attempt).toInt();
        debugPrint('⏳ OpenAI rate limited. '
            'Retrying in ${waitSeconds}s '
            '(attempt $attempt/$maxRetries)...');
        await Future.delayed(Duration(seconds: waitSeconds));

      } else if (response.statusCode == 401) {
        throw Exception(
          'Invalid OpenAI API key. '
          'Check OPENAI_API_KEY in .env',
        );
      } else if (response.statusCode == 402) {
        throw Exception(
          'OpenAI account has no credits. '
          'Add billing at platform.openai.com/account/billing',
        );
      } else {
        final body = jsonDecode(response.body);
        throw Exception(
          'OpenAI error: '
          '${body['error']?['message'] ?? response.statusCode}',
        );
      }
    }
    throw Exception('OpenAI embedding failed after $maxRetries retries.');
  }

  // ────────────────────────────────────
  // PRIVATE — HuggingFace implementation
  // ────────────────────────────────────
  Future<List<double>> _embedHuggingFace(
    String text, {
    int attempt = 0,
  }) async {
    if (_hfKey.isEmpty) {
      throw Exception(
        'No embedding key found. '
        'Add HF_API_KEY=hf_... to .env for free embeddings, '
        'or add OPENAI_API_KEY=sk-... for OpenAI.',
      );
    }

    final truncated =
        text.length > 4000 ? text.substring(0, 4000) : text;

    final response = await http.post(
      Uri.parse(_hfEndpoint),
      headers: {
        'Authorization': 'Bearer $_hfKey',
        'Content-Type': 'application/json',
        'User-Agent': 'Flutter-AI-Chat-App',
      },
      body: jsonEncode({'inputs': truncated}),
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      // HuggingFace returns flat list or nested list
      if (data is List && data.isNotEmpty) {
        if (data[0] is List) {
          return (data[0] as List<dynamic>)
              .map((e) => (e as num).toDouble())
              .toList();
        }
        return (data as List<dynamic>)
            .map((e) => (e as num).toDouble())
            .toList();
      }
      throw Exception(
          'Unexpected HuggingFace response format.');

    } else if (response.statusCode == 503 && attempt < 3) {
      // Model cold-starting — retry after 10s (max 3 times)
      debugPrint('⏳ HuggingFace model loading... '
          'retrying in 10s (attempt ${attempt + 1}/3)');
      await Future.delayed(const Duration(seconds: 10));
      return _embedHuggingFace(text, attempt: attempt + 1);

    } else if (response.statusCode == 401) {
      throw Exception(
        'Invalid HuggingFace token. '
        'Check HF_API_KEY in .env',
      );
    } else {
      String errorInfo = 'Status ${response.statusCode}';
      try {
        final body = jsonDecode(response.body);
        errorInfo = body['error'] ?? response.statusCode.toString();
      } catch (_) {
        // If not JSON, show start of body
        final snippet = response.body.length > 100
            ? '${response.body.substring(0, 100)}...'
            : response.body;
        errorInfo = 'Status ${response.statusCode}: $snippet';
      }
      throw Exception('HuggingFace error: $errorInfo');
    }
  }
}
