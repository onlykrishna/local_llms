import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../constants/app_constants.dart';

class FallbackDatasetService extends GetxService {
  Map<String, dynamic>? _dataset;

  Future<FallbackDatasetService> init() async {
    try {
      final String response = await rootBundle.loadString(AppConstants.fallbackDatasetPath);
      _dataset = json.decode(response);
    } catch (e) {
      _dataset = {
        'default': 'Hey! It seems we are completely offline and can\'t reach our model. How about we discuss Flutter or offline-AI later?'
      };
    }
    return this;
  }

  /// Intelligence logic to pick the best fallback based on message content
  Stream<String> getStreamingFallback(String userMessageText) async* {
    String message = userMessageText.toLowerCase();
    String? responseText;

    // Check for topic keywords
    if (_dataset?['topics'] != null) {
      final topics = _dataset!['topics'] as Map<String, dynamic>;
      for (var entry in topics.entries) {
        if (message.contains(entry.key)) {
          final List<dynamic> options = entry.value;
          responseText = (options..shuffle()).first.toString();
          break;
        }
      }
    }

    // Check for greetings
    if (responseText == null && _dataset?['greetings'] != null) {
      final List<dynamic> greetings = _dataset!['greetings'];
      if (message.contains('hi') || message.contains('hello')) {
        responseText = (greetings..shuffle()).first.toString();
      }
    }

    // Default response if no topic or greeting matches
    responseText ??= _dataset?['fallback_responses']?['default'] ?? 'I am offline.';

    // Simulate streaming by splitting by tokens (words)
    final List<String> tokens = responseText.split(' ');
    for (String token in tokens) {
      await Future.delayed(const Duration(milliseconds: 60));
      yield '$token ';
    }
  }
}
