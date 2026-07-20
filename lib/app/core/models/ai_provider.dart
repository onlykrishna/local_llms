/// AI provider options for chat generation.
/// Embeddings provider (OpenAI vs HuggingFace) is controlled separately by [EmbeddingService].
enum AiProvider {
  groq(
    'Groq',
    'llama-3.3-70b-versatile',
    'https://api.groq.com/openai/v1/chat/completions',
  ),
  gemini(
    'Gemini',
    'gemini-1.5-flash',
    'https://generativelanguage.googleapis.com/v1beta/models',
  ),
  openai(
    'OpenAI',
    'gpt-4o-mini',
    'https://api.openai.com/v1/chat/completions',
  ),
  offline(
    'Offline (Llama)',
    'local-gguf',
    '',
  );

  const AiProvider(this.displayName, this.modelId, this.endpoint);
  final String displayName;
  final String modelId;
  final String endpoint;

  bool get requiresNetwork => this != AiProvider.offline;
  bool get requiresApiKey => this != AiProvider.offline;

  // Returns correct model for the request type
  String modelIdForRequest({bool hasImage = false}) {
    switch (this) {
      case AiProvider.groq:
        // qwen/qwen3.6-27b supports vision; llama-3.3-70b for text-only
        return hasImage
            ? 'qwen/qwen3.6-27b'
            : 'llama-3.3-70b-versatile';
      case AiProvider.gemini:
        return 'gemini-1.5-flash'; // handles both text and vision natively
      case AiProvider.openai:
        return 'gpt-4o-mini'; // handles both
      case AiProvider.offline:
        return 'local-gguf';
    }
  }

  // Env key name for fallback
  String get envKeyName {
    switch (this) {
      case AiProvider.groq: return 'GROQ_API_KEY';
      case AiProvider.gemini: return 'GEMINI_API_KEY';
      case AiProvider.openai: return 'OPENAI_API_KEY';
      case AiProvider.offline: return '';
    }
  }
}
