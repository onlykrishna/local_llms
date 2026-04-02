import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../constants/app_constants.dart';

class FallbackDatasetService extends GetxService {
  Map<String, dynamic>? _brain;
  Map<String, dynamic>? _fallback;

  Future<FallbackDatasetService> init() async {
    try {
      final String brainData = await rootBundle.loadString(AppConstants.localBrainPath);
      _brain = json.decode(brainData);
      
      final String fallbackData = await rootBundle.loadString(AppConstants.fallbackDatasetPath);
      _fallback = json.decode(fallbackData);
    } catch (e) {
      // Fallback in case of asset failure
    }
    return this;
  }

  /// Intelligence logic to pick the best fallback based on message content
  Stream<String> getStreamingFallback(String userMessageText) async* {
    String message = userMessageText.toLowerCase();
    String? responseText;

    // Simulate "Thinking" stages for "Premium Mode"
    if (_brain?['placeholders']?['thinking'] != null) {
      final List<dynamic> stages = _brain!['placeholders']['thinking'];
      // Yield thinking states as comments to be handled by UI or just as status skips
    }

    // Process Intents (Smart Regex Pattern Matching)
    if (_brain?['intents'] != null) {
      final List<dynamic> intents = _brain!['intents'];
      for (var intent in intents) {
        final pattern = intent['pattern'] as String;
        final regex = RegExp(pattern, caseSensitive: false);
        if (regex.hasMatch(message)) {
          responseText = intent['response'] as String;
          break;
        }
      }
    }

    // Check for topic keywords in secondary fallback
    if (responseText == null && _fallback?['topics'] != null) {
      final topics = _fallback!['topics'] as Map<String, dynamic>;
      for (var entry in topics.entries) {
        if (message.contains(entry.key)) {
          final List<dynamic> options = entry.value;
          responseText = (options..shuffle()).first.toString();
          break;
        }
      }
    }

    // Default response if no intent or topic matches
    responseText ??= _brain?['default_fallback'] ?? 'I am in local mode. Try asking about Flutter or AI.';

    // Simulate streaming by splitting by tokens (words)
    final List<String> tokens = responseText!.split(' ');
    for (String token in tokens) {
      // Slower delay for long answers to make it feel more "thoughtful"
      await Future.delayed(const Duration(milliseconds: 70));
      yield '$token ';
    }
  }
}
