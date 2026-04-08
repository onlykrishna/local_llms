import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/model_setup_controller.dart';

class ModelSetupScreen extends StatelessWidget {
  const ModelSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.put(ModelSetupController());
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Model Environment'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Get.back(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader('Active Neural Core'),
            const SizedBox(height: 12),
            Obx(() {
              if (ctrl.isModelReady.value) {
                return _ReadyCard(path: ctrl.modelPath.value, onDelete: ctrl.deleteModel);
              }
              return Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: theme.colorScheme.error.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
                    const SizedBox(width: 16),
                    const Text('OFFLINE ENGINE OFFLINE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
              );
            }),
            
            const SizedBox(height: 32),
            const _SectionHeader('Layer A — Automated Fetch'),
            const SizedBox(height: 12),

            // Model Selection Cards
            ...ctrl.availableModels.map((m) => Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.colorScheme.outline.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(m.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: theme.colorScheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                      child: Text(m.sizeLabel, style: TextStyle(fontSize: 10, color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Text(m.description, style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7), height: 1.4)),
                  const SizedBox(height: 16),
                  Obx(() {
                    final isDownloading = ctrl.isDownloading.value && ctrl.downloadingModelId.value == m.id;
                    if (isDownloading) {
                      return Column(children: [
                        LinearProgressIndicator(value: ctrl.downloadProgress.value),
                        const SizedBox(height: 8),
                        Row(children: [
                          Text('${ctrl.downloadedMB.value.toStringAsFixed(0)} MB / ${ctrl.totalMB.value.toStringAsFixed(0)} MB', style: const TextStyle(fontSize: 10)),
                          const Spacer(),
                          TextButton(onPressed: ctrl.cancelDownload, child: const Text('ABORT', style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold))),
                        ]),
                      ]);
                    }
                    return SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        icon: const Icon(Icons.cloud_download_rounded, size: 18),
                        label: const Text('FETCH & INSTALL'),
                        onPressed: ctrl.isDownloading.value ? null : () => ctrl.downloadModel(m),
                      ),
                    );
                  }),
                ],
              ),
            )),

            const SizedBox(height: 24),
            const _SectionHeader('Layer B — Selective Ingest'),
            const SizedBox(height: 12),
            _ActionButton(
              icon: Icons.folder_open_rounded,
              label: 'Ingest External .GGUF File',
              onPressed: ctrl.pickLocalModel,
              color: theme.colorScheme.primary,
              isGhost: true,
            ),
            const SizedBox(height: 120),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      title.toUpperCase(),
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurfaceVariant.withOpacity(0.6), letterSpacing: 1.5),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color color;
  final bool isGhost;

  const _ActionButton({required this.icon, required this.label, required this.onPressed, required this.color, this.isGhost = false});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 52,
        width: double.infinity,
        decoration: BoxDecoration(
          color: isGhost ? Colors.transparent : color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

class _ReadyCard extends StatelessWidget {
  final String path;
  final VoidCallback onDelete;
  const _ReadyCard({required this.path, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF00E475).withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00E475).withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: Color(0xFF00E475), size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('NEURAL CORE READY', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF00E475), fontSize: 10, letterSpacing: 1)),
              Text(path.split('/').last, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface)),
            ]),
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded, color: Color(0xFFFFB4AB)),
            onPressed: () {
              Get.defaultDialog(
                backgroundColor: theme.colorScheme.surface,
                title: 'PURGE CORE?',
                titleStyle: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.bold),
                middleText: 'Storage reclamation: ~0.7-2.3 GB.',
                middleTextStyle: TextStyle(color: theme.colorScheme.onSurface),
                confirmTextColor: Colors.white,
                textConfirm: 'PURGE',
                textCancel: 'RETAIN',
                buttonColor: theme.colorScheme.error,
                onConfirm: () {
                  onDelete();
                  Get.back();
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
