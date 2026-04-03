import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../core/services/settings_service.dart';
import '../../domain/services/inference_router.dart';
import '../../domain/services/domain_service.dart';
import '../controllers/chat_controller.dart';
import '../pages/history_page.dart';
import '../pages/settings_page.dart';
import '../screens/model_setup_screen.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Get.find<SettingsService>();
    final controller = Get.find<ChatController>();
    final router = Get.find<InferenceRouterService>();
    final domainService = Get.find<DomainService>();

    return Drawer(
      child: Column(
        children: [
          _buildHeader(context),
          // Backend status card
          Obx(() => _BackendCard(backend: router.currentBackend.value)),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.memory_rounded, color: Colors.indigoAccent),
            title: const Text('AI Model Setup'),
            subtitle: const Text('Download Llama 3.2 1B'),
            onTap: () {
              Get.back();
              Get.to(() => const ModelSetupScreen());
            },
          ),
          ListTile(
            leading: const Icon(Icons.history_rounded, color: Colors.blueAccent),
            title: const Text('Chat History'),
            onTap: () {
              Get.back();
              Get.to(() => const HistoryPage());
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings, color: Colors.indigoAccent),
            title: const Text('Settings'),
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
          const Divider(),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
            title: const Text('Clear Chat'),
            onTap: () => controller.clearChat(),
          ),
          const Spacer(),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Selective Inference v2.0\nHealth · Bollywood · Education · General',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return DrawerHeader(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.indigo.shade800, Colors.deepPurple.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: const [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.white24,
            child: Icon(Icons.psychology, color: Colors.white, size: 28),
          ),
          SizedBox(height: 12),
          Text('Offline AI',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
          Text('3-Layer Selective Inference',
              style: TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }
}

class _BackendCard extends StatelessWidget {
  final InferenceBackend backend;
  const _BackendCard({required this.backend});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _color.withAlpha(25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _color.withAlpha(80)),
      ),
      child: Row(
        children: [
          Container(
            width: 10, height: 10,
            decoration: BoxDecoration(shape: BoxShape.circle, color: _color),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_label,
                  style: TextStyle(fontWeight: FontWeight.bold, color: _color, fontSize: 13)),
              Text(_subtitle, style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }

  Color get _color {
    switch (backend) {
      case InferenceBackend.gemini:   return Colors.green;
      case InferenceBackend.ollama:   return Colors.blue;
      case InferenceBackend.onDevice: return Colors.orange;
    }
  }

  String get _label {
    switch (backend) {
      case InferenceBackend.gemini:   return 'Online (Gemini Flash)';
      case InferenceBackend.ollama:   return 'Ollama LAN';
      case InferenceBackend.onDevice: return 'On-device AI';
    }
  }

  String get _subtitle {
    switch (backend) {
      case InferenceBackend.gemini:   return 'Free tier · 1M tokens/day';
      case InferenceBackend.ollama:   return 'Local LAN server';
      case InferenceBackend.onDevice: return 'Llama 3.2 1B — 100% offline';
    }
  }
}
