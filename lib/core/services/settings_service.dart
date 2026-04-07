import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import '../constants/app_constants.dart';

class SettingsService extends GetxService {
  final _storage = GetStorage();

  final ollamaIp = '192.168.1.100'.obs;
  final ollamaPort = '11434'.obs;
  final geminiApiKey = ''.obs;
  final isDarkMode = false.obs;
  final contextWindow = 10.obs;
  
  // Model path for llamadart (GGUF)
  final selectedModel = ''.obs; // Empty by default to trigger 'Not configured' UI

  Future<SettingsService> init() async {
    ollamaIp.value = _storage.read('ollama_ip') ?? '192.168.1.100';
    ollamaPort.value = _storage.read('ollama_port') ?? '11434';
    
    // Use environment define as fallback for release builds
    const envKey = String.fromEnvironment('GEMINI_KEY');
    geminiApiKey.value = _storage.read('gemini_key') ?? envKey;
    
    isDarkMode.value = _storage.read('is_dark_mode') ?? false;
    contextWindow.value = _storage.read('context_window') ?? 10;
    selectedModel.value = _storage.read(AppConstants.modelPathKey) ?? '';
    
    _applyTheme();
    return this;
  }

  void updateOllamaIp(String val) {
    ollamaIp.value = val;
    _storage.write('ollama_ip', val);
  }

  void updateOllamaPort(String val) {
    ollamaPort.value = val;
    _storage.write('ollama_port', val);
  }

  void updateGeminiKey(String val) {
    geminiApiKey.value = val;
    _storage.write('gemini_key', val);
  }

  void updateModel(String path) {
    selectedModel.value = path;
    _storage.write(AppConstants.modelPathKey, path);
  }

  void toggleDarkMode(bool val) {
    isDarkMode.value = val;
    _storage.write('is_dark_mode', val);
    _applyTheme();
  }

  void updateContextWindow(int count) {
    contextWindow.value = count;
    _storage.write('context_window', count);
  }

  void _applyTheme() {
    Get.changeThemeMode(isDarkMode.value ? ThemeMode.dark : ThemeMode.light);
  }
}
