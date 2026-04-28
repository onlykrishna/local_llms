import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:path_provider/path_provider.dart';
import '../constants/app_constants.dart';
import '../models/model_registry.dart';

class SettingsService extends GetxService {
  final _storage = GetStorage();

  final ollamaIp = '192.168.1.100'.obs;
  final ollamaPort = '11434'.obs;
  final isDarkMode = false.obs;
  final contextWindow = 10.obs;
  
  // Dynamic Model Scaling
  final selectedModelId = ''.obs; 
  final selectedModel = ''.obs; // Current GGUF path
  final selectedDomain = 'Universal'.obs;

  Future<SettingsService> init() async {
    ollamaIp.value = _storage.read('ollama_ip') ?? '192.168.1.100';
    ollamaPort.value = _storage.read('ollama_port') ?? '11434';
    
    isDarkMode.value = _storage.read('is_dark_mode') ?? false;
    contextWindow.value = _storage.read('context_window') ?? 10;
    
    selectedModelId.value = _storage.read('active_model_id') ?? 'qwen2_5_1_5b';
    selectedModel.value = await getActiveModelPath() ?? '';
    selectedDomain.value = _storage.read('selected_domain') ?? 'Universal';
    
    _applyTheme();
    return this;
  }

  void updateDomain(String domain) {
    selectedDomain.value = domain;
    _storage.write('selected_domain', domain);
  }

  void updateModel(String id) async {
    selectedModelId.value = id;
    _storage.write('active_model_id', id);
    selectedModel.value = await getActiveModelPath() ?? '';
  }

  Future<String?> getActiveModelPath() async {
    if (selectedModelId.value.isEmpty) return null;
    
    final modelDef = ModelRegistry.models.firstWhereOrNull((m) => m.id == selectedModelId.value);
    if (modelDef == null) return null;

    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/models/${modelDef.fileName}';
    
    if (File(path).existsSync()) {
      return path;
    }
    return null;
  }

  String get modelLabel {
    if (selectedModelId.value.isEmpty) return 'No Engine';
    final modelDef = ModelRegistry.models.firstWhereOrNull((m) => m.id == selectedModelId.value);
    return modelDef?.displayName ?? 'Local AI';
  }

  String get ollamaServerUrl => 'http://${ollamaIp.value}:${ollamaPort.value}';

  void updateOllamaIp(String val) {
    ollamaIp.value = val;
    _storage.write('ollama_ip', val);
  }

  void updateOllamaPort(String val) {
    ollamaPort.value = val;
    _storage.write('ollama_port', val);
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
