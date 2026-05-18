import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../theme/app_theme.dart';
import '../services/storage_service.dart';

class ThemeController extends GetxController {
  final StorageService _storage = Get.find<StorageService>();

  // 'light' | 'dark' | 'system'
  final RxString themeMode = 'system'.obs;

  @override
  void onInit() {
    super.onInit();
    final saved = _storage.getString('themeMode') ?? 'system';
    themeMode.value = saved;
    _applyTheme(saved);
  }

  void setTheme(String mode) {
    themeMode.value = mode;
    _storage.setString('themeMode', mode);
    _applyTheme(mode);
  }

  void _applyTheme(String mode) {
    switch (mode) {
      case 'light':
        Get.changeTheme(AppTheme.light());
        break;
      case 'dark':
        Get.changeTheme(AppTheme.dark());
        break;
      default:
        final brightness =
            WidgetsBinding.instance.platformDispatcher.platformBrightness;
        Get.changeTheme(
          brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
        );
    }
  }
}
