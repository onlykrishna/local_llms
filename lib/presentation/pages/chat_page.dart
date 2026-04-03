import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../controllers/chat_controller.dart';
import '../widgets/message_bubble.dart';
import '../widgets/typing_indicator.dart';
import '../widgets/domain_selector.dart';
import '../widgets/backend_status_bar.dart';

class ChatPage extends GetView<ChatController> {
  const ChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Slim 28px backend + domain bar
        const BackendStatusBar(),
        // Chat messages
        Expanded(
          child: Obx(() => ListView.builder(
            controller: controller.scrollController,
            reverse: true,
            itemCount: controller.messages.length +
                (controller.isGenerating.value ? 1 : 0),
            padding: const EdgeInsets.only(bottom: 24, top: 12),
            itemBuilder: (context, index) {
              if (index == 0 && controller.isGenerating.value) {
                if (controller.currentResponseText.value.isEmpty) {
                  return Animate(child: TypingIndicator())
                      .fadeIn(duration: 400.ms)
                      .slideY(begin: 0.1, end: 0);
                } else {
                  return Animate(child: _StreamingBubble(controller: controller))
                      .fadeIn(duration: 300.ms);
                }
              }
              final msgIndex =
                  controller.isGenerating.value ? index - 1 : index;
              final msg = controller.messages[msgIndex];
              return Animate(child: MessageBubble(message: msg))
                  .fadeIn(duration: 400.ms)
                  .slideX(begin: msg.isUser ? 0.05 : -0.05, end: 0);
            },
          )),
        ),
        // Domain chips + input
        _buildInputArea(context),
      ],
    );
  }

  Widget _buildInputArea(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(
              color: Theme.of(context).dividerColor.withOpacity(0.1)),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Domain selector row
            const DomainSelector(),
            // Input row
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller.inputController,
                      maxLines: 4,
                      minLines: 1,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => controller.sendMessage(),
                      decoration: InputDecoration(
                        hintText: 'Ask anything...',
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        filled: true,
                        fillColor: Theme.of(context)
                            .colorScheme
                            .surfaceVariant
                            .withOpacity(0.3),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Send / Stop FAB
                  Obx(() => FloatingActionButton.small(
                        heroTag: 'chat_send_btn',
                        backgroundColor: controller.isGenerating.value
                            ? Colors.red
                            : Theme.of(context).colorScheme.primary,
                        elevation: 0,
                        onPressed: controller.isGenerating.value
                            ? controller.stopGeneration
                            : controller.sendMessage,
                        child: Icon(
                          controller.isGenerating.value
                              ? Icons.stop_rounded
                              : Icons.send_rounded,
                          color: Colors.white,
                        ),
                      )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StreamingBubble extends StatelessWidget {
  final ChatController controller;
  const _StreamingBubble({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.indigo.shade700,
              child: const Icon(Icons.auto_awesome, size: 16, color: Colors.white),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceVariant
                      .withOpacity(0.4),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                    bottomLeft: Radius.circular(4),
                  ),
                ),
                child: Obx(() => Text(
                      controller.currentResponseText.value,
                      style: const TextStyle(fontSize: 15, height: 1.4),
                    )),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
