import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart' hide Condition;
import '../core/embedding_service.dart';
import '../data/document_chunk.dart';
import 'services/acronym_expander.dart';
import 'services/fuzzy_query_corrector.dart';
import '../objectbox.g.dart';
import '../core/services/log_service.dart';

// ── Query Intent ────────────────────────────────────────────────────────────
enum QueryIntent { documents, fees, eligibility, interest, tenure, process, definition, other }

class ScoredChunk {
  final DocumentChunk chunk;
  final double score;
  final double cosine;
  final double kw;
  final double boost;

  ScoredChunk({
    required this.chunk,
    required this.score,
    required this.cosine,
    required this.kw,
    required this.boost,
  });
}

class RagResult {
  final bool requiresLlm;
  final String content;
  final List<String> sources;
  final bool isFromKb;
  final String? context;
  final List<ScoredChunk> chunks;
  final QueryIntent intent;
  final bool contextSufficient;

  RagResult({
    required this.requiresLlm,
    required this.content,
    required this.sources,
    required this.chunks,
    this.isFromKb = false,
    this.context,
    this.intent = QueryIntent.other,
    this.contextSufficient = false,
  });

  factory RagResult.directBypass(String content, List<String> sources, List<ScoredChunk> chunks,
          {bool isFromKb = false, QueryIntent intent = QueryIntent.other, String? context}) =>
      RagResult(
          requiresLlm: false,
          content: content,
          sources: sources,
          chunks: chunks,
          isFromKb: isFromKb,
          intent: intent,
          context: context,
          contextSufficient: true);

  factory RagResult.llmGrounded(String context, List<String> sources, List<ScoredChunk> chunks,
          {QueryIntent intent = QueryIntent.other, bool contextSufficient = true}) =>
      RagResult(
          requiresLlm: true,
          content: '',
          context: context,
          sources: sources,
          chunks: chunks,
          intent: intent,
          contextSufficient: contextSufficient);

  factory RagResult.noAnswer() =>
      RagResult(requiresLlm: false, content: 'No answer available.', sources: [], chunks: [], contextSufficient: false);
}

class RagRetrievalService extends GetxService {
  final Store store;
  final EmbeddingService embeddingService;
  late final Box<DocumentChunk> chunkBox;

  // ── Document scope map ────────────────────────────────────────────────────
  static const Map<String, String> _documentScope = {
    'home loan': 'home_loan_faqs',
    'working capital': 'working_capital_loan_faqs',
    'unsecured': 'unsecured_business_loan_faqs',
    'business loan': 'unsecured_business_loan_faqs',
    'lap': 'loan_against_property_faqs',
    'loan against property': 'loan_against_property_faqs',
    'property loan': 'loan_against_property_faqs',
  };

  // ── Intent keyword BOOSTS (additive only — never block answers) ───────────
  static const Map<QueryIntent, List<String>> _intentKeywords = {
    QueryIntent.documents: [
      'kyc', 'pan', 'aadhaar', 'bank statement', 'itr',
      'document', 'proof', 'identity', 'address', 'requirement',
      'gst', 'balance sheet', 'passport', 'photograph', 'form',
      'criteria', 'eligibility', 'needed', 'mandatory', 'checklist',
    ],
    QueryIntent.fees: ['fee', 'charge', 'processing', 'cost', 'payment', 'applicable'],
    QueryIntent.eligibility: ['age', 'income', 'salary', 'cibil', 'score', 'eligible', 'criteria'],
    QueryIntent.interest: ['%', 'percent', 'rate', 'interest', 'roi', 'pa'],
    QueryIntent.tenure: ['tenure', 'year', 'month', 'duration', 'period', 'repay'],
    QueryIntent.definition: ['loan', 'purpose', 'means', 'refers', 'is a', 'defined', 'abbreviation', 'stands for', 'description'],
    QueryIntent.process: ['apply', 'process', 'step', 'procedure', 'how', 'application'],
    QueryIntent.other: [],
  };

  RagRetrievalService(this.store, this.embeddingService) {
    chunkBox = store.box<DocumentChunk>();
  }

  // ── Intent Detection ───────────────────────────────────────────────────────
  QueryIntent detectIntent(String query) {
    final q = query.toLowerCase();
    if (q.contains('document') || q.contains('paper') || q.contains('kyc') ||
        q.contains('what documents') || q.contains('which documents') ||
        q.contains('require') || (q.contains('need') && q.contains('loan'))) {
      return QueryIntent.documents;
    }
    if (q.contains('fee') || q.contains('charge') || q.contains('cost') || q.contains('processing')) {
      return QueryIntent.fees;
    }
    if (q.contains('eligib') || q.contains('qualify') || q.contains('criteria') || q.contains('who can')) {
      return QueryIntent.eligibility;
    }
    if (q.contains('interest') || q.contains(' rate') || q.contains('roi')) {
      return QueryIntent.interest;
    }
    if (q.contains('tenure') || q.contains('duration') || q.contains('how long')) {
      return QueryIntent.tenure;
    }
    if (q.contains('how to apply') || q.contains('process') || q.contains('steps')) {
      return QueryIntent.process;
    }
    if (q.contains('what is') || q.contains('define') || q.contains('meaning') || q.contains('explain')) {
      return QueryIntent.definition;
    }
    return QueryIntent.other;
  }

  // ── Header/Title Chunk Detection ───────────────────────────────────────────
  // Header chunks (like "HOME LOAN FAQ HOME LOAN FAQ") have no useful content.
  bool _isHeaderChunk(String text) {
    final t = text.trim();
    if (t.length < 80) return true; // Higher threshold for content
    
    // Catch repetitive titles even with slight variations
    final lower = t.toLowerCase();
    final words = lower.split(RegExp(r'\s+'));
    if (words.length >= 4 && words.length < 20) {
      final mid = words.length ~/ 2;
      final firstPart = words.sublist(0, mid).join(' ');
      final secondPart = words.sublist(mid).join(' ');
      if (firstPart.contains(secondPart) || secondPart.contains(firstPart)) return true;
    }

    if (t == t.toUpperCase() && t.length < 150) return true; 
    return false;
  }

  // ── Keyword boost (ADDITIVE only — keywords never block answers) ───────────
  double _computeKeywordBoost(String chunkText, QueryIntent intent) {
    if (intent == QueryIntent.other) return 1.0;
    final text = chunkText.toLowerCase();
    final keywords = _intentKeywords[intent] ?? [];
    final matches = keywords.where((k) => text.contains(k)).length;
    if (matches == 0) return 1.0;   // no boost — answer is NOT blocked
    if (matches == 1) return 1.20;
    if (matches == 2) return 1.35;
    return 1.50;                    // strong boost for 3+ keyword matches
  }

  // ── Deduplication by contentHash ──────────────────────────────────────────
  List<ScoredChunk> _deduplicateChunks(List<ScoredChunk> chunks) {
    final seen = <String>{};
    final unique = <ScoredChunk>[];
    for (final sc in chunks) {
      final key = sc.chunk.contentHash.isNotEmpty
          ? sc.chunk.contentHash
          : sc.chunk.text.substring(0, min(100, sc.chunk.text.length));
      if (!seen.contains(key)) {
        seen.add(key);
        unique.add(sc);
      } else {
        LogService.to.log('[RAG] Duplicate chunk removed: ${key.substring(0, min(30, key.length))}');
      }
    }
    LogService.to.log('[RAG] After dedup: ${unique.length} (removed ${chunks.length - unique.length} duplicates)');
    return unique;
  }

  String? resolveDocumentScope(String query) {
    final lower = query.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), '');
    for (final entry in _documentScope.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }
    return null;
  }

  Future<RagResult> retrieve(String rawQuery) async {
    final totalChunks = chunkBox.count();
    LogService.to.log('[RAG] Total chunks in DB: $totalChunks');
    LogService.to.log('[RAG] Raw Query: $rawQuery');

    if (totalChunks == 0) {
      LogService.to.log('[RAG] ERROR: ObjectBox is EMPTY');
      return RagResult.noAnswer();
    }

    final typoCorrected = FuzzyQueryCorrector.correct(rawQuery);
    final expanded = AcronymExpander.expand(typoCorrected);
    final resolvedScope = resolveDocumentScope(typoCorrected);
    final intent = detectIntent(typoCorrected);

    if (typoCorrected != rawQuery.toLowerCase().trim()) {
      LogService.to.log('[RAG] Corrected query: "$typoCorrected"');
    }
    if (resolvedScope != null) {
      LogService.to.log('[RAG] Scope resolved: $resolvedScope');
    }
    LogService.to.log('[RAG] Intent detected: $intent');

    // ── Vector Search with Intent Augmentation and Fallback ─────────────────
    final allCandidates = await _vectorSearchWithFallback(expanded, intent, resolvedScope);

    if (allCandidates.isEmpty) return RagResult.noAnswer();

    // ── Step 3: Filter header/title chunks ──────────────────────────────────
    final contentChunks = allCandidates.where((sc) => !_isHeaderChunk(sc.chunk.text)).toList();
    LogService.to.log('[RAG] Filtered ${allCandidates.length - contentChunks.length} header/title chunks');

    // Fall back to all chunks if header filter removed everything
    final candidates = contentChunks.isNotEmpty ? contentChunks : allCandidates;

    // ── Step 4: Deduplicate ─────────────────────────────────────────────────
    final deduped = _deduplicateChunks(candidates);
    if (deduped.isEmpty) return RagResult.noAnswer();

    // ── Step 5: Apply keyword BOOST (additive only — never blocks answers) ──
    final boosted = deduped.map((sc) {
      final kwBoost = _computeKeywordBoost(sc.chunk.text, intent);
      final tagBoost = _tagBoost(sc.chunk, typoCorrected);
      
      // NEW: Position Boost — definitions are usually in the first 6 chunks
      double posBoost = 1.0;
      if (sc.chunk.chunkIndex >= 0 && sc.chunk.chunkIndex <= 5) {
        posBoost = 1.25; // 25% boost for early document content
      }
      
      // NEW: Definition Sentence Boost - ONLY if it contains query subject
      double defBoost = 1.0;
      if (intent == QueryIntent.definition) {
        final textLower = sc.chunk.text.toLowerCase();
        // Remove common question words to find actual subjects
        final questionWords = ['what', 'is', 'are', 'how', 'does', 'do', 'can', 'a', 'the', 'of', 'in', 'for', 'to'];
        final subjects = typoCorrected.split(' ')
            .where((w) => w.length > 2 && !questionWords.contains(w))
            .toList();
            
        bool hasQuerySubject = subjects.any((s) => textLower.contains(s));
        
        // Match phrases like "EMI stands for", "LTV is a term", "Business loan is a type"
        final startsWithDef = RegExp(r'^(a|an|the|working|loan|emi|ltv|unsecured)\s+[\w\s&()]+\s+(is|stands for|refers to|means|is defined as)', caseSensitive: false);
        
        if (hasQuerySubject && startsWithDef.hasMatch(sc.chunk.text)) {
          defBoost = 1.40; // Stronger, targeted boost
        }
      }

      final newScore = (sc.score * kwBoost * posBoost * defBoost) + tagBoost;
      return ScoredChunk(
          chunk: sc.chunk, score: newScore, cosine: sc.cosine, kw: kwBoost, boost: tagBoost);
    }).toList();

    boosted.sort((a, b) => b.score.compareTo(a.score));

    // Log top 3 for debugging
    for (int i = 0; i < min(3, boosted.length); i++) {
      final c = boosted[i];
      LogService.to.log('[RAG] Score: ${c.score.toStringAsFixed(3)} | ${c.chunk.text.substring(0, min(60, c.chunk.text.length))}');
    }

    final top = boosted.first;

    // ── Step 6: Threshold check ─────────────────────────────────────────────
    final threshold = 0.40;
    LogService.to.log('[RAG] Top score: ${top.score.toStringAsFixed(3)} | Threshold: $threshold | Match: ${top.score >= threshold}');

    // If the top chunk score is below 0.40 even after keyword boost,
    // return a RagResult with a special flag: contextSufficient = false
    // The router must check this flag and return "not available" without calling LLM.
    final bool contextSufficient = top.score >= threshold;

    if (!contextSufficient) {
      LogService.to.log('[RAG] → NO ANSWER (below threshold) contextSufficient = false');
      return RagResult.llmGrounded(
        '', 
        [], 
        boosted.take(3).toList(), 
        intent: intent, 
        contextSufficient: false
      );
    }

    // ── Step 8: Build context for ALL paths (including bypass fallback) ──
    final int chunkLimit = 3; // Reduced for faster LLM processing
    
    var scoredChunks = boosted.where((s) => s.score >= threshold).toList();
    
    if (intent == QueryIntent.definition) {
      final definitionalPhrases = [
        'stands for', 'is defined as', 'abbreviated as',
        'refers to', 'full form', 'short for', 'means',
        'is a term', 'is a type', 'is a form', 'represents', 'denotes',
      ];
      
      // Extract subject words to prevent cross-topic definition promotion
      final stopWords = {'what', 'is', 'are', 'how', 'does', 'do', 'can', 'tell', 'me', 'about', 'explain', 'define', 'a', 'the', 'for', 'of', 'in', 'an', 'and', 'meaning'};
      final queryWords = typoCorrected.toLowerCase().split(RegExp(r'\W+'))
          .where((w) => w.length > 2 && !stopWords.contains(w))
          .toList();

      // Partition: only promote definitions that actually mention at least one query subject in proximity
      final defChunks = scoredChunks.where((c) {
        final text = c.chunk.text.toLowerCase();
        
        bool foundProximity = false;
        if (queryWords.isNotEmpty) {
          for (final phrase in definitionalPhrases) {
            final phrasePos = text.indexOf(phrase);
            if (phrasePos == -1) continue;
            
            // At least ONE subject should be near the definition phrase
            for (final subject in queryWords) {
              final subjectPos = text.indexOf(subject);
              if (subjectPos != -1 && (subjectPos - phrasePos).abs() <= 100) {
                foundProximity = true;
                break;
              }
            }
            if (foundProximity) break;
          }
        }
        
        final matchesSubject = queryWords.isNotEmpty && queryWords.any((w) => text.contains(w));
        return foundProximity && matchesSubject;
      }).toList();
      
      final otherChunks = scoredChunks.where((c) => !defChunks.contains(c)).toList();
      scoredChunks = [...defChunks, ...otherChunks];
    }

    final selected = scoredChunks.take(chunkLimit).toList();
    // Filter out empty/whitespace chunks from LLM context
    final validSelected = selected.where((s) => s.chunk.text.trim().length > 20).toList();
    final context = validSelected.map((s) => _sanitizeChunk(s.chunk.text)).join('\n---\n');

    LogService.to.log('[RAG] Final chunks: ${validSelected.length}');

    // ── Step 9: High-confidence bypass → serve directly ────────────────────
    // Definitions use a lower threshold for bypass because proximity matching is high-confidence
    final bypassThreshold = (intent == QueryIntent.definition) ? 0.70 : (resolvedScope != null ? 0.65 : 0.85);
    if (top.score >= bypassThreshold) {
      LogService.to.log('[RAG] → HIGH CONFIDENCE BYPASS (score ${top.score.toStringAsFixed(2)})');
      return RagResult.directBypass(
        _sanitizeChunk(top.chunk.text),
        _buildUniqueSources(validSelected),
        validSelected,
        isFromKb: top.chunk.isHardcoded,
        intent: intent,
        context: context,
      );
    }

    return RagResult.llmGrounded(
      context,
      _buildUniqueSources(validSelected),
      validSelected,
      intent: intent,
      contextSufficient: contextSufficient,
    );
  }

  bool chunkAnswersQuery(String queryLower, DocumentChunk chunk) {
    final chunkLower = chunk.text.toLowerCase();
    
    // Simple subject extraction: remove question words
    final questionWords = ['what', 'is', 'are', 'how', 'does', 'do', 'can', 
                           'tell', 'me', 'about', 'explain', 'define', 'a', 
                           'the', 'for', 'of', 'in'];
    final queryWords = queryLower.split(RegExp(r'\W+'))
        .where((w) => w.length > 2 && !questionWords.contains(w))
        .toList();
    
    int matchCount = queryWords.where((w) => chunkLower.contains(w)).length;
    double matchRatio = matchCount / queryWords.length;

    // Relaxed threshold: 30% is enough if it's a semantic match
    if (matchRatio >= 0.3) return true;

    // Intent-based fallback: Who/How/Requirements
    final lower = chunkLower;
    if (queryLower.contains('who') && (lower.contains('individual') || lower.contains('professional') || lower.contains('salaried') || lower.contains('self employed') || lower.contains('eligible'))) return true;
    if (queryLower.contains('how') && (lower.contains('process') || lower.contains('step') || lower.contains('apply') || lower.contains('method'))) return true;
    if (queryLower.contains('document') || queryLower.contains('require')) {
       if (lower.contains('kyc') || lower.contains('proof') || lower.contains('checklist') || lower.contains('pan')) return true;
    }

    return matchRatio >= 0.5;
  }

  String _augmentQueryForIntent(String query, QueryIntent intent) {
    switch (intent) {
      case QueryIntent.documents:
        return '$query required documents list checklist KYC identity proof';
      case QueryIntent.fees:
        return '$query processing fee charges cost amount';
      case QueryIntent.eligibility:
        return '$query eligible criteria age income salary requirement';
      case QueryIntent.definition:
        return '$query meaning definition what is description overview';
      default:
        return query;
    }
  }

  Future<List<ScoredChunk>> _vectorSearchWithFallback(
      String query, QueryIntent intent, String? scope) async {
    
    // Primary search with augmented query
    final augmented = _augmentQueryForIntent(query, intent);
    var results = await _vectorSearch(augmented, scope, 50); // Cast a wide net
    
    var filtered = results.where((sc) => !_isHeaderChunk(sc.chunk.text)).toList();
    filtered = _deduplicateChunks(filtered);
    
    // Check if any result actually answers the query
    bool hasRelevant = filtered.any((c) => chunkAnswersQuery(query.toLowerCase(), c.chunk));
    
    if (!hasRelevant) {
      LogService.to.log('[RAG] No relevant chunks found in primary search. Running secondary search...');
      // Secondary search: drop scope restriction, use raw query
      results = await _vectorSearch(query, null, 50);
      filtered = results.where((sc) => !_isHeaderChunk(sc.chunk.text)).toList();
      filtered = _deduplicateChunks(filtered);
    }
    
    return filtered;
  }

  // ── Internal: vector search helper ────────────────────────────────────────
  Future<List<ScoredChunk>> _vectorSearch(String query, String? scope, int limit) async {
    final queryEmbedding = await embeddingService.embed(query);

    Condition<DocumentChunk> condition = DocumentChunk_.embedding.nearestNeighborsF32(queryEmbedding, limit);
    if (scope != null) {
      condition = condition.and(DocumentChunk_.sourceDocumentTag.contains(scope));
    }

    final dbQuery = chunkBox.query(condition).build();
    final results = dbQuery.findWithScores();
    dbQuery.close();

    return results.map((result) {
      final chunk = result.object;
      final emb = chunk.embedding;
      final cosine = (emb != null && emb.isNotEmpty)
          ? _cosineSimilarity(queryEmbedding, emb)
          : (1.0 - result.score);
      double score = cosine * 0.70; // Higher multiplier for better threshold alignment
      if (chunk.isHardcoded) score *= 1.5;
      return ScoredChunk(chunk: chunk, score: score, cosine: cosine, kw: 1.0, boost: 0.0);
    }).toList();
  }

  List<String> _buildUniqueSources(List<ScoredChunk> chunks) {
    final seen = <String>{};
    final sources = <String>[];
    for (final s in chunks) {
      final label = _formatSource(s.chunk);
      if (!seen.contains(label)) {
        seen.add(label);
        sources.add(label);
      }
    }
    return sources;
  }

  double _tagBoost(DocumentChunk chunk, String query) {
    if (chunk.tags == null) return 0.0;
    return query.toLowerCase().contains(chunk.tags!.toLowerCase()) ? 0.05 : 0.0;
  }

  String _formatSource(DocumentChunk chunk) {
    String fileName = chunk.isHardcoded ? 'Knowledge Base — ${chunk.category ?? "FAQ"}' : (chunk.source ?? "Document");
    String excerpt = chunk.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (excerpt.length > 80) {
      excerpt = excerpt.substring(0, 80) + '...';
    }
    return '• [$fileName] — "$excerpt"';
  }

  String _sanitizeChunk(String raw) {
    return raw.replaceAll(RegExp(r'[■●•▪︎➤]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;
    double dot = 0, normA = 0, normB = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    final denom = sqrt(normA) * sqrt(normB);
    return denom == 0 ? 0.0 : (dot / denom).clamp(-1.0, 1.0);
  }
}
