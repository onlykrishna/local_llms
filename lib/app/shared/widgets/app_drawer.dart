import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/services/embedding_service.dart';
import '../../core/services/storage_service.dart';
import '../../routes/app_pages.dart';
import '../../core/theme/app_theme.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final embeddingSvc = Get.find<EmbeddingService>();
    final auth = FirebaseAuth.instance;

    return Drawer(
      child: Column(
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withOpacity(0.3),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/logo_small.png',
                    height: 60,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'AI Chat Assistant',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // ── AI STATUS ──────────────────────────────────
          ListTile(
            leading: Icon(Icons.psychology_outlined, color: theme.colorScheme.primary),
            title: const Text('AI Engine'),
            subtitle: Text(embeddingSvc.activeProviderName),
            trailing: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: embeddingSvc.isOpenAiActive ? Colors.green : Colors.orange,
              ),
            ),
          ),
          
          const Divider(),

          // ── NAVIGATION ────────────────────────────────
          ListTile(
            leading: const Icon(Icons.chat_bubble_outline),
            title: const Text('General Chat'),
            onTap: () {
              Get.back();
              Get.toNamed(AppRoutes.CHAT);
            },
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('PDF Knowledge Base'),
            onTap: () {
              Get.back();
              Get.toNamed(AppRoutes.PDF_CHAT);
            },
          ),
          
          const Spacer(),
          
          const Divider(),
          
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Settings'),
            onTap: () {
              Get.back();
              Get.toNamed(AppRoutes.SETTINGS);
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Sign Out', style: TextStyle(color: Colors.red)),
            onTap: () async {
              Get.back();
              await auth.signOut();
              await Get.find<StorageService>().clearUid();
              Get.offAllNamed(AppRoutes.PHONE_INPUT);
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
