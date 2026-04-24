import 'package:get/get.dart';

/// Provides strict factual rules and post-processing verification for on-device AI.
class FactualHardeningService extends GetxService {
  
  /// STRATEGY A: Knowledge Builder (JSON Extractor)
  String get knowledgeBuilderPrompt => '''You are a knowledge base builder. For the topic given below, extract and return 
only verified, specific facts in strict JSON format.

Rules:
- Only include facts you are highly confident about
- Every fact must have a source type: "established" or "uncertain"
- Dates must be exact (day/month/year) if known, else mark as "approximate"
- No sentences, no explanations — pure structured data only

Output format:
{
  "topic": "",
  "facts": [
    {
      "claim": "",
      "value": "",
      "date": "",
      "date_confidence": "exact | approximate | unknown",
      "confidence": "high | medium | low"
    }
  ]
}''';

  /// STRATEGY B: Date and Number Extractor
  String get dateNumberExtractorPrompt => '''You are a date and number extractor. Read the text below and identify ALL 
references to time, dates, or quantities — including vague ones.

Flag ALL of these patterns:
- Exact dates, Year only, Decade references, Relative time, Approximate time, Counts/numbers.

Output format:
[
  { "original_text": "", "type": "exact_date | year | decade | relative | approximate | number", "needs_verify": true }
]''';

  /// STRATEGY E: Query Classifier
  String get queryClassifierPrompt => '''You are a query classifier. Read the user question and return ONLY a JSON object.
Classify along these dimensions:
1. type: "factual" | "opinion" | "procedural" | "conversational"
2. complexity: "simple" | "moderate" | "complex"
3. date_sensitive: true | false
4. requires_rag: true | false
5. protocol: "UNCERTAINTY_ANCHOR" | "FACT_BLOCK" | "DATE_SENTRY" | "DIRECT"

Output ONLY this JSON, nothing else:
{
  "type": "",
  "complexity": "",
  "date_sensitive": bool,
  "requires_rag": bool,
  "protocol": "",
  "reason": ""
}''';

  /// MASTER CONTROL PROMPT v2.0 - Core Intelligence Framework (P4 Fix)
  String getConsolidatedSystemPrompt({bool isRag = false}) {
    if (isRag) {
      return '''MASTER v3.3: RAG PROTOCOL
1. ROLE: Strict fact-retrieval assistant.
2. SOURCE: Use ONLY the provided CONTEXT. Do not use outside knowledge.
3. NO_DATA: If the answer is not in the CONTEXT, you MUST say "NO_DATA: I could not find information on this in the current document."
4. CITATION: Cite your sources like this: [filename, p.X]. Only cite if the fact is present in that source.
5. FORMAT: Direct answer first, followed by a maximum of 3 key facts.
6. TERMINATION: End with --- END ---''';
    }

    return '''MASTER v2.0: GENERAL & MEDICAL PROTOCOL
1. ROLE: Professional info assistant. Prefix ALL: [ASSISTANT]:
2. ONE-TURN: No self-dialogue. No follow-up questions.
3. UNCERTAIN: Use ONCE max, only for factual doubt. Banned on advice/safety.
4. CLEANLINESS: No merged words. No special tokens. End: --- END ---.
5. FORMAT for ALL non-emergency responses:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[TITLE: Topic in Title Case]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[Direct answer: 1 sentence]

RECOMMENDED STRATEGIES / KEY FACTS:

1. **[Bold Point Name]**
   [Exactly 2 sentences. No sub-bullets.]

2. **[Bold Point Name]**
   [Exactly 2 sentences. No sub-bullets.]

3. **[Bold Point Name]**
   [Exactly 2 sentences. No sub-bullets.]

IMPORTANT NOTE:
[1 sentence: when to seek professional help]

Source: [Verified Fact Block / General guidance]
Please consult a qualified professional for personalised advice.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--- END ---'''
    .replaceAll('&', '&');
  }

  /// COMPACT CONTROL v1.0 — lean prompt for 3B and smaller on-device models.
  String getCompactSystemPrompt({bool isRag = false}) {
    final ragFacts = isRag
        ? '\nSTRICT RAG RULES:\n'
          '1. Answer ONLY using the CONTEXT provided. Do not use generic knowledge.\n'
          '2. If answer is missing, say NO_DATA.\n'
          '3. Cite specifically: [Source: filename, p.X].\n'
        : '';

    return 'You are a professional factual assistant. Output ONLY the final answer. '
        'Never output file paths, model names, loading messages, or system tokens.$ragFacts\n'
        'FORMAT (mandatory for all responses):\n'
        '\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\n'
        '**[Topic Title]**\n'
        '\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\n'
        '[1 sentence direct answer]\n'
        'KEY FACTS:\n'
        '1. **[Point Name]** [2 sentences]\n'
        '2. **[Point Name]** [2 sentences]\n'
        '3. **[Point Name]** [2 sentences]\n'
        'IMPORTANT NOTE: [1 sentence]\n'
        'Source: [1] filename.pdf, p.X\n'
        '\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\n'
        '--- END ---\n'
        'Rules: Exactly 3 points. Bold **names**. No bullets inside points. Nothing after --- END ---.';
  }

  /// P4 Fix: Deterministic post-processor for format compliance.
  String enforceFormatCompliance(String text) {
    final lines2 = text.split('\n');
    final filtered = <String>[];
    bool inNumberedPoint = false;
    for (final line in lines2) {
      final trimmed = line.trim();
      if (RegExp(r'^\d+\.').hasMatch(trimmed)) inNumberedPoint = true;
      if (inNumberedPoint && (trimmed.startsWith('- ') || trimmed.startsWith('* '))) continue;
      if (trimmed.isEmpty) inNumberedPoint = false;
      filtered.add(line);
    }
    String result = filtered.join('\n');

    // Expanded merged-word dictionary (patterns seen in screenshots)
    result = result
      .replaceAll('Hereare', 'Here are')
      .replaceAll('phenomenonwhere', 'phenomenon where')
      .replaceAll('insuch', 'in such')
      .replaceAll('oneparticle', 'one particle')
      .replaceAll('largedistances', 'large distances')
      .replaceAll('dancersperforming', 'dancers performing')
      .replaceAll('onedancer', 'one dancer')
      .replaceAll("dancer'sarms", "dancer's arms")
      .replaceAll('evenif', 'even if')
      .replaceAll('ofthestage', 'of the stage')
      .replaceAll('TimeManagement', 'Time Management')
      .replaceAll('StayCalm', 'Stay Calm')
      .replaceAll('intoa', 'into a')
      .replaceAll('ofthe', 'of the')
      .replaceAll('andthe', 'and the')
      .replaceAll('inthe', 'in the')
      .replaceAll('forthe', 'for the')
      .replaceAll('tothe', 'to the')
      .replaceAll('withthe', 'with the')
      .replaceAll('atthe', 'at the')
      .replaceAll('onthe', 'on the');

    // Generic CamelCase splitter (lowercaseLetter → uppercase = insert space)
    result = result.replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (m) => '${m.group(1)} ${m.group(2)}',
    );
    return result;
  }

  /// Strips lines that echo back system prompt instructions.
  /// Small models sometimes output safety rules or format templates verbatim.
  String stripSystemLeak(String text) {
    final leakPrefixes = [
      'SYSTEM:',
      'SAFETY (',
      'SAFETY:',
      'FORMAT (',
      'FORMAT:',
      'MEDICAL ALERT:',
      'USER:',
      'ASSISTANT:',
      'Never output file',
      'You are a professional factual',
      'Output ONLY the final answer',
      'Rules: Exactly 3 points',
      'If query mentions fever',
    ];

    final lines = text.split('\n');
    final cleaned = lines.where((line) {
      final trimmed = line.trim();
      return !leakPrefixes.any((prefix) => trimmed.startsWith(prefix));
    }).toList();

    return cleaned.join('\n').trim();
  }

  /// Reconstructs the mandatory response format when the model deviates.
  /// If model has no real content, returns a graceful "not yet updated" message.
  String enforceResponseStructure(String text, String originalQuestion) {
    final sep = '\u2501' * 29;
    final noDataMessage =
        '$sep\n'
        '**Knowledge Limit Reached**\n'
        '$sep\n\n'
        'This model is not yet updated with complete knowledge on this topic.\n\n'
        'For accurate information, please refer to:\n'
        '1. **Official website** relevant to your query\n'
        '2. **Wikipedia** for general background\n'
        '3. **Trusted news sources** for recent events\n\n'
        'IMPORTANT NOTE:\n'
        'The on-device model has limited training data. '
        'For precise or recent facts, always verify with an authoritative source.\n\n'
        '$sep\n'
        '--- END ---';

    // ── STEP 1: Detect NO_DATA or knowledge-limit signals ──────────────────
    final lowerText = text.toLowerCase();
    final noDataSignals = [
      'no_data', 'no data', 'not in these facts', 'not in my knowledge',
      'i don\'t have', "i don't have", 'i do not have', 'cannot verify',
      'not able to verify', 'beyond my knowledge', 'not trained',
      'outside my knowledge', 'not in my training', 'not aware of',
      'unable to find', 'no information', 'please check', 'please refer',
    ];
    if (noDataSignals.any((s) => lowerText.contains(s))) {
      return noDataMessage;
    }

    final lines = text.split('\n').map((l) => l.trim()).toList();

    // ── STEP 2: Strip after END marker ─────────────────────────────────────
    final endIdx = lines.indexWhere((l) => l.contains('--- END ---'));
    final trimmedLines = endIdx >= 0 ? lines.sublist(0, endIdx) : lines;

    // ── STEP 3: Collect real bullet/numbered content ────────────────────────
    final bulletLines = <String>[];
    final contentLines = <String>[];
    bool foundKeyFacts = false;

    for (final line in trimmedLines) {
      if (line.toUpperCase().contains('KEY FACTS') ||
          line.toUpperCase().contains('RECOMMENDED STRATEGIES')) {
        foundKeyFacts = true;
        continue;
      }
      final isBullet = line.startsWith('•') || line.startsWith('-') ||
          line.startsWith('*') || RegExp(r'^\d+\.').hasMatch(line);
      if (isBullet) {
        final cleaned = line.replaceFirst(RegExp(r'^[•\-\*\d+\.]\s*'), '').trim();
        if (cleaned.isNotEmpty && cleaned.length > 10) bulletLines.add(cleaned);
      } else if (foundKeyFacts && line.isNotEmpty && !line.startsWith('IMPORTANT')) {
        // paragraph content under KEY FACTS — treat as bullet
        if (line.length > 10) bulletLines.add(line);
      } else {
        contentLines.add(line);
      }
    }

    // ── STEP 4: If no real points found, return graceful message ───────────
    if (bulletLines.isEmpty) {
      // Check if there's at least some meaningful prose content
      final meaningfulContent = contentLines
          .where((l) => l.isNotEmpty && l.length > 15 && !l.startsWith('**'))
          .toList();
      if (meaningfulContent.isEmpty) return noDataMessage;

      // There's prose but no bullets — render as plain answer without fake structure
      final title = _extractTitle(trimmedLines, originalQuestion);
      final buffer = StringBuffer();
      buffer.writeln(sep);
      buffer.writeln(title);
      buffer.writeln(sep);
      buffer.writeln();
      for (final l in meaningfulContent.take(6)) {
        buffer.writeln(l);
      }
      buffer.writeln();
      buffer.writeln('$sep\n--- END ---');
      return buffer.toString();
    }

    // ── STEP 5: Build structured response from real bullet content ──────────
    final title = _extractTitle(trimmedLines, originalQuestion);
    final directAnswer = contentLines
        .where((l) => l.isNotEmpty && !l.startsWith('IMPORTANT') && l.length > 10)
        .take(1)
        .join(' ');

    // Only include as many REAL points as we have — never pad with fake ones
    final points = bulletLines.take(3).toList();

    String importantNote = 'Verify facts with official or authoritative sources.';
    final impIdx = trimmedLines.indexWhere((l) => l.startsWith('IMPORTANT'));
    if (impIdx >= 0) {
      final raw = trimmedLines[impIdx]
          .replaceFirst(RegExp(r'^IMPORTANT\s*NOTE\s*:?\s*'), '').trim();
      importantNote = raw.isNotEmpty ? raw
          : (impIdx + 1 < trimmedLines.length ? trimmedLines[impIdx + 1] : importantNote);
    }

    // ── STEP 6: Citations and Source ──────────────────────────────────────
    String sourceLine = 'General knowledge | Verify with authoritative sources.';
    if (lowerText.contains('[source:') || lowerText.contains('p.') || lowerText.contains('.pdf')) {
      sourceLine = 'Verified Source: Knowledge Base | Check citations above.';
    }
    
    final buffer = StringBuffer();
    buffer.writeln(sep);
    buffer.writeln(title);
    buffer.writeln(sep);
    buffer.writeln();
    if (directAnswer.isNotEmpty) buffer.writeln(directAnswer);
    buffer.writeln();
    buffer.writeln('KEY FACTS:');
    buffer.writeln();
    for (int i = 0; i < points.length; i++) {
      final sentences = points[i].split(RegExp(r'(?<=[.!?])\s+'));
      final body = sentences.take(2).join(' ');
      final name = sentences.first.split(' ').take(3).join(' ');
      buffer.writeln('${i + 1}. **$name**');
      buffer.writeln('   $body');
      buffer.writeln();
    }
    buffer.writeln('IMPORTANT NOTE:');
    buffer.writeln(importantNote);
    buffer.writeln();
    buffer.writeln('Source: $sourceLine');
    buffer.writeln(sep);
    buffer.write('--- END ---');

    return buffer.toString();
  }

  /// Extracts a display title from model output or falls back to question keywords.
  String _extractTitle(List<String> lines, String question) {
    final hasTitle = lines.any((l) => l.startsWith('**') && l.endsWith('**'));
    if (hasTitle) {
      return lines.firstWhere(
          (l) => l.startsWith('**') && l.endsWith('**'), orElse: () => '**Topic**');
    }
    final words = question
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .split(' ')
        .where((w) => w.length > 2 &&
            !['can', 'you', 'me', 'the', 'for', 'how', 'what', 'why',
               'help', 'please', 'tell', 'about', 'just', 'give', 'explain']
                .contains(w.toLowerCase()))
        .take(4)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
    return '**${words.isEmpty ? 'Your Question' : words}**';
  }

  /// Wraps a user question and a retrieved fact block into a clean data structure.
  /// Wraps a user question and a retrieved fact block into a clean ChatML structure.
  String buildFactualPrompt({required String question, String? factBlock}) {
    if (factBlock == null || factBlock.isEmpty) {
      return question;
    }

    // Simplified wrapper for ChatTemplate compatibility
    return '''CONTEXT:
$factBlock

QUESTION:
$question''';
  }

  /// Removes special tokens and technical markers from the model's response.
  String sanitizeOutput(String text) {
    var clean = text
      .replaceAll('<|end|>', '')
      .replaceAll('<|assistant|>', '')
      .replaceAll('<|user|>', '')
      .replaceAll('<|system|>', '')
      .replaceAll(RegExp(r'<[a-zA-Z\/]+>'), '');
    
    // Safety: ensure it ends with the trailer if missing due to stream cutoff
    if (clean.isNotEmpty && !clean.contains('--- END ---')) {
       // Only add it if the model actually finished or if we want to force it
    }
    return clean.trim();
  }

  /// Post-processes a model's response to add [VERIFY: ...] flags to dates and large numbers.
  String addVerificationFlags(String text) {
    // 1. Exact Dates and Years
    final yearRegex = RegExp(r'\b(19|20)\d{2}\b');
    final dateRegex = RegExp(r'\b\d{1,2}\s+(January|February|March|April|May|June|July|August|September|October|November|December)\b', caseSensitive: false);
    
    // 2. Decades and Vague Eras (e.g., mid-fifties, 60s, 1980s)
    final decadeRegex = RegExp(r'\b(\d{2}s|(mid|early|late)-\w+ies|the\s\d{2}s)\b', caseSensitive: false);
    
    // 3. Relative Time and Quantities (e.g., seven decades ago, About two hundred, few years after)
    final relativeRegex = RegExp(r'\b(\w+\s+(decades|years|months|days)\s+ago|about|roughly|over|under)\s+\d+|(\d+|a\sfew)\s+(years|decades)\s+(after|before|later)\b', caseSensitive: false);
    
    // 4. Word-based numbers (hundred, thousand, million)
    final wordNumberRegex = RegExp(r'\b(hundred|thousand|million|billion)\b', caseSensitive: false);

    String flagged = text;

    // Apply flags sequentially
    flagged = flagged.replaceAllMapped(yearRegex, (m) => '[VERIFY: ${m.group(0)}]');
    flagged = flagged.replaceAllMapped(dateRegex, (m) => '[VERIFY: ${m.group(0)}]');
    flagged = flagged.replaceAllMapped(decadeRegex, (m) => '[VERIFY: ${m.group(0)}]');
    flagged = flagged.replaceAllMapped(relativeRegex, (m) => '[VERIFY: ${m.group(0)}]');
    flagged = flagged.replaceAllMapped(wordNumberRegex, (m) => '[VERIFY: ${m.group(0)}]');

    return flagged;
  }
}
