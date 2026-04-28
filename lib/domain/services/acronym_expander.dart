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
      q = q.replaceAll(RegExp(r'\b' + acronym + r'\b'), expansion);
    });
    return q;
  }

  static String expandQuery(String query) {
    // 1. Expand acronyms first
    String expanded = expand(query);
    
    // 2. For "what is X" / "what does X mean" patterns, 
    // add definition-oriented terms to enrich query vector
    final definitionPattern = RegExp(r'^what (is|are|does|do)\b', caseSensitive: false);
    if (definitionPattern.hasMatch(expanded)) {
      expanded = '$expanded definition meaning explanation description';
    }
    
    // 3. For extremely short queries, append search keywords
    final words = expanded.split(RegExp(r'\s+'));
    if (words.length < 4) {
      expanded = '$expanded finance banking details';
    }
    
    return expanded;
  }
}
