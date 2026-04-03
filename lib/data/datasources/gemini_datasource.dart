import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../core/services/settings_service.dart';
import 'package:get/get.dart';

class GeminiRateLimitException implements Exception {
  final String message;
  GeminiRateLimitException(this.message);
  @override
  String toString() => 'GeminiRateLimitException: $message';
}

/// Datasource for Gemini 1.5 Flash API with SSE streaming.
class GeminiDatasource {
  final SettingsService _settings = Get.find<SettingsService>();
  final Dio _dio = Dio();
  CancelToken? _cancelToken;

  static const String _baseUrl = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:streamGenerateContent';

  /// Streams response from Gemini 1.5 Flash using SSE.
  Stream<String> streamChat({
    required String apiKey,
    required String userMessage,
    required String systemPrompt,
    List<Map<String, dynamic>>? history,
  }) async* {
    _cancelToken = CancelToken();

    try {
      final response = await _dio.post(
        '$_baseUrl?key=$apiKey',
        data: {
          'contents': [
            {
              'role': 'user',
              'parts': [
                {'text': 'System Instruction: $systemPrompt\n\nUser Question: $userMessage'}
              ]
            }
          ],
          'generationConfig': {
             'temperature': 0.7,
             'maxOutputTokens': 512,
          }
        },
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Content-Type': 'application/json'},
        ),
        cancelToken: _cancelToken,
      );

      final stream = response.data!.stream
          .transform(StreamTransformer<Uint8List, String>.fromHandlers(
            handleData: (data, sink) {
              sink.add(utf8.decode(data));
            },
          ))
          .transform(const LineSplitter());

      await for (final line in stream) {
        if (_cancelToken?.isCancelled ?? false) break;
        if (line.isEmpty) continue;
        
        String cleanLine = line;
        if (line.startsWith('data: ')) {
          cleanLine = line.substring(6);
        }

        try {
          final json = jsonDecode(cleanLine);
          if (json['candidates'] != null && json['candidates'].isNotEmpty) {
            final part = json['candidates'][0]['content']['parts'][0]['text'];
            if (part != null) {
              yield part;
            }
          }
        } catch (e) {
          if (kDebugMode) print('Gemini Parse Error: $e on line: $cleanLine');
        }
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) return;
      if (e.response?.statusCode == 429) {
        throw GeminiRateLimitException('Gemini 429 quota exhausted');
      }
      yield '⚠️ Gemini API Error: ${e.message}';
    } catch (e) {
      yield '⚠️ Gemini error: $e';
    }
  }

  void cancel() {
    _cancelToken?.cancel('Cancelled by user');
    _cancelToken = null;
  }
}
