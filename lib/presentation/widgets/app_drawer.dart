import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../core/services/settings_service.dart';
import '../controllers/chat_controller.dart';
import '../pages/history_page.dart';
import '../pages/settings_page.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Get.find<SettingsService>();
    final controller = Get.find<ChatController>();

    return Drawer(
      child: Column(
        children: [
          _buildHeader(context),
          ListTile(
            leading: const Icon(Icons.history_rounded, color: Colors.blueAccent),
            title: const Text('View Chat History'),
            onTap: () {
              Get.back();
              Get.to(() => const HistoryPage());
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings, color: Colors.indigoAccent),
            title: const Text('AI Configuration'),
            onTap: () {
              Get.back();
              Get.to(() => const SettingsPage());
            },
          ),
          Obx(() => ListTile(
            leading: Icon(
              settings.isDarkMode.value ? Icons.dark_mode : Icons.light_mode,
              color: Colors.orangeAccent,
            ),
            title: const Text('Dark Mode'),
            trailing: Switch(
              value: settings.isDarkMode.value,
              onChanged: (_) => settings.toggleDarkMode(),
            ),
          )),
          const Spacer(),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent),
            title: const Text('Clear Chat History'),
            onTap: () {
              _showConfirmClear(context, controller);
            },
          ),
          const SizedBox(height: 12),
          Text(
            'Offline AI v1.0.0',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return DrawerHeader(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Theme.of(context).primaryColor, Colors.blue.shade800],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircleAvatar(
              radius: 36,
              backgroundColor: Colors.white24,
              child: Icon(Icons.auto_awesome, color: Colors.white, size: 40),
            ),
            const SizedBox(height: 12),
            Text(
              'Local Intelligence',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showConfirmClear(BuildContext context, ChatController controller) {
    Get.defaultDialog(
      title: 'Clear History?',
      middleText: 'This will delete all messages locally.',
      textConfirm: 'Delete',
      textCancel: 'Cancel',
      confirmTextColor: Colors.white,
      buttonColor: Colors.red,
      onConfirm: () => controller.clearChat(),
    );
  }
}
