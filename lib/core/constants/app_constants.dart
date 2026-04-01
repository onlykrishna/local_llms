/// Centralized constants for the Offline AI Flutter demo app.
///
/// This file groups together URLs, keys, and configuration values that are
/// used throughout the application. Keeping them in a single place makes the
/// codebase easier to maintain and enables quick adjustments for different
/// environments (development, staging, production).

class AppConstants {
  // ---------------------------------------------------------------------
  // Network configuration
  // ---------------------------------------------------------------------
  /// Base URL for the local Ollama server. The default points to the Android
  /// emulator's host‑only address. Adjust if you run Ollama on a different
  /// device or port.
  static const String ollamaBaseUrl = 'http://192.168.68.115:11434/api';

  /// Timeout (in seconds) for HTTP requests to the Ollama server.
  static const int requestTimeout = 30;

  // ---------------------------------------------------------------------
  // Fallback dataset configuration
  // ---------------------------------------------------------------------
  /// Path to the bundled JSON file that contains offline fallback responses.
  static const String fallbackDatasetPath = 'assets/fallback_dataset.json';

  /// Minimum number of characters to generate before falling back to the
  /// dataset when the LLM does not respond.
  static const int fallbackTriggerLength = 5;

  // ---------------------------------------------------------------------
  // Hive storage keys
  // ---------------------------------------------------------------------
  static const String chatBoxName = 'chat_history';

  // ---------------------------------------------------------------------
  // GetStorage keys (persisted user preferences)
  // ---------------------------------------------------------------------
  static const String selectedModelKey = 'selected_model';
  static const String isDarkModeKey = 'is_dark_mode';
}
