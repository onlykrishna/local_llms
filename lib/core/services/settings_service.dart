import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import '../constants/app_constants.dart';

class SettingsService extends GetxService {
  final _storage = GetStorage();
  
  final RxString selectedModel = 'mistral'.obs;
  final RxBool isDarkMode = true.obs;
  final RxBool useOfflineMode = false.obs;

  Future<SettingsService> init() async {
    selectedModel.value = _storage.read(AppConstants.selectedModelKey) ?? 'mistral';
    isDarkMode.value = _storage.read(AppConstants.isDarkModeKey) ?? true;
    useOfflineMode.value = _storage.read(AppConstants.useOfflineModeKey) ?? false;
    return this;
  }

  void updateModel(String model) {
    selectedModel.value = model;
    _storage.write(AppConstants.selectedModelKey, model);
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
}
