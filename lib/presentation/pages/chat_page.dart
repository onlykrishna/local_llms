import 'package:flutter/material.dart';
import 'package:get/get.dart';
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
                // If it's the very first item (last index numerically in reversed list) and we're loading,
                // we show either the streaming text or the typing dots.
                if (controller.currentResponseText.value.isEmpty) {
                  return const TypingIndicator();
                } else {
                  return _buildStreamingBubble(context);
                }
              }
              
              final int msgIndex = controller.isLoading.value ? index - 1 : index;
              return MessageBubble(message: controller.messages[msgIndex]);
            },
          )),
        ),
        _buildInputArea(context),
      ],
    );
  }

  Widget _buildConnectivityBanner(BuildContext context) {
    return Obx(() => AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      height: controller.isOllamaOnline.value ? 0 : 36,
      color: Colors.redAccent.withOpacity(0.9),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.offline_bolt, color: Colors.white, size: 14),
            SizedBox(width: 8),
            Text(
              'Ollama Server Unreachable: Using Offline Local Datasets',
              style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    ));
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
