import 'package:flutter/foundation.dart';
import '../data/hardcoded_kb.dart';

class HardcodedKbService {

  /// Looks up the best matching KB entry for a user query.
  /// Returns null if no confident match found.
  KbEntry? lookup(String rawQuery) {
    final q = _normalize(rawQuery);

    KbEntry? bestEntry;
    int bestScore = 0;

    for (final entry in kFaqsKnowledgeBase) {
      int score = 0;
      for (final keyword in entry.keywords) {
        if (q.contains(_normalize(keyword))) {
          // Longer keyword matches score higher
          score += keyword.split(' ').length * 2;
        }
      }
      if (score > bestScore) {
        bestScore = score;
        bestEntry = entry;
      }
    }

    // Require at least score 2 to avoid false positives
    return bestScore >= 2 ? bestEntry : null;
  }

  String _normalize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
