import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../core/services/settings_service.dart';
import '../bindings/model_manager_binding.dart';
import 'package:path_provider/path_provider.dart';
import '../../domain/services/on_device_inference_service.dart';
import '../../data/source_document.dart';
import '../../data/document_chunk.dart';
import '../../objectbox.g.dart';
import 'model_manager_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final SettingsService s = Get.find<SettingsService>();

  late TextEditingController ollamaIpCtrl;
  late TextEditingController ollamaPortCtrl;

  final RxString connectionResult = ''.obs;

  @override
  void initState() {
    super.initState();
    ollamaIpCtrl = TextEditingController(text: s.ollamaIp.value);
    ollamaPortCtrl = TextEditingController(text: s.ollamaPort.value);
  }

  @override
  void dispose() {
    ollamaIpCtrl.dispose();
    ollamaPortCtrl.dispose();
    super.dispose();
  }

  void _unfocus() => FocusScope.of(context).unfocus();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Neural Config'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Get.back(),
        ),
      ),
      body: GestureDetector(
        onTap: _unfocus,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          children: [
            // const _SectionHeader(title: 'AI BACKEND'),
            // const SizedBox(height: 20),

            // _buildTextField(
            //   context: context,
            //   controller: ollamaIpCtrl,
            //   label: 'Ollama IP Address',
            //   hint: 'e.g. 192.168.1.100',
            //   icon: Icons.lan_rounded,
            //   onChanged: s.updateOllamaIp,
            // ),
            // const SizedBox(height: 16),
            // _buildTextField(
            //   context: context,
            //   controller: ollamaPortCtrl,
            //   label: 'Ollama Port',
            //   hint: 'e.g. 11434',
            //   icon: Icons.swap_horiz_rounded,
            //   onChanged: s.updateOllamaPort,
            // ),

            // const SizedBox(height: 20),
            // _buildConnectionTester(theme),

            // const SizedBox(height: 40),
            const _SectionHeader(title: 'LOCAL COMPUTE'),
            const SizedBox(height: 20),

            _buildModelManagerTile(theme),

            const SizedBox(height: 40),
            const _SectionHeader(title: 'PREFERENCES'),
            // const SizedBox(height: 20),

            // Obx(() => _buildToggle(
            //       context: context,
            //       title: 'Aetheric Glow',
            //       subtitle: 'Enhanced OLED dark mode',
            //       value: s.isDarkMode.value,
            //       onChanged: s.toggleDarkMode,
            //       icon: s.isDarkMode.value
            //           ? Icons.dark_mode_rounded
            //           : Icons.light_mode_rounded,
            //     )),

            const SizedBox(height: 24),
            Obx(() => _buildSlider(
                  context: context,
                  label: 'Context Buffer',
                  value: s.contextWindow.value.toDouble(),
                  onChanged: (v) => s.updateContextWindow(v.toInt()),
                )),

            const SizedBox(height: 40),
            const _SectionHeader(title: 'MAINTENANCE'),
            const SizedBox(height: 20),

            _buildActionTile(
              theme: theme,
              title: 'Clear Model Cache',
              subtitle: 'Delete all downloaded models',
              icon: Icons.delete_sweep_rounded,
              onTap: () => _confirmClearCache(context, 'Models', () async {
                await Get.find<OnDeviceInferenceService>().clearModelCache();
                Get.snackbar('Success', 'Model cache cleared');
              }),
            ),
            const SizedBox(height: 16),
            _buildActionTile(
              theme: theme,
              title: 'Clear Knowledge Base',
              subtitle: 'Reset all ingested documents',
              icon: Icons.auto_delete_rounded,
              onTap: () =>
                  _confirmClearCache(context, 'Knowledge Base', () async {
                final store = Get.find<Store>();
                store.box<SourceDocument>().removeAll();
                store.box<DocumentChunk>().removeAll();
                Get.snackbar('Success', 'Knowledge base cleared');
              }),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmClearCache(
      BuildContext context, String target, VoidCallback onConfirm) {
    Get.dialog(
      AlertDialog(
        title: Text('Clear $target?'),
        content: Text('This action cannot be undone. Are you sure?'),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
          TextButton(
              onPressed: () {
                Get.back();
                onConfirm();
              },
              child: const Text('Clear',
                  style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required ThemeData theme,
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.outline.withOpacity(0.5)),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.redAccent, size: 20),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.bold)),
                  Text(subtitle,
                      style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant
                              .withOpacity(0.6),
                          fontSize: 11)),
                ],
              ),
            ),
            const Icon(Icons.warning_amber_rounded,
                color: Colors.orange, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required BuildContext context,
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    Widget? suffix,
    required Function(String) onChanged,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.6),
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: theme.colorScheme.outline.withOpacity(0.5)),
          ),
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            onChanged: onChanged,
            style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
                  fontSize: 14),
              border: InputBorder.none,
              icon: Icon(icon, color: theme.colorScheme.primary, size: 18),
              suffixIcon: suffix,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConnectionTester(ThemeData theme) {
    return Obx(() => ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary.withOpacity(0.05),
            foregroundColor: theme.colorScheme.primary,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side:
                  BorderSide(color: theme.colorScheme.primary.withOpacity(0.2)),
            ),
            minimumSize: const Size.fromHeight(48),
          ),
          onPressed: () async {
            connectionResult.value = 'Testing...';
            try {
              final probeDio = Dio();
              await probeDio.get(
                'http://${s.ollamaIp.value}:${s.ollamaPort.value}/api/tags',
                options: Options(connectTimeout: const Duration(seconds: 2)),
              );
              connectionResult.value = '✅ Ollama Online';
            } catch (e) {
              connectionResult.value = '❌ Unreachable';
            }
          },
          child: Text(connectionResult.value.isEmpty
              ? 'Test Local Connectivity'
              : connectionResult.value),
        ));
  }

  Widget _buildModelManagerTile(ThemeData theme) {
    return InkWell(
      onTap: () => Get.to(() => const ModelManagerPage(),
          binding: ModelManagerBinding()),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.outline.withOpacity(0.5)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child:
                  Icon(Icons.memory_rounded, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Model Management',
                      style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.bold)),
                  Obx(() => Text(
                        s.selectedModelId.value.isNotEmpty
                            ? '${s.modelLabel} Selected'
                            : 'No local model active',
                        style: TextStyle(
                            color: s.selectedModelId.value.isNotEmpty
                                ? theme.colorScheme.primary
                                : theme.colorScheme.error,
                            fontSize: 12),
                      )),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.4)),
          ],
        ),
      ),
    );
  }

  Widget _buildToggle(
      {required BuildContext context,
      required String title,
      required String subtitle,
      required bool value,
      required Function(bool) onChanged,
      required IconData icon}) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.primary, size: 20),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.bold)),
                Text(subtitle,
                    style: TextStyle(
                        color:
                            theme.colorScheme.onSurfaceVariant.withOpacity(0.6),
                        fontSize: 11)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: theme.colorScheme.primary,
            activeTrackColor: theme.colorScheme.primary.withOpacity(0.2),
          ),
        ],
      ),
    );
  }

  Widget _buildSlider(
      {required BuildContext context,
      required String label,
      required double value,
      required Function(double) onChanged}) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label.toUpperCase(),
                style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant.withOpacity(0.6),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1)),
            Text('${value.toInt()} MSG',
                style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        Slider(
          value: value,
          min: 2,
          max: 20,
          activeColor: theme.colorScheme.primary,
          inactiveColor: theme.colorScheme.outline.withOpacity(0.2),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({Key? key, required this.title}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w900,
        color: theme.colorScheme.primary,
        letterSpacing: 1.5,
      ),
    );
  }
}
