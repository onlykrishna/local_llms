import 'dart:ui';
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

// ═══════════════════════════════════════════════════════════════════════════════
// Live Scan Screen
// ═══════════════════════════════════════════════════════════════════════════════

class LiveScanScreen extends GetView<LiveScanController> {
  const LiveScanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            // Full screen camera
            _FullScreenCamera(),

            // Top overlay — AppBar area
            _TopBar(),

            // Bottom overlay — mode + results
            _BottomSheet(),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Full-Screen Camera Preview
// ═══════════════════════════════════════════════════════════════════════════════

class _FullScreenCamera extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final controller = Get.find<LiveScanController>();

    return Positioned.fill(
      child: Obx(() => _buildCameraContent(context, controller)),
    );
  }

  Widget _buildCameraContent(BuildContext context, LiveScanController controller) {
    if (controller.isPermissionDenied.value) {
      return _PermissionDeniedScreen();
    }

    final status = controller.initStatus.value;
    if (status == 'idle' || status == 'loading') {
      return _LoadingScreen(
        message: 'Loading AI Models…',
        subtitle: 'Preparing detection engine',
      );
    }
    if (status == 'error') {
      return _ErrorScreen(onRetry: controller.retryInitialization);
    }

    if (!controller.isCameraInitialized.value || controller.cameraController == null) {
      return _LoadingScreen(message: 'Starting Camera…', subtitle: '');
    }

    // Both OCR and Object Detection use the same CameraPreview.
    // flutter_vision runs YOLO inference directly on the image stream.
    final cc = controller.cameraController!;
    return Stack(
      fit: StackFit.expand,
      children: [
        FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: cc.value.previewSize?.height ?? 1,
            height: cc.value.previewSize?.width ?? 1,
            child: CameraPreview(cc),
          ),
        ),

        // Unified bounding-box overlay (handles both OCR and Object modes)
        Obx(() {
          final imgSize = controller.absoluteImageSize.value;
          final rotation = controller.imageRotation.value;
          final scanMode = controller.scanMode.value;
          final detectedObjects = controller.detectedObjects.toList();
          final ocrResult = controller.lastOcrResult.value;
          if (imgSize == null || rotation == null) return const SizedBox.shrink();

          return CustomPaint(
            painter: ScanOverlayPainter(
              viewSize: MediaQuery.of(context).size,
              absoluteImageSize: imgSize,
              previewSize: Size(
                cc.value.previewSize?.height ?? 1.0,
                cc.value.previewSize?.width ?? 1.0,
              ),
              rotation: rotation,
              isOcrMode: scanMode == 'ocr',
              detectedObjects: detectedObjects,
              ocrResult: ocrResult,
            ),
            child: const SizedBox.expand(),
          );
        }),

        // Scan animation
        Obx(() => controller.isFrozen.value
            ? const SizedBox.shrink()
            : const _ScannerAnimation()),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Top Bar Overlay
// ═══════════════════════════════════════════════════════════════════════════════

class _TopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final controller = Get.find<LiveScanController>();

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withAlpha(180),
                  Colors.black.withAlpha(80),
                  Colors.transparent,
                ],
              ),
            ),
            child: Row(
              children: [
                // Back button
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_rounded,
                      color: Colors.white, size: 20),
                  onPressed: () => Get.back(),
                ),

                const Spacer(),

                // Status indicator
                Obx(() {
                  final isFrozen = controller.isFrozen.value;
                  final mode = controller.scanMode.value;
                  final count = mode == 'ocr'
                      ? controller.detectedTexts.length
                      : controller.detectedObjects.length;
                  return _StatusBadge(isFrozen: isFrozen, mode: mode, count: count);
                }),

                const Spacer(),

                // Freeze / Resume button
                Obx(() => controller.isFrozen.value
                    ? TextButton.icon(
                        icon: const Icon(Icons.play_arrow_rounded,
                            color: Color(0xFF10B981), size: 20),
                        label: const Text('Resume',
                            style: TextStyle(
                                color: Color(0xFF10B981),
                                fontWeight: FontWeight.bold)),
                        onPressed: controller.resumeScan,
                      )
                    : IconButton(
                        icon: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Center(
                            child: Icon(Icons.camera_alt_rounded,
                                color: Colors.white, size: 16),
                          ),
                        ),
                        tooltip: 'Capture & Freeze',
                        onPressed: controller.captureSnapshot,
                      )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Status Badge ──────────────────────────────────────────────────────────────

class _StatusBadge extends StatefulWidget {
  final bool isFrozen;
  final String mode;
  final int count;
  const _StatusBadge({
    required this.isFrozen,
    required this.mode,
    required this.count,
  });

  @override
  State<_StatusBadge> createState() => _StatusBadgeState();
}

class _StatusBadgeState extends State<_StatusBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isOcr = widget.mode == 'ocr';
    final color = widget.isFrozen
        ? Colors.orange
        : isOcr
            ? const Color(0xFF10B981)
            : const Color(0xFF6C63FF);
    final label = widget.isFrozen
        ? 'PAUSED'
        : isOcr
            ? 'OCR LIVE'
            : 'DETECT LIVE';

    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, child) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(140),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: color.withAlpha(widget.isFrozen ? 200 : (100 + (_pulse.value * 100).round())),
            width: 1.2,
          ),
        ),
        child: child,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
          if (widget.count > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: color.withAlpha(200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${widget.count}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Bottom Sheet Overlay
// ═══════════════════════════════════════════════════════════════════════════════

class _BottomSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final controller = Get.find<LiveScanController>();
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Positioned.fill(
      child: DraggableScrollableSheet(
        initialChildSize: 0.45,
        minChildSize: 0.15,
        maxChildSize: 0.9,
        snap: false,
        builder: (context, scrollController) {
          return ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(210),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  border: Border(
                    top: BorderSide(color: Colors.white.withAlpha(25), width: 0.8),
                  ),
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: CustomScrollView(
                        controller: scrollController,
                        slivers: [
                          // Handle
                          SliverToBoxAdapter(
                            child: Center(
                              child: Container(
                                width: 36,
                                height: 4,
                                margin: const EdgeInsets.only(top: 10, bottom: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withAlpha(60),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),

                          // Mode switcher
                          SliverToBoxAdapter(
                            child: _ModeSwitcher(),
                          ),

                          const SliverToBoxAdapter(child: SizedBox(height: 8)),

                          // Controls bar (only when camera ready)
                          SliverToBoxAdapter(
                            child: Obx(() {
                              if (!controller.isCameraInitialized.value) return const SizedBox.shrink();
                              return const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 16),
                                child: ScanControlsBar(),
                              );
                            }),
                          ),

                          const SliverToBoxAdapter(child: SizedBox(height: 8)),

                          // Results section (returns a sliver)
                          _ResultsSection(scrollController: scrollController),
                        ],
                      ),
                    ),

                    // Done button (persistent pinned footer)
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + bottomPad),
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: const Text(
                            'Done',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                          onPressed: () {
                            HapticFeedback.mediumImpact();
                            Get.back();
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Mode Switcher
// ═══════════════════════════════════════════════════════════════════════════════

class _ModeSwitcher extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final controller = Get.find<LiveScanController>();

    return Obx(() {
      final mode = controller.scanMode.value;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withAlpha(20), width: 0.8),
          ),
          child: Row(
            children: [
              Expanded(
                child: _ModeButton(
                  icon: Icons.text_fields_rounded,
                  label: 'Text Scanner',
                  isActive: mode == 'ocr',
                  color: const Color(0xFF10B981),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    controller.toggleScanMode('ocr');
                  },
                ),
              ),
              Container(width: 0.8, height: 24, color: Colors.white.withAlpha(20)),
              Expanded(
                child: _ModeButton(
                  icon: Icons.search_rounded,
                  label: 'Object Detect',
                  isActive: mode == 'object',
                  color: const Color(0xFF6C63FF),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    controller.toggleScanMode('object');
                  },
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

class _ModeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final Color color;
  final VoidCallback onTap;

  const _ModeButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: double.infinity,
        decoration: BoxDecoration(
          color: isActive ? color.withAlpha(40) : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: isActive ? color : Colors.white54),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: isActive ? color : Colors.white54,
                fontSize: 12,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Results Section
// ═══════════════════════════════════════════════════════════════════════════════

class _ResultsSection extends StatelessWidget {
  final ScrollController scrollController;
  const _ResultsSection({required this.scrollController});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<LiveScanController>();

    return Obx(() {
      final mode = controller.scanMode.value;
      final texts = controller.detectedTexts.toList();
      final objects = controller.detectedObjects.toList();
      final isFrozen = controller.isFrozen.value;

      // Results header row
      Widget header = Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: Row(
          children: [
            Icon(
              mode == 'ocr' ? Icons.text_fields_rounded : Icons.category_rounded,
              size: 13,
              color: mode == 'ocr' ? const Color(0xFF10B981) : const Color(0xFF6C63FF),
            ),
            const SizedBox(width: 6),
            Text(
              mode == 'ocr' ? 'DETECTED TEXT' : 'DETECTED OBJECTS',
              style: TextStyle(
                color: Colors.white.withAlpha(150),
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
            const Spacer(),
            // OCR export buttons
            if (mode == 'ocr' && texts.isNotEmpty) ...[
              _SmallButton(
                icon: Icons.copy_rounded,
                label: 'Copy All',
                onTap: controller.copyAllOcrText,
                color: const Color(0xFF10B981),
              ),
              const SizedBox(width: 6),
              _SmallButton(
                icon: Icons.share_rounded,
                label: 'Share',
                onTap: () {
                  final text = controller.detectedTexts.join('\n');
                  if (text.isNotEmpty) Share.share(text, subject: 'OCR Result');
                },
                color: const Color(0xFF10B981),
              ),
            ],
          ],
        ),
      );

      final int itemCount = mode == 'ocr'
          ? (texts.isEmpty ? 2 : 1 + texts.length)
          : (objects.isEmpty ? 2 : 1 + objects.length);

      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index == 0) {
              return header;
            }

            if (mode == 'ocr') {
              if (texts.isEmpty) {
                return _EmptyState(
                  scrollController: scrollController,
                  icon: Icons.document_scanner_outlined,
                  title: isFrozen ? 'No text found' : 'Scanning for text…',
                  subtitle: isFrozen
                      ? 'Try capturing a clearer frame'
                      : 'Point at text and tap 📷 to capture',
                );
              }
              final text = texts[index - 1];
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _OcrResultTile(
                    text: text,
                    onTap: () => controller.selectItem(text),
                  ),
                  Divider(height: 1, color: Colors.white.withAlpha(12)),
                ],
              );
            } else {
              if (objects.isEmpty) {
                return _EmptyState(
                  scrollController: scrollController,
                  icon: Icons.image_search_rounded,
                  title: isFrozen ? 'No objects detected' : 'Scanning for objects…',
                  subtitle: isFrozen
                      ? 'Lower confidence or try a different angle'
                      : 'Point camera at any object to detect it',
                );
              }
              final obj = objects[index - 1];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _ObjectResultTile(
                  obj: obj,
                  onTap: () {
                    final label = obj.labels.isNotEmpty
                        ? obj.labels.first.text
                        : 'Object';
                    controller.selectItem(label);
                  },
                ),
              );
            }
          },
          childCount: itemCount,
        ),
      );
    });
  }
}

// ── OCR Result Tile ───────────────────────────────────────────────────────────

class _OcrResultTile extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _OcrResultTile({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
      leading: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: const Color(0xFF10B981).withAlpha(30),
          borderRadius: BorderRadius.circular(7),
        ),
        child: const Icon(Icons.text_fields_rounded,
            color: Color(0xFF10B981), size: 14),
      ),
      title: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: GestureDetector(
        onTap: onTap,
        child: const Icon(Icons.add_circle_outline_rounded,
            color: Color(0xFF10B981), size: 20),
      ),
      onTap: onTap,
    );
  }
}

// ── Object Result Tile ────────────────────────────────────────────────────────

class _ObjectResultTile extends StatelessWidget {
  final DetectedObject obj;
  final VoidCallback onTap;
  const _ObjectResultTile({required this.obj, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final label = obj.labels.isNotEmpty ? obj.labels.first.text : 'Object';
    final conf = obj.labels.isNotEmpty ? obj.labels.first.confidence : 0.0;
    final pct = (conf * 100).toStringAsFixed(0);
    final barColor = conf >= 0.6
        ? const Color(0xFF10B981)
        : conf >= 0.4
            ? const Color(0xFFFFC107)
            : const Color(0xFFFF7675);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF6C63FF).withAlpha(20),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xFF6C63FF).withAlpha(50),
            width: 0.8,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF6C63FF).withAlpha(40),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.category_outlined,
                  color: Color(0xFF6C63FF), size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: conf,
                            minHeight: 4,
                            backgroundColor: Colors.white.withAlpha(18),
                            valueColor: AlwaysStoppedAnimation<Color>(barColor),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$pct%',
                        style: TextStyle(
                          color: barColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.add_circle_outline_rounded,
                color: Color(0xFF6C63FF), size: 20),
          ],
        ),
      ),
    );
  }
}

// ── Small Button ──────────────────────────────────────────────────────────────

class _SmallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  const _SmallButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withAlpha(25),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withAlpha(80), width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 10, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final ScrollController scrollController;
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 26, color: Colors.white24),
              const SizedBox(height: 6),
              Text(title,
                  style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(subtitle,
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 10.5, fontStyle: FontStyle.italic),
                    textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Loading / Error / Permission Screens
// ═══════════════════════════════════════════════════════════════════════════════

class _LoadingScreen extends StatelessWidget {
  final String message;
  final String subtitle;
  const _LoadingScreen({required this.message, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(message,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold)),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(subtitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorScreen({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: Colors.redAccent, size: 48),
              const SizedBox(height: 16),
              const Text('Initialization Failed',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Could not load detection models.',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Retry'),
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionDeniedScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off_rounded,
                  color: Colors.white38, size: 48),
              const SizedBox(height: 16),
              const Text('Camera Access Required',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Enable camera permission in Settings to use Live Scan.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                  textAlign: TextAlign.center),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                icon: const Icon(Icons.settings_rounded, size: 16),
                label: const Text('Open Settings'),
                onPressed: openAppSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Scanner Animation
// ═══════════════════════════════════════════════════════════════════════════════

class _ScannerAnimation extends StatefulWidget {
  const _ScannerAnimation();

  @override
  State<_ScannerAnimation> createState() => _ScannerAnimationState();
}

class _ScannerAnimationState extends State<_ScannerAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pos;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _pos = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, constraints) {
      final h = constraints.maxHeight;
      return AnimatedBuilder(
        animation: _pos,
        builder: (_, _) => Stack(
          children: [
            Positioned(
              top: _pos.value * (h - 3),
              left: 0,
              right: 0,
              child: Container(
                height: 2,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      AppColors.primary.withAlpha(200),
                      AppColors.primary,
                      AppColors.primary.withAlpha(200),
                      Colors.transparent,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withAlpha(120),
                      blurRadius: 8,
                      spreadRadius: 3,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}
