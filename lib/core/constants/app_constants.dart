class AppConstants {
  // Ollama (dynamic now — defaults only used if SettingsService not loaded)
  static const String ollamaBaseUrl = 'http://192.168.1.100:11434/api';
  static const int requestTimeout = 30;

  // Fallback dataset
  static const String fallbackDatasetPath = 'assets/fallback_dataset.json';
  static const String localBrainPath = 'assets/local_brain.json';
  static const int fallbackTriggerLength = 5;

  // Hive boxes
  static const String chatBoxName = 'chat_history';
  static const String kbVersion = 'v1.7';
  static const String settingsBoxName = 'settings';
  static const String downloadBoxName = 'download_history';
  static const String pdfLibraryBoxName = 'pdf_library';
  static const String bundledPdfHashesBoxName = 'bundled_pdf_hashes';

  // GetStorage keys
  static const String modelPathKey = 'model_path'; // EXACTLY AS REQUESTED
  static const String isDarkModeKey = 'is_dark_mode';
  static const String useOfflineModeKey = 'use_offline_mode';
}
