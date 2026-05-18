import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/pdf_chat_controller.dart';
import '../../../core/services/embedding_service.dart';
import 'widgets/pdf_list_panel.dart';
import 'widgets/upload_progress_card.dart';
import 'widgets/pdf_empty_state.dart';
import 'widgets/pdf_chat_bubble.dart';

import '../../chat/views/widgets/message_input_bar.dart';
import '../../chat/views/widgets/typing_indicator.dart';
import '../../../shared/widgets/app_drawer.dart';

class PdfChatScreen extends GetView<PdfChatController> {
  const PdfChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('PDF Chat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear_all),
            tooltip: 'Clear Chat',
            onPressed: () => controller.messages.clear(),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 640;

          if (isWide) {
            return Row(
              children: [
                SizedBox(
                  width: 280,
                  child: Column(
                    children: [
                      const Expanded(child: PdfListPanel()),
                      Obx(() {
                        if (controller.isUploading.value) {
                          return UploadProgressCard(
                            stage: controller.uploadStage.value,
                            progress: controller.uploadProgress.value,
                          );
                        }
                        return const SizedBox.shrink();
                      }),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: _buildChatArea(context),
                ),
              ],
            );
          } else {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8.0, vertical: 4.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.folder_outlined),
                        label: const Text('Manage PDFs'),
                        onPressed: () {
                          Get.bottomSheet(
                            Container(
                              color: theme.colorScheme.surface,
                              child: Column(
                                children: [
                                  const Expanded(child: PdfListPanel()),
                                  Obx(() {
                                    if (controller.isUploading.value) {
                                      return UploadProgressCard(
                                        stage: controller.uploadStage.value,
                                        progress:
                                            controller.uploadProgress.value,
                                      );
                                    }
                                    return const SizedBox.shrink();
                                  }),
                                ],
                              ),
                            ),
                            isScrollControlled: true,
                          );
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _buildChatArea(context),
                ),
              ],
            );
          }
        },
      ),
    );
  }

  Widget _buildChatArea(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Obx(() {
            if (controller.messages.isEmpty &&
                !controller.isThinking.value) {
              return const PdfEmptyState();
            }

            return ListView.builder(
              reverse: false,
              itemCount: controller.messages.length +
                  (controller.isThinking.value ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == controller.messages.length) {
                  return const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: TypingIndicator(),
                  );
                }

                final message = controller.messages[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 4.0),
                  child: PdfChatBubble(message: message),
                );
              },
            );
          }),
        ),
        MessageInputBar(
          isTyping: controller.isThinking,
          onSend: (text) => controller.sendQuestion(text),
        ),
      ],
    );
  }
}
