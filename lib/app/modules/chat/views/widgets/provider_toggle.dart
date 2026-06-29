import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../core/models/ai_provider.dart';
import '../../controllers/chat_controller.dart';
import '../../../../core/services/api_provider_service.dart';
import '../../../../core/services/local_llm_service.dart';
import '../../../../core/theme/app_theme.dart';

class ProviderToggle extends StatelessWidget {
  const ProviderToggle({super.key});

  void _showProviderSheet(BuildContext context) {
    final apiService = Get.find<ApiProviderService>();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Select AI Provider',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            // ── OpenAI ──
            Obx(() => _ProviderTile(
                  provider: AiProvider.openai,
                  isSelected:
                      apiService.activeProvider.value == AiProvider.openai,
                  subtitle: 'gpt-4o-mini · Cloud',
                  icon: Icons.cloud_outlined,
                  statusText: apiService.openAiKey.value.isNotEmpty
                      ? 'Key configured'
                      : 'No key',
                  statusColor: apiService.openAiKey.value.isNotEmpty
                      ? AppColors.success
                      : AppColors.error,
                  onTap: () {
                    apiService.switchProvider(AiProvider.openai);
                    Get.back();
                  },
                )),
            // ── Groq ──
            Obx(() => _ProviderTile(
                  provider: AiProvider.groq,
                  isSelected:
                      apiService.activeProvider.value == AiProvider.groq,
                  subtitle: 'llama-3.3-70b · Cloud',
                  icon: Icons.bolt_outlined,
                  statusText: apiService.groqKey.value.isNotEmpty
                      ? 'Key configured'
                      : 'No key',
                  statusColor: apiService.groqKey.value.isNotEmpty
                      ? AppColors.success
                      : AppColors.error,
                  onTap: () {
                    apiService.switchProvider(AiProvider.groq);
                    Get.back();
                  },
                )),
            // ── Offline ──
            Obx(() {
              LocalLlmService? localLlm;
              try {
                localLlm = Get.find<LocalLlmService>();
              } catch (_) {}
              final isReady = localLlm?.isModelReady.value ?? false;
              return _ProviderTile(
                provider: AiProvider.offline,
                isSelected:
                    apiService.activeProvider.value == AiProvider.offline,
                subtitle: 'Llama 3.2 3B · On-device',
                icon: Icons.memory_outlined,
                statusText: isReady ? 'Model ready' : 'Not downloaded',
                statusColor: isReady ? AppColors.success : Colors.grey,
                tooltip: isReady
                    ? null
                    : 'Download model from Settings → AI Engine first',
                onTap: () {
                  if (!isReady) {
                    Get.back();
                    Get.snackbar(
                      'Offline model not ready',
                      'Download it from Settings → AI Engine.',
                      snackPosition: SnackPosition.BOTTOM,
                      duration: const Duration(seconds: 3),
                    );
                    return;
                  }
                  apiService.switchProvider(AiProvider.offline);
                  Get.back();
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<ChatController>();

    return Obx(() => TextButton.icon(
          icon: const Icon(Icons.swap_horiz, color: Colors.white),
          label: Text(
            controller.activeProviderName,
            style: const TextStyle(color: Colors.white),
          ),
          onPressed: () => _showProviderSheet(context),
        ));
  }
}

// ── Individual provider row in the bottom sheet ─────────────

class _ProviderTile extends StatelessWidget {
  final AiProvider provider;
  final bool isSelected;
  final String subtitle;
  final IconData icon;
  final String statusText;
  final Color statusColor;
  final String? tooltip;
  final VoidCallback onTap;

  const _ProviderTile({
    required this.provider,
    required this.isSelected,
    required this.subtitle,
    required this.icon,
    required this.statusText,
    required this.statusColor,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    Widget tile = ListTile(
      leading: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.grey.shade400,
            width: isSelected ? 2 : 1.5,
          ),
        ),
        child: isSelected
            ? Center(
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              )
            : null,
      ),
      title: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 6),
          Text(
            provider.displayName,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
      subtitle: Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
      trailing: Text(
        statusText,
        style: TextStyle(
          color: statusColor,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
    );

    if (tooltip != null) {
      tile = Tooltip(message: tooltip!, child: tile);
    }

    return tile;
  }
}
