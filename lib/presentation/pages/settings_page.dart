import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../core/services/settings_service.dart';
import '../screens/model_setup_screen.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Get.find<SettingsService>();
    final ollamaIpCtrl = TextEditingController(text: s.ollamaIp.value);
    final ollamaPortCtrl = TextEditingController(text: s.ollamaPort.value);
    final geminiKeyCtrl = TextEditingController(text: s.geminiApiKey.value);
    final RxString connectionResult = ''.obs;
    final RxBool obscureKey = true.obs;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── AI Backend ─────────────────────────────────────────
          _header('AI Backend'),
          TextField(
            controller: ollamaIpCtrl,
            decoration: const InputDecoration(
              labelText: 'Ollama IP Address',
              hintText: '192.168.1.100',
              prefixIcon: Icon(Icons.lan_rounded),
            ),
            onChanged: s.updateOllamaIp,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: ollamaPortCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Ollama Port',
              hintText: '11434',
              prefixIcon: Icon(Icons.settings_ethernet),
            ),
            onChanged: s.updateOllamaPort,
          ),
          const SizedBox(height: 8),
          Obx(() => ElevatedButton.icon(
                icon: const Icon(Icons.network_check_rounded),
                label: const Text('Test Ollama Connection'),
                onPressed: () async {
                  connectionResult.value = 'Testing...';
                  try {
                    final stopwatch = Stopwatch()..start();
                    await Dio().get(
                      'http://${s.ollamaIp.value}:${s.ollamaPort.value}/api/tags',
                      options: Options(receiveTimeout: const Duration(milliseconds: 2000)),
                    );
                    stopwatch.stop();
                    connectionResult.value =
                        '✅ Ollama reachable (${stopwatch.elapsedMilliseconds}ms)';
                  } catch (e) {
                    connectionResult.value = '❌ Unreachable: $e';
                  }
                },
              )),
          Obx(() => connectionResult.value.isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(connectionResult.value,
                      style: TextStyle(
                          color: connectionResult.value.startsWith('✅')
                              ? Colors.green
                              : Colors.red,
                          fontSize: 12)),
                )),
          const SizedBox(height: 16),
          Obx(() => TextField(
                controller: geminiKeyCtrl,
                obscureText: obscureKey.value,
                decoration: InputDecoration(
                  labelText: 'Gemini API Key (optional)',
                  hintText: 'Get free key at aistudio.google.com',
                  prefixIcon: const Icon(Icons.key_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(obscureKey.value
                        ? Icons.visibility
                        : Icons.visibility_off),
                    onPressed: () => obscureKey.value = !obscureKey.value,
                  ),
                ),
                onChanged: s.updateGeminiKey,
              )),
          const Padding(
            padding: EdgeInsets.only(top: 4, bottom: 16),
            child: Text(
              'Free quota: 15 req/min · 1M tokens/day',
              style: TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ),

          const Divider(),
          // ── On-device Model ───────────────────────────────────
          _header('On-device Model'),
          ListTile(
            leading: const Icon(Icons.memory_rounded, color: Colors.indigo),
            title: const Text('Model File'),
            subtitle: Obx(() => Text(
              s.useOfflineMode.value ? 'Configured' : 'Not configured',
              style: TextStyle(
                  color: s.useOfflineMode.value ? Colors.green : Colors.grey),
            )),
            trailing: OutlinedButton(
              onPressed: () => Get.to(() => const ModelSetupScreen()),
              child: const Text('Manage'),
            ),
          ),

          const Divider(),
          // ── Chat Behaviour ────────────────────────────────────
          _header('Chat Behaviour'),
          Obx(() => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Context Window: ${s.contextWindow.value} messages',
                    style: const TextStyle(fontSize: 13),
                  ),
                  Slider(
                    value: s.contextWindow.value.toDouble(),
                    min: 4,
                    max: 20,
                    divisions: 16,
                    label: '${s.contextWindow.value}',
                    onChanged: (v) => s.updateContextWindow(v.toInt()),
                  ),
                ],
              )),
          Obx(() => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Streaming Speed: ${s.streamDelayMs.value}ms delay',
                    style: const TextStyle(fontSize: 13),
                  ),
                  Slider(
                    value: s.streamDelayMs.value.toDouble(),
                    min: 0,
                    max: 50,
                    divisions: 10,
                    label: '${s.streamDelayMs.value}ms',
                    onChanged: (v) => s.updateStreamDelay(v.toInt()),
                  ),
                  const Text(
                    '0ms = fastest · 50ms = smoother appearance',
                    style: TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              )),

          const Divider(),
          // ── Appearance ────────────────────────────────────────
          _header('Appearance'),
          Obx(() => SwitchListTile(
                title: const Text('Dark Mode'),
                value: s.isDarkMode.value,
                onChanged: (_) => s.toggleDarkMode(),
              )),
          const ListTile(
            title: Text('App Version'),
            subtitle: Text('2.0.0 (Selective Inference Edition)'),
          ),
        ],
      ),
    );
  }

  Widget _header(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
        child: Text(title.toUpperCase(),
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo)),
      );
}
