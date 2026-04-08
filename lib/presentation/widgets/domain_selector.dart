import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../domain/models/inference_domain.dart';
import '../../domain/services/domain_service.dart';

class DomainSelector extends StatelessWidget {
  const DomainSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final domainService = Get.find<DomainService>();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Text(
            'Mode:',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Obx(() => Row(
                children: InferenceDomain.values.map((domain) {
                  final isSelected = domainService.selectedDomain.value == domain;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _DomainChip(
                      domain: domain,
                      isSelected: isSelected,
                      onTap: () {
                        domainService.changeDomain(domain);
                        Get.snackbar(
                          '${domain.label} Mode',
                          'Switched to ${domain.label} mode. Next message will be domain-scoped.',
                          snackPosition: SnackPosition.TOP,
                          duration: const Duration(seconds: 2),
                          backgroundColor: _domainColor(domain).withOpacity(0.9),
                          colorText: Colors.white,
                          margin: const EdgeInsets.all(8),
                        );
                      },
                    ),
                  );
                }).toList(),
              )),
            ),
          ),
        ],
      ),
    );
  }

  Color _domainColor(InferenceDomain domain) {
    switch (domain) {
      case InferenceDomain.health:     return const Color(0xFFE53935);
      case InferenceDomain.bollywood:  return const Color(0xFFF9A825);
      case InferenceDomain.education:  return const Color(0xFF1565C0);
      case InferenceDomain.general:    return const Color(0xFF00695C);
    }
  }
}

class _DomainChip extends StatelessWidget {
  final InferenceDomain domain;
  final bool isSelected;
  final VoidCallback onTap;

  const _DomainChip({
    required this.domain,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = _color;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : color.withOpacity(0.4),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _icon,
              size: 13,
              color: isSelected ? Colors.white : color,
            ),
            const SizedBox(width: 4),
            Text(
              domain.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color get _color {
    switch (domain) {
      case InferenceDomain.health:     return const Color(0xFFE53935);
      case InferenceDomain.bollywood:  return const Color(0xFFF9A825);
      case InferenceDomain.education:  return const Color(0xFF1565C0);
      case InferenceDomain.general:    return const Color(0xFF00695C);
    }
  }

  IconData get _icon {
    switch (domain) {
      case InferenceDomain.health:     return Icons.favorite_rounded;
      case InferenceDomain.bollywood:  return Icons.movie_creation_rounded;
      case InferenceDomain.education:  return Icons.school_rounded;
      case InferenceDomain.general:    return Icons.chat_bubble_rounded;
    }
  }
}
