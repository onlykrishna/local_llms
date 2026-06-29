import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import '../controllers/live_voice_controller.dart';
import '../../../core/theme/app_theme.dart';

/// Full-screen live voice conversation view.
/// Matches the ChatGPT voice mode: animated orb, live transcript pill, close button.
class LiveVoiceScreen extends GetView<LiveVoiceController> {
  const LiveVoiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceLight,
      body: SafeArea(
        child: Stack(
          children: [
            // ── Animated background gradient ────────────────
            Positioned.fill(
              child: Obx(() {
                final isActive = controller.isListening.value ||
                    controller.isSpeaking.value;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 800),
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.center,
                      radius: 1.5,
                      colors: isActive
                          ? [
                              AppColors.primary.withAlpha(30),
                              AppColors.surfaceLight,
                            ]
                          : [
                              AppColors.surfaceLight,
                              AppColors.surfaceLight,
                            ],
                    ),
                  ),
                );
              }),
            ),

            // ── Close button ────────────────────────────────
            Positioned(
              top: AppSpacing.md,
              right: AppSpacing.md,
              child: IconButton(
                onPressed: controller.close,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.grey.shade200,
                  shape: const CircleBorder(),
                ),
                icon: const Icon(Icons.close_rounded, color: Colors.black54),
              ),
            ),

            // ── Main content ────────────────────────────────
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Animated orb
                  _AnimatedOrb(controller: controller),

                  const SizedBox(height: AppSpacing.xxl),

                  // Status pill
                  Obx(() => _StatusPill(text: controller.statusText.value)),

                  const SizedBox(height: AppSpacing.xl),

                  // Loop control button — always tappable; icon toggles between start/stop
                  Obx(() {
                    final looping = controller.isLooping.value;
                    return GestureDetector(
                      onTap: controller.toggleLoop, // always active (Issue 6 fix)
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xl,
                          vertical: AppSpacing.md,
                        ),
                        decoration: BoxDecoration(
                          color: looping
                              ? AppColors.error.withAlpha(220)
                              : AppColors.primary,
                          borderRadius: const BorderRadius.all(AppRadius.full),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 250),
                              child: Icon(
                                looping
                                    ? Icons.stop_rounded
                                    : Icons.mic_rounded,
                                key: ValueKey(looping),
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 250),
                              child: Text(
                                looping ? 'Tap to stop' : 'Start Conversation',
                                key: ValueKey('label_$looping'),
                                style: AppTextStyles.body.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
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
          ],
        ),
      ),
    );
  }
}

// ── Animated Orb ───────────────────────────────────────────

class _AnimatedOrb extends StatelessWidget {
  final LiveVoiceController controller;
  const _AnimatedOrb({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isListening = controller.isListening.value;
      final isSpeaking = controller.isSpeaking.value;
      final isThinking = controller.isThinking.value;

      return Stack(
        alignment: Alignment.center,
        children: [
          // Outer glow ring
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            width: isListening ? 200 : 170,
            height: isListening ? 200 : 170,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary
                  .withAlpha(isListening ? 30 : (isSpeaking ? 20 : 10)),
            ),
          )
              .animate(
                onPlay: (c) => c.repeat(reverse: true),
                target: (isListening || isSpeaking) ? 1.0 : 0.0,
              )
              .scaleXY(
                begin: 1.0,
                end: 1.08,
                duration: 900.ms,
                curve: Curves.easeInOut,
              ),

          // Mid ring
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            width: isListening ? 160 : 140,
            height: isListening ? 160 : 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary
                  .withAlpha(isListening ? 50 : (isSpeaking ? 35 : 20)),
            ),
          ),

          // Core orb
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: isThinking
                    ? [
                        Colors.purple.shade300,
                        AppColors.primary,
                      ]
                    : isSpeaking
                        ? [
                            AppColors.secondary,
                            AppColors.primary,
                          ]
                        : [
                            AppColors.primary,
                            AppColors.primaryDark,
                          ],
                center: Alignment.topLeft,
                radius: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary
                      .withAlpha(isListening || isSpeaking ? 100 : 50),
                  blurRadius: isListening ? 30 : 15,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              isThinking
                  ? Icons.psychology_rounded
                  : isSpeaking
                      ? Icons.volume_up_rounded
                      : isListening
                          ? Icons.mic_rounded
                          : Icons.mic_none_rounded,
              color: Colors.white,
              size: 44,
            ),
          )
              .animate(
                onPlay: (c) => c.repeat(reverse: true),
                target: (isListening || isSpeaking) ? 1.0 : 0.0,
              )
              .scaleXY(
                begin: 1.0,
                end: 1.05,
                duration: 700.ms,
                curve: Curves.easeInOut,
              ),
        ],
      );
    });
  }
}

// ── Status Pill ────────────────────────────────────────────

class _StatusPill extends StatelessWidget {
  final String text;
  const _StatusPill({required this.text});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Container(
        key: ValueKey(text.length > 40 ? text.substring(0, 40) : text),
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm + 2,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.all(AppRadius.full),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(15),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          text.isEmpty ? 'Tap Start Conversation' : text,
          style: AppTextStyles.body.copyWith(
            color: Colors.black87,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
