import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../domain/services/inference_router.dart';
import '../../domain/services/domain_service.dart';
import '../../domain/models/inference_domain.dart';
import '../pages/settings_page.dart';

class BackendStatusBar extends StatelessWidget {
  const BackendStatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final router = Get.find<InferenceRouterService>();
    final domainService = Get.find<DomainService>();

    return Container(
      height: 28,
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // Left: backend indicator
          Obx(() {
            final backend = router.currentBackend.value;
            return GestureDetector(
              onTap: () => Get.to(() => const SettingsPage()),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _dotColor(backend),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _backendLabel(backend),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _dotColor(backend),
                    ),
                  ),
                ],
              ),
            );
          }),

          const Spacer(),

          // Right: domain chip
          Obx(() {
            final domain = domainService.selectedDomain.value;
            return Container(
              height: 20,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: _domainColor(domain).withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _domainColor(domain).withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_domainIcon(domain), size: 10, color: _domainColor(domain)),
                  const SizedBox(width: 3),
                  Text(
                    domain.label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _domainColor(domain),
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

  Color _dotColor(InferenceBackend backend) {
    switch (backend) {
      case InferenceBackend.gemini:   return Colors.green;
      case InferenceBackend.ollama:   return Colors.blue;
      case InferenceBackend.onDevice: return Colors.orange;
    }
  }

  String _backendLabel(InferenceBackend backend) {
    switch (backend) {
      case InferenceBackend.gemini:   return 'Online (Gemini)';
      case InferenceBackend.ollama:   return 'Ollama LAN';
      case InferenceBackend.onDevice: return 'On-device AI';
    }
  }

  Color _domainColor(InferenceDomain domain) {
    switch (domain) {
      case InferenceDomain.health:     return const Color(0xFFE53935);
      case InferenceDomain.bollywood:  return const Color(0xFFF9A825);
      case InferenceDomain.education:  return const Color(0xFF1565C0);
      case InferenceDomain.general:    return const Color(0xFF00695C);
    }
  }

  IconData _domainIcon(InferenceDomain domain) {
    switch (domain) {
      case InferenceDomain.health:     return Icons.favorite_rounded;
      case InferenceDomain.bollywood:  return Icons.movie_creation_rounded;
      case InferenceDomain.education:  return Icons.school_rounded;
      case InferenceDomain.general:    return Icons.chat_bubble_rounded;
    }
  }
}
