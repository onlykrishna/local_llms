import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/storage_service.dart';
import '../../routes/app_pages.dart';

class AuthMiddleware extends GetMiddleware {
  @override
  RouteSettings? redirect(String? route) {
    final storage = Get.find<StorageService>();

    // First launch → show onboarding
    final seen = storage.getBool('onboardingSeen') ?? false;
    if (!seen) {
      return const RouteSettings(name: AppRoutes.ONBOARDING);
    }

    // Already authenticated → go straight to chat
    if (storage.getUid() != null) {
      return const RouteSettings(name: AppRoutes.CHAT);
    }

    return null;
  }
}
