import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../../core/services/settings_service.dart';
import 'package:get/get.dart';
import '../../core/services/log_service.dart';

class GeminiRateLimitException implements Exception {
  final String message;
  GeminiRateLimitException(this.message);
  @override
  String toString() => 'GeminiRateLimitException: $message';
}

/// Datasource for Gemini Flash API with V1beta protocol.
class GeminiDatasource {
  final SettingsService _settings = Get.find<SettingsService>();
  final Dio _dio = Dio();
  CancelToken? _cancelToken;

  // Use V1beta as requested for modern Flash models
  static const String _baseUrl = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:streamGenerateContent';

  /// Streams response from Gemini Flash.
  Stream<String> streamChat({
    required String apiKey,
    required String userMessage,
    required String systemPrompt,
    List<Map<String, dynamic>>? history,
  }) async* {
    LogService.to.log('>>> GEMINI: key length = ${apiKey.length}');
    if (apiKey.isEmpty) {
      LogService.to.log('>>> GEMINI: API Key missing');
      throw GeminiRateLimitException('API Key missing');
    }

    _cancelToken = CancelToken();

    try {
      LogService.to.log('>>> GEMINI: sending request to v1beta...');
      final response = await _dio.post(
        '$_baseUrl?key=$apiKey&alt=sse',
        data: {
          'system_instruction': {
            'parts': [
              {'text': systemPrompt}
            ]
          },
          'contents': [
            {
              'role': 'user',
              'parts': [
                {'text': userMessage}
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
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 45),
        ),
        cancelToken: _cancelToken,
      );

      LogService.to.log('>>> GEMINI: response status = ${response.statusCode}');

      // Parse v1beta SSE stream (data: prefix)
      final stream = response.data!.stream
          .transform(StreamTransformer<Uint8List, String>.fromHandlers(
            handleData: (data, sink) => sink.add(utf8.decode(data, allowMalformed: true)),
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
          // Some chunks might be partial or contain non-text fields, skip them
        }
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        LogService.to.log('>>> GEMINI: request cancelled');
        return;
      }
      LogService.to.log('>>> GEMINI: Dio Error: ${e.message} (Status: ${e.response?.statusCode})');
      if (e.response?.statusCode == 429) {
        throw GeminiRateLimitException('Gemini 429 quota exhausted');
      }
      yield '⚠️ Gemini API Error: ${e.message} (${e.response?.statusCode})';
      if (e.response?.data != null) {
        yield '\nDetail: ${e.response?.data}';
      }
    } catch (e) {
      LogService.to.log('>>> GEMINI: general error: $e');
      yield '⚠️ Gemini error: $e';
    }
  }

  void cancel() {
    LogService.to.log('>>> GEMINI: manual cancel triggered');
    _cancelToken?.cancel('Cancelled by user');
    _cancelToken = null;
  }
}
