import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../controllers/chat_controller.dart';
import '../widgets/message_bubble.dart';
import '../widgets/typing_indicator.dart';
import '../widgets/model_selector.dart';

class ChatPage extends GetView<ChatController> {
  const ChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildConnectivityBanner(context),
        Expanded(
          child: Obx(() => ListView.builder(
            controller: controller.scrollController,
            reverse: true, // New messages at the bottom
            itemCount: controller.messages.length + (controller.isLoading.value ? 1 : 0),
            padding: const EdgeInsets.only(bottom: 24, top: 12),
            itemBuilder: (context, index) {
              if (index == 0 && controller.isLoading.value) {
                if (controller.currentResponseText.value.isEmpty) {
                  return Animate(
                    child: TypingIndicator(), 
                  ).fadeIn(duration: const Duration(milliseconds: 400))
                   .slideY(begin: 0.1, end: 0);
                } else {
                  return Animate(
                    child: _buildStreamingBubble(context),
                  ).fadeIn(duration: const Duration(milliseconds: 300));
                }
              }
              
              final int msgIndex = controller.isLoading.value ? index - 1 : index;
              final msg = controller.messages[msgIndex];
              return Animate(
                child: MessageBubble(message: msg),
              ).fadeIn(duration: const Duration(milliseconds: 400))
               .slideX(begin: msg.isUser ? 0.05 : -0.05, end: 0);
            },
          )),
        ),
        _buildInputArea(context),
      ],
    );
  }

  Widget _buildConnectivityBanner(BuildContext context) {
    final banner = Obx(() {
      final isOnline = controller.isOllamaOnline.value;
      final isHWReady = controller.isHardwareReady.value;
      
      String text = 'Ollama Server Unreachable: Using Offline Local Datasets';
      IconData icon = Icons.offline_bolt;
      Color color = Colors.redAccent.withOpacity(0.9);

      if (isOnline) return const SizedBox.shrink();

      if (isHWReady) {
        text = 'Hardware AI Active: Gemma 2B Inference Running Locally';
        icon = Icons.psychology;
        color = Colors.teal.shade800.withOpacity(0.9);
      }

      return AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        height: 40,
        decoration: BoxDecoration(color: color),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 14),
              const SizedBox(width: 8),
              Text(
                text,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      );
    });

    return Animate(
      child: banner,
      target: controller.isOllamaOnline.value ? 0 : 1,
    ).fadeIn().shimmer(delay: const Duration(seconds: 1));
  }

  Widget _buildStreamingBubble(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.teal.shade700,
              child: const Icon(Icons.auto_awesome, size: 16, color: Colors.white),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
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

  Widget _buildInputArea(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.1))),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                const ModelSelector(),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => Get.snackbar('Tip', 'Long press on any bubble to copy!'),
                  icon: const Icon(Icons.lightbulb_outline, size: 14),
                  label: const Text('Help', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller.inputController,
                    maxLines: 4,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => controller.sendMessage(),
                    decoration: InputDecoration(
                      hintText: 'Ask your local AI...',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FloatingActionButton.small(
                  onPressed: () => controller.sendMessage(),
                  elevation: 0,
                  child: const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
