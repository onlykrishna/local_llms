import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../constants/app_constants.dart';

class OllamaClient {
  final http.Client _client = http.Client();

  /// Streams the chat response from Ollama server
  Stream<String> streamChat(String prompt, String model) async* {
    final Map<String, dynamic> body = {
      'model': model,
      'prompt': prompt,
      'stream': true,
    };

    try {
      final request = http.Request('POST', Uri.parse('${AppConstants.ollamaBaseUrl}/generate'));
      request.body = json.encode(body);
      request.headers[HttpHeaders.contentTypeHeader] = 'application/json';

      final http.StreamedResponse response = await _client.send(request).timeout(
        const Duration(seconds: AppConstants.requestTimeout),
      );

      if (response.statusCode != 200) {
        throw HttpException('Ollama Error: ${response.statusCode}');
      }

      // Decode and split stream into lines properly to handle partial chunks
      final Stream<String> lineStream = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final String line in lineStream) {
        if (line.trim().isEmpty) continue;
        try {
          final Map<String, dynamic> data = json.decode(line);
          if (data['response'] != null) {
            yield data['response'].toString();
          }
        } catch (e) {
          // Silent catch for invalid JSON in stream
        }
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Checks if the Ollama server is up
  Future<bool> checkServer() async {
    try {
      final response = await _client.get(Uri.parse(AppConstants.ollamaBaseUrl.replaceAll('/api', '')));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Lists available models on the Ollama server
  Future<List<String>> listModels() async {
    try {
      final response = await _client.get(Uri.parse('${AppConstants.ollamaBaseUrl}/tags'));
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        final List<dynamic> models = data['models'] ?? [];
        return models.map((m) => m['name'].toString()).toList();
      }
    } catch (_) {}
    return ['mistral', 'llama2', 'codellama']; // Fallback common models
  }
}
