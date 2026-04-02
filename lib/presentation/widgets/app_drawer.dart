import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../core/services/settings_service.dart';
import '../controllers/chat_controller.dart';
import '../pages/history_page.dart';
import '../pages/settings_page.dart';
import '../../core/services/hardware_inference_service.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Get.find<SettingsService>();
    final controller = Get.find<ChatController>();
    final hardware = Get.find<HardwareInferenceService>();

    return Drawer(
      child: Column(
        children: [
          _buildHeader(context),
          _buildAIUpgradeSection(context, hardware, controller),
          const Divider(),
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

  Widget _buildAIUpgradeSection(BuildContext context, HardwareInferenceService hardware, ChatController chatController) {
    return Obx(() {
      if (chatController.isHardwareReady.value) {
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.teal.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.teal.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.flash_on, color: Colors.teal),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Hardware AI Active', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    Text('Gemma 2B is powering your responses.', style: TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        );
      }

      return Container(
        margin: const EdgeInsets.all(12),
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [Colors.indigo.shade400, Colors.deepPurple.shade600],
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _handleUpgrade(context, hardware, chatController),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
              child: Row(
                children: [
                  const Icon(Icons.psychology, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text('Enable Pro Offline AI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        Text('One-click download (~1GB)', style: TextStyle(color: Colors.white70, fontSize: 11)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.white54),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  void _handleUpgrade(BuildContext context, HardwareInferenceService hardware, ChatController chatController) {
    final RxDouble progress = 0.0.obs;
    final RxString status = 'Downloading AI Brain...'.obs;

    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_download, size: 48, color: Colors.indigo),
            const SizedBox(height: 16),
            Obx(() => Text(status.value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
            const SizedBox(height: 24),
            Obx(() => LinearProgressIndicator(
              value: progress.value / 100,
              backgroundColor: Colors.indigo.withOpacity(0.1),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.indigo),
            )),
            const SizedBox(height: 12),
            Obx(() => Text('${progress.value.toInt()}% complete', style: const TextStyle(color: Colors.grey))),
            const SizedBox(height: 24),
            const Text(
              'Once complete, the app will run real AI inference directly on your phone.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
      isDismissible: false,
      enableDrag: false,
    );

    hardware.installRealAIBrain(
      onProgress: (p) {
        progress.value = p.toDouble();
        if (p >= 100) status.value = 'Installation Complete!';
      },
    ).then((_) {
      chatController.isHardwareReady.value = true;
      Get.back(); // close bottom sheet
      Get.snackbar('Success', 'AI Brain installed! You are now in Full Offline Power mode.', 
        snackPosition: SnackPosition.TOP, backgroundColor: Colors.teal, colorText: Colors.white);
    }).catchError((e) {
      Get.back();
      Get.snackbar('Error', e.toString(), 
        snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.redAccent, colorText: Colors.white);
    });
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
