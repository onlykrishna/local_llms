import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/live_scan_controller.dart';

/// Bottom control bar for the Live ML Scanner.
///
/// Contains:
///  - Torch (flashlight) toggle
///  - Zoom slider (1x – max device zoom)
///  - Confidence threshold selector (Low / Medium / High presets)
class ScanControlsBar extends StatelessWidget {
  const ScanControlsBar({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<LiveScanController>();
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(200),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor, width: 0.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Row 1: Torch + Confidence presets ─────────────────────────────
          Row(
            children: [
              // Torch toggle
              Obx(() => _ControlButton(
                icon: controller.isTorchOn.value
                    ? Icons.flashlight_on_rounded
                    : Icons.flashlight_off_rounded,
                label: 'Torch',
                active: controller.isTorchOn.value,
                onTap: controller.toggleTorch,
                activeColor: const Color(0xFFFBBC05),
                theme: theme,
              )),
              const SizedBox(width: 8),
              // Confidence presets
              Expanded(
                child: Obx(() => _ConfidenceSelector(
                  threshold: controller.confidenceThreshold.value,
                  onChanged: controller.setConfidenceThreshold,
                  theme: theme,
                )),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // ── Row 2: Zoom slider ────────────────────────────────────────────
          Obx(() {
            final minZ = controller.minZoom;
            final maxZ = controller.maxZoom;
            // Only show slider if device supports zooming beyond 1x
            if (maxZ <= minZ + 0.1) return const SizedBox.shrink();
            return Row(
              children: [
                Icon(Icons.zoom_out_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
                Expanded(
                  child: Slider(
                    value: controller.zoomLevel.value.clamp(minZ, maxZ),
                    min: minZ,
                    max: maxZ,
                    divisions: ((maxZ - minZ) * 10).toInt().clamp(1, 50),
                    label: '${controller.zoomLevel.value.toStringAsFixed(1)}×',
                    activeColor: theme.colorScheme.primary,
                    onChanged: (v) => controller.setZoom(v),
                  ),
                ),
                Icon(Icons.zoom_in_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                SizedBox(
                  width: 36,
                  child: Text(
                    '${controller.zoomLevel.value.toStringAsFixed(1)}×',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

// ── Torch button ──────────────────────────────────────────────────────────────

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color activeColor;
  final ThemeData theme;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    required this.activeColor,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? activeColor.withAlpha(30) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? activeColor : theme.dividerColor,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: active ? activeColor : theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: active ? activeColor : theme.colorScheme.onSurfaceVariant,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Confidence selector ───────────────────────────────────────────────────────

class _ConfidenceSelector extends StatelessWidget {
  final double threshold;
  final ValueChanged<double> onChanged;
  final ThemeData theme;

  const _ConfidenceSelector({
    required this.threshold,
    required this.onChanged,
    required this.theme,
  });

  static const _presets = [
    (label: 'Low', value: 0.3),
    (label: 'Med', value: 0.5),
    (label: 'High', value: 0.75),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          'Min Conf:',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant.withAlpha(180),
          ),
        ),
        const SizedBox(width: 4),
        ..._presets.map((preset) {
          final active = (threshold - preset.value).abs() < 0.05;
          return Padding(
            padding: const EdgeInsets.only(left: 4),
            child: GestureDetector(
              onTap: () => onChanged(preset.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: active
                      ? theme.colorScheme.primary
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: active ? theme.colorScheme.primary : theme.dividerColor,
                    width: 0.5,
                  ),
                ),
                child: Text(
                  preset.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: active ? Colors.white : theme.colorScheme.onSurfaceVariant,
                    fontWeight: active ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}
