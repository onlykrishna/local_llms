import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/storage_service.dart';
import '../../../routes/app_pages.dart';
import 'widgets/ai_engine_section.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: Get.back,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          // ── AI ENGINE ─────────────────────────────────────
          _SectionHeader(title: 'AI ENGINE'),
          const AiEngineSection(),

          const SizedBox(height: AppSpacing.md),

          // ── ACCOUNT ──────────────────────────────────────
          _SectionHeader(title: 'ACCOUNT'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.phone_outlined),
                  title: const Text('Phone Number'),
                  subtitle: Text(_userPhoneNumber),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.logout, color: AppColors.error),
                  title: Text(
                    'Sign Out',
                    style: TextStyle(color: AppColors.error),
                  ),
                  onTap: () => _confirmSignOut(context),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          // ── ABOUT ────────────────────────────────────────
          _SectionHeader(title: 'ABOUT'),
          Card(
            child: Column(
              children: [
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snap) {
                    final version = snap.hasData
                        ? '${snap.data!.version} (${snap.data!.buildNumber})'
                        : '—';
                    return ListTile(
                      leading: const Icon(Icons.info_outlined),
                      title: const Text('App Version'),
                      trailing: Text(
                        version,
                        style: theme.textTheme.bodySmall,
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Open Source Licenses'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: () => showLicensePage(context: context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Privacy Policy'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: () {
                    Get.snackbar(
                      'Privacy Policy',
                      'Visit https://example.com/privacy',
                      snackPosition: SnackPosition.BOTTOM,
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }

  String get _userPhoneNumber {
    try {
      return FirebaseAuth.instance.currentUser?.phoneNumber ?? 'Unknown';
    } catch (_) {
      return 'Unknown';
    }
  }

  void _confirmSignOut(BuildContext context) {
    Get.defaultDialog(
      title: 'Sign Out',
      middleText: 'Are you sure you want to sign out?',
      textConfirm: 'Sign Out',
      textCancel: 'Cancel',
      confirmTextColor: Colors.white,
      buttonColor: AppColors.error,
      onConfirm: () async {
        Get.back();
        await FirebaseAuth.instance.signOut();
        await Get.find<StorageService>().clearUid();
        Get.offAllNamed(AppRoutes.PHONE_INPUT);
      },
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// Section header
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.xs,
        bottom: AppSpacing.sm,
      ),
      child: Text(
        title,
        style: AppTextStyles.label.copyWith(
          color: Theme.of(context).colorScheme.onSurface.withAlpha(120),
        ),
      ),
    );
  }
}

