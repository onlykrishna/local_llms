import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/theme/app_theme.dart';
import 'core/constants/app_constants.dart';
import 'core/services/log_service.dart';
import 'domain/entities/chat_message.dart';
import 'domain/entities/download_state.dart';
import 'data/models/pdf_document_meta.dart';
import 'presentation/bindings/chat_binding.dart';
import 'presentation/pages/chat_page.dart';
import 'presentation/pages/settings_page.dart';
import 'presentation/pages/startup_page.dart';
import 'presentation/widgets/app_drawer.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Pre-startup core services
  Get.put(LogService());

  try {
    await GetStorage.init();
    await Hive.initFlutter();
    Hive.registerAdapter(ChatMessageAdapter());
    Hive.registerAdapter(DownloadStateAdapter());
    Hive.registerAdapter(PdfDocumentMetaAdapter());
    
    try {
      await Hive.openBox<ChatMessage>(AppConstants.chatBoxName);
      await Hive.openBox<PdfDocumentMeta>(AppConstants.pdfLibraryBoxName);
      await Hive.openBox<String>(AppConstants.bundledPdfHashesBoxName);
      await Hive.openBox(AppConstants.settingsBoxName);
    } catch (e) {
      LogService.to.log('🚨 Hive box corrupt, clearing: $e');
      await Hive.deleteBoxFromDisk(AppConstants.chatBoxName);
      await Hive.openBox<ChatMessage>(AppConstants.chatBoxName);
      await Hive.openBox<PdfDocumentMeta>(AppConstants.pdfLibraryBoxName);
      await Hive.openBox<String>(AppConstants.bundledPdfHashesBoxName);
      await Hive.openBox(AppConstants.settingsBoxName);
    }
    await Hive.openBox<DownloadState>(AppConstants.downloadBoxName);
  } catch (e) {
    LogService.to.log('🚨 Storage Init Error: $e');
  }

  runApp(const OfflineAIDemoApp());
}

class OfflineAIDemoApp extends StatelessWidget {
  const OfflineAIDemoApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Offline AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      initialRoute: '/',
      getPages: [
        GetPage(
          name: '/', 
          page: () => const StartupPage(),
        ),
        GetPage(
          name: '/home', 
          page: () => const HomeScreen(),
          binding: ChatBinding(),
        ),
      ],
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      behavior: HitTestBehavior.translucent,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/images/logo_icon.png', height: 24),
              const SizedBox(width: 10),
              const Text('Offline AI'),
            ],
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          flexibleSpace: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(color: Colors.transparent),
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings_rounded),
              onPressed: () => Get.to(() => const SettingsPage()),
            ),
          ],
        ),
        drawer: const AppDrawer(),
        body: const ChatPage(),
      ),
    );
  }
}
