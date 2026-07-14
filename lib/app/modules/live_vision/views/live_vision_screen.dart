import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_theme.dart';
import '../controllers/live_vision_controller.dart';

/// Full-screen "Live Vision" mode.
///
/// Layout:
///  • Full-bleed camera preview (like ChatGPT/Gemini vision mode)
///  • Dark gradient overlay at bottom
///  • Narration caption pill (latest AI text)
///  • Animated status orb (listening / thinking / speaking)
///  • Start/Stop button + Flip camera + Close buttons
class LiveVisionScreen extends GetView<LiveVisionController> {
  const LiveVisionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── 1. Camera preview ──────────────────────────────────────────
          Obx(() {
            final initialized = controller.isCameraInitialized.value;
            final denied = controller.isPermissionDenied.value;

            if (denied) return _PermissionDeniedView(onRetry: controller.retryCamera);
            if (!initialized) return _CameraLoadingView();

            final cc = controller.cameraController;
            if (cc == null || !cc.value.isInitialized) return _CameraLoadingView();

            return _FullCameraPreview(cameraController: cc);
          }),

          // ── 2. Top bar (AppBar behavior with scrim) ────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x99000000), Colors.transparent],
                  stops: [0.0, 1.0],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Close button
                      _CircleIconButton(
                        icon: Icons.close_rounded,
                        onTap: controller.close,
                        tooltip: 'Close',
                      ),

                      // "LIVE VISION" badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.xs + 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(AppRadius.full.x),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Animated red dot when running
                            Obx(() => AnimatedContainer(
                              duration: const Duration(milliseconds: 400),
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: controller.isRunning.value
                                    ? Colors.redAccent
                                    : Colors.white38,
                              ),
                            )),
                            const Text(
                              'LIVE VISION',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),

                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Test Speak Debug Button
                          _CircleIconButton(
                            icon: Icons.volume_up_rounded,
                            onTap: controller.testSpeak,
                            tooltip: 'Test Speak',
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          // Flip camera button
                          _CircleIconButton(
                            icon: Icons.flip_camera_ios_outlined,
                            onTap: controller.flipCamera,
                            tooltip: 'Flip camera',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── 3. Bottom gradient + controls ──────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xE6000000)],
                  stops: [0.0, 0.7],
                ),
              ),
              padding: const EdgeInsets.only(
                left: AppSpacing.md,
                right: AppSpacing.md,
                bottom: AppSpacing.lg,
                top: AppSpacing.xxl,
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Live transcript pill
                    Obx(() {
                      final text = controller.liveTranscript.value;
                      if (text.isEmpty) return const SizedBox.shrink();
                      return _TranscriptPill(text: text)
                          .animate()
                          .fadeIn(duration: 200.ms)
                          .slideY(begin: 0.3, end: 0, duration: 200.ms);
                    }),

                    const SizedBox(height: AppSpacing.sm),

                    // Narration caption
                    Obx(() {
                      final text = controller.latestNarration.value;
                      if (text.isEmpty) return const SizedBox.shrink();
                      return _NarrationCaption(text: text)
                          .animate()
                          .fadeIn(duration: 350.ms);
                    }),

                    const SizedBox(height: AppSpacing.lg),

                    // Status row: orb + status text + big action button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Animated state orb
                        _StateOrb(controller: controller),

                        const SizedBox(width: AppSpacing.md),

                        // Status pill
                        Expanded(
                          child: Obx(() => _StatusPill(
                            text: controller.statusText.value,
                          )),
                        ),
                      ],
                    ),

                    const SizedBox(height: AppSpacing.lg),

                    // Start / Stop button
                    Obx(() {
                      final running = controller.isRunning.value;
                      return GestureDetector(
                        onTap: controller.toggleSession,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          width: double.infinity,
                          height: 56,
                          decoration: BoxDecoration(
                            color: running
                                ? Colors.redAccent
                                : AppColors.primary,
                            borderRadius: BorderRadius.circular(AppRadius.full.x),
                            boxShadow: [
                              BoxShadow(
                                color: (running ? Colors.red : AppColors.primary)
                                    .withAlpha(120),
                                blurRadius: 20,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 250),
                                child: Icon(
                                  running ? Icons.stop_rounded : Icons.visibility_rounded,
                                  key: ValueKey(running),
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 10),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 250),
                                child: Text(
                                  running ? 'Stop Vision' : 'Start Vision',
                                  key: ValueKey('btn_$running'),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Camera Preview ─────────────────────────────────────────────────────────────

class _FullCameraPreview extends StatelessWidget {
  final CameraController cameraController;
  const _FullCameraPreview({required this.cameraController});

  @override
  Widget build(BuildContext context) {
    return OverflowBox(
      maxWidth: double.infinity,
      maxHeight: double.infinity,
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: cameraController.value.previewSize?.height ?? 1,
          height: cameraController.value.previewSize?.width ?? 1,
          child: CameraPreview(cameraController),
        ),
      ),
    );
  }
}

// ── Loading & Permission Views ─────────────────────────────────────────────────

class _CameraLoadingView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.white54),
          SizedBox(height: 16),
          Text('Initializing camera…',
              style: TextStyle(color: Colors.white54, fontSize: 14)),
        ],
      ),
    );
  }
}

class _PermissionDeniedView extends StatelessWidget {
  final VoidCallback onRetry;
  const _PermissionDeniedView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.camera_alt_outlined, size: 64, color: Colors.white38),
            const SizedBox(height: 20),
            const Text(
              'Camera permission required',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'Live Vision needs camera access to see the world around you.',
              style: TextStyle(color: Colors.white54, fontSize: 14, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Grant Permission'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: const StadiumBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── State Orb ──────────────────────────────────────────────────────────────────

class _StateOrb extends StatelessWidget {
  final LiveVisionController controller;
  const _StateOrb({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final listening = controller.isListening.value;
      final thinking = controller.isFetching.value;
      final speaking = controller.isSpeaking.value;

      final Color color = thinking
          ? Colors.purpleAccent
          : speaking
              ? AppColors.secondary
              : listening
                  ? AppColors.primary
                  : Colors.white38;

      final IconData icon = thinking
          ? Icons.psychology_rounded
          : speaking
              ? Icons.volume_up_rounded
              : listening
                  ? Icons.mic_rounded
                  : Icons.mic_none_rounded;

      final active = listening || thinking || speaking;

      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withAlpha(30),
          border: Border.all(color: color, width: 2),
          boxShadow: active
              ? [BoxShadow(color: color.withAlpha(100), blurRadius: 16)]
              : null,
        ),
        child: Icon(icon, color: color, size: 22),
      )
          .animate(
            onPlay: (c) => c.repeat(reverse: true),
            target: active ? 1.0 : 0.0,
          )
          .scaleXY(
            begin: 1.0,
            end: 1.12,
            duration: 700.ms,
            curve: Curves.easeInOut,
          );
    });
  }
}

// ── Status Pill ────────────────────────────────────────────────────────────────

class _StatusPill extends StatelessWidget {
  final String text;
  const _StatusPill({required this.text});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Container(
        key: ValueKey(text.length > 40 ? text.substring(0, 40) : text),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs + 2,
        ),
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(AppRadius.full.x),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(
          text.isEmpty ? 'Ready' : text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

// ── Narration Caption ─────────────────────────────────────────────────────────

class _NarrationCaption extends StatelessWidget {
  final String text;
  const _NarrationCaption({required this.text});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      child: Container(
        key: ValueKey(text.length > 50 ? text.substring(0, 50) : text),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + 2,
        ),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(AppRadius.lg.x),
          border: Border.all(color: Colors.white12),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            height: 1.5,
          ),
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

// ── Live Transcript Pill ────────────────────────────────────────────────────────

class _TranscriptPill extends StatelessWidget {
  final String text;
  const _TranscriptPill({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs + 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary.withAlpha(200),
        borderRadius: BorderRadius.circular(AppRadius.full.x),
      ),
      child: Text(
        '🎤 $text',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// ── Circle Icon Button ─────────────────────────────────────────────────────────

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  const _CircleIconButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black54,
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}
