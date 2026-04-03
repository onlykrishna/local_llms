import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import '../constants/app_constants.dart';

class SettingsService extends GetxService {
  final _storage = GetStorage();

  // Model & UI
  final RxString selectedModel = 'mistral'.obs; // We keep the variable name for now as it's used elsewhere
  final RxBool isDarkMode = true.obs;
  final RxBool useOfflineMode = false.obs;

  // Ollama connection
  final RxString ollamaIp = '192.168.1.100'.obs;
  final RxString ollamaPort = '11434'.obs;

  // Gemini API
  final RxString geminiApiKey = ''.obs;

  // Chat behaviour
  final RxInt contextWindow = 6.obs;
  final RxInt streamDelayMs = 0.obs;

  Future<SettingsService> init() async {
    // UPDATED to use AppConstants.modelPathKey ('model_path')
    selectedModel.value  = _storage.read(AppConstants.modelPathKey)      ?? 'mistral';
    isDarkMode.value     = _storage.read(AppConstants.isDarkModeKey)      ?? true;
    useOfflineMode.value = _storage.read(AppConstants.useOfflineModeKey)  ?? false;
    ollamaIp.value       = _storage.read('ollama_ip')                     ?? '192.168.1.100';
    ollamaPort.value     = _storage.read('ollama_port')                   ?? '11434';
    // Option B: Read from --dart-define at build time (most secure)
    // Build with: flutter build apk --dart-define=GEMINI_KEY=your_key_here
    geminiApiKey.value   = _storage.read('gemini_api_key') ?? 
        const String.fromEnvironment('GEMINI_KEY', defaultValue: '');
    contextWindow.value  = _storage.read('context_window')                ?? 6;
    streamDelayMs.value  = _storage.read('stream_delay_ms')               ?? 0;
    return this;
  }

  void updateModel(String model) {
    selectedModel.value = model;
    _storage.write(AppConstants.modelPathKey, model); // UPDATED to model_path key
  }

  void toggleDarkMode() {
    isDarkMode.value = !isDarkMode.value;
    _storage.write(AppConstants.isDarkModeKey, isDarkMode.value);
    Get.changeThemeMode(isDarkMode.value ? ThemeMode.dark : ThemeMode.light);
  }

  void toggleOfflineMode() {
    useOfflineMode.value = !useOfflineMode.value;
    _storage.write(AppConstants.useOfflineModeKey, useOfflineMode.value);
  }

  void updateOllamaIp(String ip) {
    ollamaIp.value = ip;
    _storage.write('ollama_ip', ip);
  }

  void updateOllamaPort(String port) {
    ollamaPort.value = port;
    _storage.write('ollama_port', port);
  }

  void updateGeminiKey(String key) {
    geminiApiKey.value = key;
    _storage.write('gemini_api_key', key);
  }

  void updateContextWindow(int val) {
    contextWindow.value = val;
    _storage.write('context_window', val);
  }

  void updateStreamDelay(int ms) {
    streamDelayMs.value = ms;
    _storage.write('stream_delay_ms', ms);
  }
}
