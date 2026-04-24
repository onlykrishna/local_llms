import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../domain/services/inference_router.dart';
import '../../domain/services/domain_service.dart';
import '../../domain/models/inference_domain.dart';
import '../../core/services/settings_service.dart';

class BackendStatusBar extends StatelessWidget {
  const BackendStatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final router = Get.find<InferenceRouterService>();
    final domainService = Get.find<DomainService>();
    final theme = Theme.of(context);

    return Container(
      height: 32,
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // Left: backend selector (FEATURE 3)
          Obx(() {
            final backend = router.isManualMode.value 
                ? router.manualBackend.value 
                : router.currentBackend.value;
            final isManual = router.isManualMode.value;

            return PopupMenuButton<InferenceBackend>(
              padding: EdgeInsets.zero,
              offset: const Offset(0, 30),
              tooltip: 'Choose AI Engine',
              onSelected: (InferenceBackend b) {
                router.setManualBackend(b);
              },
              itemBuilder: (context) => [
                _buildMenuItem(context, 'Auto Routing', Icons.auto_mode_rounded, Colors.grey, null, isAuto: true),
                _buildMenuItem(context, 'Gemini Flash', Icons.cloud_rounded, Colors.green, InferenceBackend.gemini),
                _buildMenuItem(context, 'Ollama LAN', Icons.lan_rounded, Colors.blue, InferenceBackend.ollama),
                _buildMenuItem(context, 'On-device AI', Icons.memory_rounded, Colors.orange, InferenceBackend.onDevice),
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

          // Right: domain chip
          Obx(() {
            final domain = domainService.selectedDomain.value;
            return Container(
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: _domainColor(domain).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _domainColor(domain).withOpacity(0.25),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_domainIcon(domain), size: 11, color: _domainColor(domain)),
                  const SizedBox(width: 4),
                  Text(
                    domain.label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: _domainColor(domain),
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  PopupMenuItem<InferenceBackend> _buildMenuItem(
    BuildContext context, 
    String label, 
    IconData icon, 
    Color color,
    InferenceBackend? value,
    {bool isAuto = false}
  ) {
    final router = Get.find<InferenceRouterService>();
    return PopupMenuItem<InferenceBackend>(
      value: value ?? InferenceBackend.onDevice,
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

  Color _dotColor(InferenceBackend backend) {
    switch (backend) {
      case InferenceBackend.gemini:   return Colors.green;
      case InferenceBackend.ollama:   return Colors.blue;
      case InferenceBackend.onDevice: return Colors.orange;
    }
  }

  String _backendLabel(InferenceBackend backend, String currentLocalModel) {
    switch (backend) {
      case InferenceBackend.gemini:   return 'Gemini AI';
      case InferenceBackend.ollama:   return 'Ollama LAN';
      case InferenceBackend.onDevice: return currentLocalModel;
    }
  }

  Color _domainColor(InferenceDomain domain) {
    switch (domain) {
      case InferenceDomain.health:     return const Color(0xFFE53935);
      case InferenceDomain.bollywood:  return const Color(0xFFF9A825);
      case InferenceDomain.education:  return const Color(0xFF1565C0);
      case InferenceDomain.banking:    return const Color(0xFF43A047);
      case InferenceDomain.general:    return const Color(0xFF00695C);
    }
  }

  IconData _domainIcon(InferenceDomain domain) {
    switch (domain) {
      case InferenceDomain.health:     return Icons.favorite_rounded;
      case InferenceDomain.bollywood:  return Icons.movie_creation_rounded;
      case InferenceDomain.education:  return Icons.school_rounded;
      case InferenceDomain.banking:    return Icons.account_balance_rounded;
      case InferenceDomain.general:    return Icons.chat_bubble_rounded;
    }
  }
}
