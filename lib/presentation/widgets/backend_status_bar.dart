import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../domain/services/inference_router.dart';
import '../../core/services/settings_service.dart';

class BackendStatusBar extends StatelessWidget {
  const BackendStatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final router = Get.find<InferenceRouterService>();
    final theme = Theme.of(context);

    return Container(
      height: 32,
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // Left: backend selector
          Obx(() {
            final backend = router.isManualMode.value 
                ? router.manualBackend.value 
                : router.currentBackend.value;
            final isManual = router.isManualMode.value;

            return PopupMenuButton<InferenceBackendType>(
              padding: EdgeInsets.zero,
              offset: const Offset(0, 30),
              tooltip: 'Choose AI Engine',
              onSelected: (InferenceBackendType b) {
                router.setManualBackend(b);
              },
              itemBuilder: (context) => [
                _buildMenuItem(context, 'Auto Routing', Icons.auto_mode_rounded, Colors.grey, null, isAuto: true),
                _buildMenuItem(context, 'Ollama LAN', Icons.lan_rounded, Colors.blue, InferenceBackendType.ollama),
                _buildMenuItem(context, 'On-device AI', Icons.memory_rounded, Colors.orange, InferenceBackendType.onDevice),
              ],
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _dotColor(backend),
                      boxShadow: [
                        BoxShadow(
                          color: _dotColor(backend).withOpacity(0.5),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isManual 
                        ? '${_backendLabel(backend, Get.find<SettingsService>().modelLabel)} (Locked)' 
                        : _backendLabel(backend, Get.find<SettingsService>().modelLabel),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _dotColor(backend),
                    ),
                  ),
                  Icon(Icons.arrow_drop_down_rounded, size: 16, color: _dotColor(backend)),
                ],
              ),
            );
          }),

          const Spacer(),

          // Right: Status indicator
          Text(
            'STRICT GROUNDING ON',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.4),
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<InferenceBackendType> _buildMenuItem(
    BuildContext context, 
    String label, 
    IconData icon, 
    Color color,
    InferenceBackendType? value,
    {bool isAuto = false}
  ) {
    final router = Get.find<InferenceRouterService>();
    return PopupMenuItem<InferenceBackendType>(
      value: value ?? InferenceBackendType.onDevice,
      onTap: isAuto ? () => router.resetToAuto() : null,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          if (isAuto && !router.isManualMode.value) ...[
            const Spacer(),
            const Icon(Icons.check_circle_rounded, size: 16, color: Colors.green),
          ] else if (value != null && router.isManualMode.value && router.manualBackend.value == value) ...[
             const Spacer(),
             const Icon(Icons.check_circle_rounded, size: 16, color: Colors.green),
          ]
        ],
      ),
    );
  }

  Color _dotColor(InferenceBackendType backend) {
    switch (backend) {
      case InferenceBackendType.ollama:   return Colors.blue;
      case InferenceBackendType.onDevice: return Colors.orange;
    }
  }

  String _backendLabel(InferenceBackendType backend, String currentLocalModel) {
    switch (backend) {
      case InferenceBackendType.ollama:   return 'Ollama LAN';
      case InferenceBackendType.onDevice: return currentLocalModel;
    }
  }
}
