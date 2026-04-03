import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import '../../domain/models/inference_domain.dart';

class GeminiDatasource {
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/'
      'gemini-1.5-flash:streamGenerateContent';

  final Dio _dio = Dio();
  CancelToken? _cancelToken;

  /// Streams tokens from Gemini 1.5 Flash free tier.
  /// Requires a valid Gemini API key from aistudio.google.com.
  Stream<String> streamChat({
    required String apiKey,
    required String userMessage,
    required String systemPrompt,
    required List<Map<String, dynamic>> history,
    String Function(String)? onError,
  }) async* {
    if (apiKey.isEmpty) {
      yield '⚠️ No Gemini API key set. Go to Settings → AI Backend to add your free key.';
      return;
    }

    _cancelToken = CancelToken();

    final url = '$_baseUrl?alt=sse&key=$apiKey';

    // Build contents from history (last N messages)
    final contents = <Map<String, dynamic>>[];
    for (final msg in history) {
      contents.add({
        'role': msg['isUser'] == true ? 'user' : 'model',
        'parts': [{'text': msg['content']}],
      });
    }
    contents.add({'role': 'user', 'parts': [{'text': userMessage}]});

    final body = {
      'system_instruction': {
        'parts': [{'text': systemPrompt}],
      },
      'contents': contents,
      'generationConfig': {
        'temperature': 0.7,
        'maxOutputTokens': 512,
      },
    };

    try {
      final response = await _dio.post<ResponseBody>(
        url,
        data: body,
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Content-Type': 'application/json'},
        ),
        cancelToken: _cancelToken,
      );

      final stream = response.data!.stream
          .map((bytes) => utf8.decode(bytes))
          .transform(const LineSplitter());

      await for (final line in stream) {
        if (_cancelToken?.isCancelled ?? false) break;
        if (!line.startsWith('data:')) continue;
        final jsonStr = line.substring(5).trim();
        if (jsonStr.isEmpty || jsonStr == '[DONE]') continue;
        try {
          final data = json.decode(jsonStr) as Map<String, dynamic>;
          final token = data['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?;
          if (token != null && token.isNotEmpty) yield token;
        } catch (_) {}
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) return;

      final statusCode = e.response?.statusCode ?? 0;
      if (statusCode == 429) {
        yield '\n⚠️ Gemini free quota reached. Switching to on-device AI...';
        // Caller (router) will handle fallback via thrown exception
        throw GeminiRateLimitException();
      } else if (statusCode == 401 || statusCode == 403) {
        yield '\n⚠️ Invalid Gemini API key. Check Settings → AI Backend.';
      } else {
        yield '\n[Gemini Error: ${e.message}]';
      }
    }
  }

  void cancel() {
    _cancelToken?.cancel('User cancelled request');
    _cancelToken = null;
  }
}

class GeminiRateLimitException implements Exception {
  @override
  String toString() => 'Gemini 429: Rate limit reached';
}
