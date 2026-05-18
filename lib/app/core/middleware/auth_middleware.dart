import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

    // Dynamic sync with Firebase Auth in case GetStorage was cleared but native Firebase Auth session is active
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      storage.saveUid(currentUser.uid);
    }

    // Already authenticated → go straight to setup (or chat/home if already setup)
    if (storage.getUid() != null || currentUser != null) {
      final setupComplete = storage.getBool('setupComplete') ?? false;
      if (setupComplete) {
        return const RouteSettings(name: AppRoutes.CHAT);
      }
      return const RouteSettings(name: AppRoutes.SETUP);
    }

    return null;
  }
}
