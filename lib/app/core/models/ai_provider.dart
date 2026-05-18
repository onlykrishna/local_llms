enum AiProvider { openai, groq }

extension AiProviderExtension on AiProvider {
  String get displayName {
    switch (this) {
      case AiProvider.openai: return 'OpenAI';
      case AiProvider.groq:   return 'Groq';
    }
  }

  String get modelId {
    switch (this) {
      case AiProvider.openai: return 'gpt-4o-mini';
      case AiProvider.groq:   return 'llama-3.3-70b-versatile';
    }
  }

  String get endpoint {
    switch (this) {
      case AiProvider.openai:
        return 'https://api.openai.com/v1/chat/completions';
      case AiProvider.groq:
        return 'https://api.groq.com/openai/v1/chat/completions';
    }
  }
}
