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
            // Premium Info card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [theme.colorScheme.primary, theme.colorScheme.primary.withOpacity(0.6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: theme.colorScheme.primary.withOpacity(0.1), blurRadius: 20, spreadRadius: 2)
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Llama 3.2 1B IQ4_XS', style: TextStyle(
                    color: theme.colorScheme.onPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('~743 MB · Apache 2.0 · Ultra-compressed',
                      style: TextStyle(color: theme.colorScheme.onPrimary.withOpacity(0.7), fontSize: 12)),
                  const SizedBox(height: 12),
                  Text('Optimized for current hardware. High-speed local inference with zero data leakage.',
                      style: TextStyle(color: theme.colorScheme.onPrimary.withOpacity(0.6), fontSize: 11, height: 1.4)),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Model status
            Obx(() {
              if (ctrl.isModelReady.value) {
                return _ReadyCard(path: ctrl.modelPath.value, onDelete: ctrl.deleteModel);
              }
              return const SizedBox.shrink();
            }),

            // Option A: Auto-download
            const _SectionHeader('Layer A — Automated Fetch'),
            const SizedBox(height: 12),
            Obx(() {
              if (ctrl.isDownloading.value) {
                return _DownloadProgress(
                  progress: ctrl.downloadProgress.value,
                  downloadedMB: ctrl.downloadedMB.value,
                  totalMB: ctrl.totalMB.value,
                  onCancel: ctrl.cancelDownload,
                );
              }
              return _ActionButton(
                icon: Icons.cloud_download_rounded,
                label: 'Fetch from HuggingFace (~743 MB)',
                onPressed: ctrl.downloadModel,
                color: theme.colorScheme.primary,
              );
            }),
            const SizedBox(height: 24),

            // Option B: Manual pick
            const _SectionHeader('Layer B — Selective Ingest'),
            const SizedBox(height: 12),
            _ActionButton(
              icon: Icons.folder_open_rounded,
              label: 'Ingest Local .GGUF File',
              onPressed: ctrl.pickLocalModel,
              color: theme.colorScheme.primary,
              isGhost: true,
            ),
            const SizedBox(height: 24),

            // Option C: ADB
            const _SectionHeader('Layer C — Terminal Injection'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.colorScheme.outline.withOpacity(0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ADB BRIDGE:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurfaceVariant.withOpacity(0.6))),
                  const SizedBox(height: 8),
                  SelectableText(
                    'adb push your-model.gguf /sdcard/Android/data/com.example.offline_ai_flutter_demo/files/llama-3.2-1b-iq4_xs.gguf',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: theme.colorScheme.primary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),

            // Start chatting
            Obx(() => ctrl.isModelReady.value
                ? _ActionButton(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: 'Initialize Neural Session',
                    color: const Color(0xFF00E475),
                    onPressed: () => Get.back(),
                  )
                : const SizedBox.shrink()),
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

class _DownloadProgress extends StatelessWidget {
  final double progress;
  final double downloadedMB;
  final double totalMB;
  final VoidCallback onCancel;
  const _DownloadProgress({required this.progress, required this.downloadedMB, required this.totalMB, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(
            value: progress,
            backgroundColor: theme.colorScheme.outline.withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Text('${downloadedMB.toStringAsFixed(0)} MB / ${totalMB.toStringAsFixed(0)} MB', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface)),
            const Spacer(),
            TextButton(onPressed: onCancel, child: const Text('ABORT', style: TextStyle(color: Color(0xFFFFB4AB), fontWeight: FontWeight.bold, fontSize: 11))),
          ]),
        ],
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
      margin: const EdgeInsets.only(bottom: 24),
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
                middleText: 'Storage reclamation: 743 MB.',
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
