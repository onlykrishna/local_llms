import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import 'app/core/services/analytics_service.dart';
import 'app/core/services/api_provider_service.dart';
import 'app/core/services/chat_history_service.dart';
import 'app/core/services/connectivity_service.dart';
import 'app/core/services/embedding_service.dart';
import 'app/core/services/pdf_chat_service.dart';
import 'app/core/services/pdf_processing_service.dart';
import 'app/core/services/storage_service.dart';
import 'app/core/theme/app_theme.dart';
import 'app/core/theme/theme_controller.dart';
import 'app/routes/app_pages.dart';

void main() async {
  // 1. Ensure binding + preserve splash
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // 2. Load environment variables
  await dotenv.load(fileName: '.env');

  // 3. Initialize Firebase
  await Firebase.initializeApp();

  // 4. Crashlytics error hooks
  FlutterError.onError =
      FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  // 5. App Check
  try {
    await FirebaseAppCheck.instance.activate(
      androidProvider: kDebugMode 
          ? AndroidProvider.debug 
          : AndroidProvider.playIntegrity,
      appleProvider: kDebugMode 
          ? AppleProvider.debug 
          : AppleProvider.appAttest,
    );
  } catch (e, stack) {
    debugPrint("Firebase App Check activation failed: $e");
    FirebaseCrashlytics.instance.recordError(e, stack, reason: 'App Check activation failed');
  }

  // 6. Local storage init
  await GetStorage.init();

  // 7. Register services in dependency order
  final storage = await Get.putAsync(() async => StorageService());

  // Synchronize Firebase Auth session with local storage on startup
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await storage.saveUid(user.uid);
      debugPrint("🔐 main: Active Firebase user session synchronized with local storage (UID: ${user.uid})");
    }
  } catch (e) {
    debugPrint("⚠️ main: Failed to sync Firebase user session: $e");
  }
  Get.put(ThemeController());
  Get.put(ConnectivityService());
  Get.put(ApiProviderService());
  Get.put(ChatHistoryService());
  Get.put(PdfProcessingService());
  Get.put(EmbeddingService());
  Get.put(PdfChatService());
  Get.put(AnalyticsService());

  // 8. Enable Analytics collection
  await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(!kDebugMode);

  // 9. Remove splash and launch app
  FlutterNativeSplash.remove();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'AI Chat',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      themeMode: ThemeMode.light,
      initialRoute: AppRoutes.PHONE_INPUT,
      getPages: AppPages.routes,
    );
  }
}
