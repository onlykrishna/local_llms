import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/chat_controller.dart';
import 'widgets/chat_bubble.dart';
import 'widgets/typing_indicator.dart';
import 'widgets/provider_toggle.dart';
import 'widgets/message_input_bar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../routes/app_pages.dart';
import '../../../shared/widgets/no_connection_banner.dart';

class ChatScreen extends GetView<ChatController> {
  ChatScreen({super.key});

  final ScrollController _scrollController = ScrollController();

  void _confirmClear(BuildContext context) {
    Get.defaultDialog(
      title: 'Clear conversation?',
      middleText: 'This will delete all messages in this session.',
      textConfirm: 'Clear',
      textCancel: 'Cancel',
      confirmTextColor: Colors.white,
      buttonColor: AppColors.error,
      onConfirm: () {
        controller.clearConversation();
        Get.back();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Auto-scroll on new message
    ever(controller.messages, (_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    });

    // Auto-scroll when typing indicator appears/disappears
    ever(controller.isTyping, (_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Chat'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'PDF Chat',
            onPressed: () => Get.toNamed(AppRoutes.PDF_CHAT),
          ),
          const ProviderToggle(),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear conversation',
            onPressed: () => _confirmClear(context),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Get.toNamed(AppRoutes.SETTINGS),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              await Get.find<StorageService>().clearUid();
              Get.offAllNamed(AppRoutes.PHONE_INPUT);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Offline banner ──
          const NoConnectionBanner(),

          // ── Message list ──
          Expanded(
            child: Obx(() {
              if (controller.isLoadingHistory.value) {
                return const Center(child: CircularProgressIndicator());
              }

              if (controller.messages.isEmpty && !controller.isTyping.value) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 64,
                        color: theme.colorScheme.onSurface.withAlpha(80),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Start a conversation',
                        style: AppTextStyles.headline.copyWith(
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        'Ask anything — I\'m powered by ${controller.activeProviderName}',
                        style: AppTextStyles.body.copyWith(
                          color: theme.colorScheme.onSurface.withAlpha(140),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              }

              final itemCount = controller.messages.length +
                  (controller.isTyping.value ? 1 : 0);

              return ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.md,
                ),
                itemCount: itemCount,
                itemBuilder: (context, index) {
                  if (index < controller.messages.length) {
                    return ChatBubble(message: controller.messages[index]);
                  } else {
                    return const TypingIndicator();
                  }
                },
              );
            }),
          ),

          // ── Input bar ──
          MessageInputBar(
            isTyping: controller.isTyping,
            onSend: (text) => controller.sendMessage(text),
          ),
        ],
      ),
    );
  }
}
