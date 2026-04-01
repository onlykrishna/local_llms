import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../core/services/settings_service.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Get.find<SettingsService>();
    final List<String> models = ['mistral', 'llama2', 'codellama', 'phi'];

    return Scaffold(
      appBar: AppBar(title: const Text('AI Settings')),
      body: ListView(
        children: [
          _buildSectionHeader('Model Configuration'),
          Obx(() => ListTile(
            title: const Text('Primary Local Model'),
            subtitle: const Text('Switch between downloaded Ollama models.'),
            trailing: DropdownButton<String>(
              value: settings.selectedModel.value,
              onChanged: (v) => settings.updateModel(v!),
              items: models.map((m) => DropdownMenuItem(value: m, child: Text(m.toUpperCase()))).toList(),
            ),
          )),
          const Divider(),
          _buildSectionHeader('Appearance'),
          Obx(() => ListTile(
            title: const Text('Dark Theme'),
            subtitle: const Text('Follow system or force dark mode.'),
            trailing: Switch(
              value: settings.isDarkMode.value,
              onChanged: (_) => settings.toggleDarkMode(),
            ),
          )),
          const Divider(),
          _buildSectionHeader('Server Info'),
          const ListTile(
            title: Text('Ollama Base URL'),
            subtitle: Text('Default: http://10.0.2.2:11434/api'),
          ),
          const ListTile(
            title: Text('App Version'),
            subtitle: Text('1.0.0 (Build 2026.04)'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.blueAccent,
        ),
      ),
    );
  }
}
