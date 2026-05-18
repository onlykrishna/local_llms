import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/theme/app_theme.dart';

class NoConnectionBanner extends StatelessWidget {
  const NoConnectionBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isOffline = !Get.find<ConnectivityService>().isOnline.value;
      return AnimatedSlide(
        offset: isOffline ? Offset.zero : const Offset(0, -1),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        child: AnimatedOpacity(
          opacity: isOffline ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: Container(
            color: AppColors.warning,
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.wifi_off, size: 16, color: Colors.black87),
                const SizedBox(width: 8),
                Text(
                  'No internet connection',
                  style: AppTextStyles.caption.copyWith(color: Colors.black87),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}
