import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/model_setup_controller.dart';

class ModelSetupScreen extends StatelessWidget {
  const ModelSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.put(ModelSetupController());

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Model Setup'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  Colors.deepPurple.shade900,
                  Colors.indigo.shade800,
                ]),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Llama 3.2 1B Instruct', style: TextStyle(
                    color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text('~650 MB · Apache 2.0 · No login required',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                  SizedBox(height: 8),
                  Text('128K context · CPU-optimised · 100+ tok/sec on mobile',
                      style: TextStyle(color: Colors.white60, fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Model status
            Obx(() {
              if (ctrl.isModelReady.value) {
                return _ReadyCard(path: ctrl.modelPath.value, onDelete: ctrl.deleteModel);
              }
              return const SizedBox.shrink();
            }),

            // Option A: Auto-download
            _SectionHeader('Option A — Auto Download (HuggingFace)'),
            Obx(() {
              if (ctrl.isDownloading.value) {
                return _DownloadProgress(
                  progress: ctrl.downloadProgress.value,
                  downloadedMB: ctrl.downloadedMB.value,
                  totalMB: ctrl.totalMB.value,
                  onCancel: ctrl.cancelDownload,
                );
              }
              return ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: Colors.indigo,
                ),
                icon: const Icon(Icons.cloud_download_rounded, color: Colors.white),
                label: const Text('Download Llama 3.2 1B (~650 MB)',
                    style: TextStyle(color: Colors.white)),
                onPressed: ctrl.downloadModel,
              );
            }),
            const SizedBox(height: 16),

            // Option B: Manual pick
            _SectionHeader('Option B — Pick Local File'),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('Browse & Select .gguf File'),
              onPressed: ctrl.pickLocalModel,
            ),
            const SizedBox(height: 16),

            // Option C: ADB
            _SectionHeader('Option C — ADB Push (Power Users)'),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Run on your PC:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  SizedBox(height: 4),
                  SelectableText(
                    'adb push your-model.gguf '
                    '/sdcard/Android/data/com.example.offline_ai_flutter_demo/files/llama-3.2-1b-q4.gguf',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 10),
                  ),
                  SizedBox(height: 8),
                  Text('The app will auto-detect and migrate it on next launch.',
                      style: TextStyle(fontSize: 11, color: Colors.teal)),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Start chatting
            Obx(() => ctrl.isModelReady.value
                ? ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor: Colors.teal,
                    ),
                    icon: const Icon(Icons.chat_rounded, color: Colors.white),
                    label: const Text('Start Chatting',
                        style: TextStyle(color: Colors.white, fontSize: 16)),
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
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title.toUpperCase(),
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo)),
      );
}

class _DownloadProgress extends StatelessWidget {
  final double progress;
  final double downloadedMB;
  final double totalMB;
  final VoidCallback onCancel;
  const _DownloadProgress(
      {required this.progress, required this.downloadedMB, required this.totalMB, required this.onCancel});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Text('${downloadedMB.toStringAsFixed(0)} MB / ${totalMB.toStringAsFixed(0)} MB',
                style: const TextStyle(fontSize: 12)),
            const Spacer(),
            TextButton(onPressed: onCancel, child: const Text('Cancel')),
          ]),
        ],
      );
}

class _ReadyCard extends StatelessWidget {
  final String path;
  final VoidCallback onDelete;
  const _ReadyCard({required this.path, required this.onDelete});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.teal.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.teal.shade300),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.teal),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Model Ready', style: TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.teal)),
                Text(path.split('/').last,
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ]),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: () {
                Get.defaultDialog(
                  title: 'Delete Model?',
                  middleText: 'This will remove the 650 MB file from storage.',
                  onConfirm: () {
                    onDelete();
                    Get.back();
                  },
                  onCancel: () {},
                );
              },
            ),
          ],
        ),
      );
}
