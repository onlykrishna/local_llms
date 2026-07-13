import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/services/live_scan_service.dart';

import '../../../../app/core/theme/app_theme.dart';
import '../controllers/live_scan_controller.dart';
import 'widgets/scan_overlay_painter.dart';
import 'widgets/scan_controls_bar.dart';

class LiveScanScreen extends GetView<LiveScanController> {
  const LiveScanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Obx(() => Text(
          controller.scanMode.value == 'ocr' ? 'OCR Text Scanner' : 'Object Detection',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        )),
        actions: [
          Obx(() => controller.isFrozen.value
              ? TextButton.icon(
                  icon: Icon(Icons.play_arrow_rounded, color: AppColors.success, size: 18),
                  label: Text('Resume',
                      style: TextStyle(color: AppColors.success, fontSize: 12)),
                  onPressed: controller.resumeScan,
                )
              : IconButton(
                  icon: const Icon(Icons.camera_alt_rounded),
                  tooltip: 'Freeze Frame',
                  onPressed: controller.captureSnapshot,
                )),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Mode Switcher ────────────────────────────────────────────────
            _ModeSwitcher(theme: theme),

            // ── Camera Preview ───────────────────────────────────────────────
            Expanded(
              flex: 5,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _CameraPreviewCard(theme: theme),
              ),
            ),

            const SizedBox(height: 6),

            // ── Camera Controls ──────────────────────────────────────────────
            Obx(() {
              if (!controller.isCameraInitialized.value) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: const ScanControlsBar(),
              );
            }),

            const SizedBox(height: 6),

            // ── Results Panel ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Obx(() => Icon(
                    controller.scanMode.value == 'ocr'
                        ? Icons.text_fields_rounded
                        : Icons.category_rounded,
                    size: 14,
                    color: AppColors.primary,
                  )),
                  const SizedBox(width: 6),
                  Obx(() => Text(
                    controller.scanMode.value == 'ocr' ? 'DETECTED TEXT' : 'DETECTED OBJECTS',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )),
                  const Spacer(),
                  // Export buttons (OCR only)
                  Obx(() {
                    if (controller.scanMode.value != 'ocr') return const SizedBox.shrink();
                    if (controller.detectedTexts.isEmpty) return const SizedBox.shrink();
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ExportButton(
                          icon: Icons.copy_rounded,
                          label: 'Copy All',
                          onTap: controller.copyAllOcrText,
                          theme: theme,
                        ),
                        const SizedBox(width: 6),
                        _ExportButton(
                          icon: Icons.share_rounded,
                          label: 'Share',
                          onTap: () {
                            final text = controller.detectedTexts.join('\n');
                            if (text.isNotEmpty) Share.share(text, subject: 'OCR Scan Result');
                          },
                          theme: theme,
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ),

            const SizedBox(height: 4),

            Expanded(
              flex: 3,
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.dividerColor, width: 0.5),
                ),
                child: Obx(() {
                  final scanMode = controller.scanMode.value;
                  final detectedTexts = controller.detectedTexts.toList();
                  final detectedObjects = controller.detectedObjects.toList();
                  final isFrozen = controller.isFrozen.value;
                  return _ResultsPanel(
                    theme: theme,
                    controller: controller,
                    scanMode: scanMode,
                    detectedTexts: detectedTexts,
                    detectedObjects: detectedObjects,
                    isFrozen: isFrozen,
                  );
                }),
              ),
            ),

            // ── Done Button ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check_rounded, color: Colors.white),
                label: const Text('Done',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  Get.back();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Camera Preview Card ───────────────────────────────────────────────────────
// Separate StatelessWidget so it can contain the Obx watchers close to their
// reactive data, avoiding unnecessary rebuilds of the outer Scaffold.

class _CameraPreviewCard extends StatelessWidget {
  final ThemeData theme;
  const _CameraPreviewCard({required this.theme});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<LiveScanController>();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primary.withAlpha(60),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withAlpha(20),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Obx(() => _buildContent(context, controller)),
      ),
    );
  }

  Widget _buildContent(BuildContext context, LiveScanController controller) {
    // ── Permission denied ─────────────────────────────────────────────────
    if (controller.isPermissionDenied.value) {
      return _Placeholder(
        icon: Icons.videocam_off_rounded,
        title: 'Camera Permission Required',
        subtitle: 'Enable camera access in Settings.',
        action: TextButton(
          onPressed: openAppSettings,
          child: const Text('Open Settings'),
        ),
      );
    }

    // ── ML model loading ──────────────────────────────────────────────────
    final status = controller.initStatus.value;
    if (status == 'idle' || status == 'loading') {
      return const _Placeholder(
        icon: Icons.model_training_rounded,
        title: 'Loading ML Model…',
        subtitle: 'Copying TFLite model (first launch only)',
        showSpinner: true,
      );
    }

    // ── ML model error ────────────────────────────────────────────────────
    if (status == 'error') {
      return _Placeholder(
        icon: Icons.error_outline_rounded,
        title: 'Model Load Failed',
        subtitle: 'Could not initialize detector.',
        action: TextButton.icon(
          icon: const Icon(Icons.refresh_rounded, size: 14),
          label: const Text('Retry'),
          onPressed: controller.retryInitialization,
        ),
      );
    }

    // ── Camera initializing ───────────────────────────────────────────────
    if (!controller.isCameraInitialized.value || controller.cameraController == null) {
      return const _Placeholder(
        icon: Icons.camera_alt_rounded,
        title: 'Starting Camera…',
        subtitle: '',
        showSpinner: true,
      );
    }

    // ── Live Camera Preview ───────────────────────────────────────────────
    // FIX: Use AspectRatio to prevent stretching. CameraPreview must be sized
    // to match its native sensor aspect ratio; StackFit.expand distorts it.
    final cc = controller.cameraController!;
    return Stack(
      alignment: Alignment.center,
      children: [
        // Black background fills the card while the preview letterboxes
        const ColoredBox(color: Color(0xFF0A0A0A), child: SizedBox.expand()),

        // AspectRatio prevents distortion
        Center(
          child: AspectRatio(
            aspectRatio: 1 / cc.value.aspectRatio,
            child: CameraPreview(cc),
          ),
        ),

        // Bounding-box overlay — must be same size as the CameraPreview widget
        Obx(() {
          final imgSize = controller.absoluteImageSize.value;
          final rotation = controller.imageRotation.value;
          final scanMode = controller.scanMode.value;
          final detectedObjects = controller.detectedObjects.toList();
          final ocrResult = controller.lastOcrResult.value;
          if (imgSize == null || rotation == null) return const SizedBox.shrink();

          return LayoutBuilder(builder: (_, constraints) {
            // The preview occupies AspectRatio space inside this Stack.
            // Compute preview rect to correctly position the overlay.
            // Safe aspect ratio extraction to prevent division by zero or stretching.
            final rawAspect = cc.value.aspectRatio;
            final previewAspect = (rawAspect > 0.1 && rawAspect < 10.0)
                ? (rawAspect > 1.0 ? 1.0 / rawAspect : rawAspect)
                : 0.5625;
            final cardW = constraints.maxWidth;
            final cardH = constraints.maxHeight;
            double pw, ph;
            if (cardW / cardH > previewAspect) {
              ph = cardH;
              pw = cardH * previewAspect;
            } else {
              pw = cardW;
              ph = cardW / previewAspect;
            }

            return SizedBox(
              width: pw,
              height: ph,
              child: CustomPaint(
                painter: ScanOverlayPainter(
                  viewSize: Size(pw, ph),
                  absoluteImageSize: imgSize,
                  rotation: rotation,
                  isOcrMode: scanMode == 'ocr',
                  detectedObjects: detectedObjects,
                  ocrResult: ocrResult,
                ),
              ),
            );
          });
        }),

        // Freeze badge
        if (controller.isFrozen.value)
          Positioned(
            top: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withAlpha(220),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.pause_rounded, size: 11, color: Colors.white),
                  SizedBox(width: 4),
                  Text('PAUSED',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5)),
                ],
              ),
            ),
          ),

        // Scanning laser
        if (!controller.isFrozen.value) const _ScanningIndicator(),
      ],
    );
  }
}

// ── Mode Switcher ─────────────────────────────────────────────────────────────

class _ModeSwitcher extends StatelessWidget {
  final ThemeData theme;
  const _ModeSwitcher({required this.theme});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<LiveScanController>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Obx(() {
        final currentMode = controller.scanMode.value;
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.dividerColor, width: 0.5),
          ),
          padding: const EdgeInsets.all(3),
          child: Row(
            children: [
              Expanded(child: _Pill(
                mode: 'ocr',
                label: 'OCR Text',
                icon: Icons.text_fields_rounded,
                theme: theme,
                active: currentMode == 'ocr',
                onTap: () => controller.toggleScanMode('ocr'),
              )),
              Expanded(child: _Pill(
                mode: 'object',
                label: 'Object Detect',
                icon: Icons.category_rounded,
                theme: theme,
                active: currentMode == 'object',
                onTap: () => controller.toggleScanMode('object'),
              )),
            ],
          ),
        );
      }),
    );
  }
}

class _Pill extends StatelessWidget {
  final String mode;
  final String label;
  final IconData icon;
  final ThemeData theme;
  final bool active;
  final VoidCallback onTap;

  const _Pill({
    required this.mode,
    required this.label,
    required this.icon,
    required this.theme,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 14,
                color: active ? Colors.white : theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 5),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: active ? Colors.white : theme.colorScheme.onSurfaceVariant,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Results Panel ─────────────────────────────────────────────────────────────

class _ResultsPanel extends StatelessWidget {
  final ThemeData theme;
  final LiveScanController controller;
  final String scanMode;
  final List<String> detectedTexts;
  final List<DetectedObject> detectedObjects;
  final bool isFrozen;

  const _ResultsPanel({
    required this.theme,
    required this.controller,
    required this.scanMode,
    required this.detectedTexts,
    required this.detectedObjects,
    required this.isFrozen,
  });

  @override
  Widget build(BuildContext context) {
    final isOcr = scanMode == 'ocr';

    if (isOcr) {
      if (detectedTexts.isEmpty) {
        return _EmptyHint(
          icon: Icons.document_scanner_outlined,
          message: isFrozen
              ? 'No text detected in this frame.'
              : 'Point camera at text, then tap 📷 to capture.',
        );
      }

      return ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        itemCount: detectedTexts.length,
        separatorBuilder: (_, _) => Divider(height: 1, color: theme.dividerColor),
        itemBuilder: (context, i) {
          final text = detectedTexts[i];
          return ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
            leading: CircleAvatar(
              radius: 13,
              backgroundColor: AppColors.primary.withAlpha(25),
              child: Icon(Icons.text_fields_rounded, color: AppColors.primary, size: 13),
            ),
            title: Text(text,
                style: theme.textTheme.bodyMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              icon: Icon(Icons.add_circle_outline_rounded,
                  color: AppColors.primary, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'Add to chat',
              onPressed: () => controller.selectItem(text),
            ),
            onTap: () => controller.selectItem(text),
          );
        },
      );
    }

    // Object Detection
    if (detectedObjects.isEmpty) {
      return _EmptyHint(
        icon: Icons.find_in_page_outlined,
        message: isFrozen
            ? 'No objects detected. Try lowering confidence threshold.'
            : 'Scanning for objects in frame…',
      );
    }

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: detectedObjects.map((obj) {
          final labelsList = obj.labels;
          final hasLabels = labelsList.isNotEmpty;
          final labelText = hasLabels ? labelsList.first.text : 'Object';
          final conf = hasLabels
              ? (labelsList.first.confidence * 100).toStringAsFixed(0)
              : '?';
          return ActionChip(
            avatar: Icon(Icons.category_outlined, size: 13, color: AppColors.primary),
            label: Text('$labelText · $conf%',
                style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600)),
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            side: BorderSide(color: AppColors.primary.withAlpha(60), width: 0.5),
            shape: const StadiumBorder(),
            onPressed: () => controller.selectItem(labelText),
          );
        }).toList(),
      ),
    );
  }
}

// ── Placeholder ───────────────────────────────────────────────────────────────

class _Placeholder extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;
  final bool showSpinner;

  const _Placeholder({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
    this.showSpinner = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1A1A2E),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showSpinner)
                const SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: AppColors.primary),
                )
              else
                Icon(icon, size: 42, color: Colors.white38),
              const SizedBox(height: 12),
              Text(title,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  textAlign: TextAlign.center),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(subtitle,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                    textAlign: TextAlign.center),
              ],
              if (action != null) ...[
                const SizedBox(height: 14),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Empty Hint ────────────────────────────────────────────────────────────────

class _EmptyHint extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyHint({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(message,
                style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 12,
                    fontStyle: FontStyle.italic),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

// ── Export Button ─────────────────────────────────────────────────────────────

class _ExportButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final ThemeData theme;

  const _ExportButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.primary.withAlpha(18),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.primary.withAlpha(60), width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: AppColors.primary),
            const SizedBox(width: 3),
            Text(label,
                style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ── Scanning Laser ────────────────────────────────────────────────────────────

class _ScanningIndicator extends StatefulWidget {
  const _ScanningIndicator();

  @override
  State<_ScanningIndicator> createState() => _ScanningIndicatorState();
}

class _ScanningIndicatorState extends State<_ScanningIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _t;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2500))
      ..repeat(reverse: true);
    _t = CurvedAnimation(parent: _anim, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LayoutBuilder(builder: (_, constraints) {
        final h = constraints.maxHeight;
        return AnimatedBuilder(
          animation: _t,
          builder: (_, _) => Stack(
            children: [
              Positioned(
                top: _t.value * (h - 3),
                left: 0,
                right: 0,
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      Colors.transparent,
                      AppColors.primary,
                      Colors.transparent,
                    ]),
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.primary.withAlpha(120),
                          blurRadius: 6,
                          spreadRadius: 2),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
