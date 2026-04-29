class AcronymExpander {
  static const Map<String, String> _expansions = {
    'emi': 'equated monthly instalment',
    'pemi': 'pre-emi pre equated monthly instalment interest',
    'ltv': 'loan to value ratio',
    'lap': 'loan against property',
    'ecs': 'electronic clearing service',
    'kyc': 'know your customer documents',
    'itr': 'income tax returns',
    'nri': 'non resident indian',
    'sme': 'small medium enterprise',
    'nbfc': 'non banking financial company',
  };

  static String expand(String query) {
    String q = query.toLowerCase().trim();
    _expansions.forEach((acronym, expansion) {
      // Use lookbehind and lookahead to ensure acronym isn't part of a hyphenated word (like pre-emi)
      final pattern = RegExp('(?<!-)\\b$acronym\\b(?!-)', caseSensitive: false);
      q = q.replaceAll(pattern, expansion);
    });
    return q;
  }

  static String expandQuery(String query) {
    // Only expand acronyms, don't add generic noise which pollutes the embedding vector
    return expand(query);
  }
}
