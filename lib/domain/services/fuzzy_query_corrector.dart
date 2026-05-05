import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../core/services/log_service.dart';

class FuzzyQueryCorrector {
  /// Known corrections dictionary (deterministic, highly reliable)
  static const Map<String, String> _corrections = {
    'homelan': 'home loan',
    'homlan': 'home loan',
    'homeloan': 'home loan',
    'homelone': 'home loan',
    'homelong': 'home loan',
    'homlon': 'home loan',
    'workin capital': 'working capital',
    'working captial': 'working capital',
    'workingg capital': 'working capital',
    'unsecure': 'unsecured',
    'unsecure loan': 'unsecured loan',
    'propety loan': 'property loan',
    'proprty loan': 'property loan',
  };

  /// Domain-specific keywords to check against for word-level correction
  static const List<String> _knownTerms = [
    'home', 'loan', 'working', 'capital', 'unsecured',
    'business', 'property', 'documents', 'eligibility',
    'interest', 'rate', 'emi', 'tenure', 'apply',
  ];

  static String normalize(String input) {
    return input
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), '') // remove punctuation
        .replaceAll(RegExp(r'\s+'), ' ');       // normalize spaces
  }

  static String correctQuery(String query) {
    final normalized = normalize(query);
    LogService.to.log('[FUZZY] Normalized query: "$normalized"');

    // Step 1: Check full-phrase corrections dictionary first (highest priority)
    if (_corrections.containsKey(normalized)) {
      final fixed = _corrections[normalized]!;
      LogService.to.log('[FUZZY] Full-phrase dictionary match: "$normalized" -> "$fixed"');
      return fixed;
    }

    // Step 2: Word-by-word correction
    final words = normalized.split(' ');
    final correctedWords = words.map((w) {
      // 2a. Check dictionary for the single word (e.g. "homelan" -> "home loan")
      if (_corrections.containsKey(w)) {
        return _corrections[w]!;
      }
      // 2b. Fallback to Levenshtein correction against known terms
      return _correctWord(w);
    }).toList();

    final result = correctedWords.join(' ');

    if (result != normalized) {
      LogService.to.log('[FUZZY] Corrected: "$normalized" -> "$result"');
    }
    
    return result;
  }

  static String _correctWord(String word) {
    if (word.length < 3) return word; 
    if (_knownTerms.contains(word)) return word; 

    String best = word;
    int bestDist = 2; // max edit distance allowed

    for (final term in _knownTerms) {
      final dist = _levenshtein(word, term);
      if (dist < bestDist) {
        bestDist = dist;
        best = term;
      }
    }
    return best;
  }

  static int _levenshtein(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    List<int> v0 = List<int>.generate(s2.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(s2.length + 1, 0);

    for (int i = 0; i < s1.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < s2.length; j++) {
        int cost = (s1[i] == s2[j]) ? 0 : 1;
        v1[j + 1] = min(v1[j] + 1, min(v0[j + 1] + 1, v0[j] + cost));
      }
      for (int j = 0; j < v0.length; j++) {
        v0[j] = v1[j];
      }
    }
    return v0[s2.length];
  }

  /// Legacy compatibility — calls the new logic
  static String correct(String query) => correctQuery(query);
}
