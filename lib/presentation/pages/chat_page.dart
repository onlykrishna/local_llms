import 'dart:ui';
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
    final theme = Theme.of(context);
    
    // ISSUE 1: Removed global GestureDetector as it interfered with drawer/navigation.
    // Replaced with professional 'onTapOutside' on TextField (see _buildInputArea).
    return Scaffold(
      backgroundColor: Colors.transparent, // Background handled by parent (main.dart)
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          const SizedBox(height: 100), // Spacing for transparent appbar
          const BackendStatusBar(),
          
          Expanded(
            child: Obx(() => ListView.builder(
              controller: controller.scrollController,
              reverse: true, // Reversed for messaging behavior
              physics: const BouncingScrollPhysics(),
              itemCount: controller.messages.length + (controller.isGenerating.value ? 1 : 0),
              padding: const EdgeInsets.only(bottom: 24, top: 12),
              itemBuilder: (context, index) {
                if (index == 0 && controller.isGenerating.value) {
                  if (controller.currentResponseText.value.isEmpty) {
                    return Animate(child: const TypingIndicator())
                        .fadeIn(duration: 400.ms)
                        .slideY(begin: 0.1, end: 0);
                  } else {
                    return Animate(child: _StreamingBubble(controller: controller))
                        .fadeIn(duration: 300.ms);
                  }
                }
                final msgIndex = controller.isGenerating.value ? index - 1 : index;
                final msg = controller.messages[msgIndex];
                return Animate(child: MessageBubble(message: msg))
                    .fadeIn(duration: 400.ms)
                    .slideX(begin: msg.isUser ? 0.05 : -0.05, end: 0);
              },
            )),
          ),
          _buildInputArea(context),
        ],
      ),
    );
  }

  Widget _buildInputArea(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const DomainSelector(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.5)),
                      ),
                      child: TextField(
                        controller: controller.inputController,
                        maxLines: 4,
                        minLines: 1,
                        style: TextStyle(color: theme.colorScheme.onSurface),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => controller.sendMessage(),
                        // FIX: Precise unfocus control that doesn't trigger when tapping functional UI elements
                        onTapOutside: (event) {
                          FocusManager.instance.primaryFocus?.unfocus();
                        },
                        decoration: InputDecoration(
                          hintText: 'Synthesizing with local knowledge...',
                          hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5), fontSize: 13),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          border: InputBorder.none,
                          filled: false,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Obx(() => FloatingActionButton(
                    heroTag: 'chat_send_btn',
                    mini: true,
                    backgroundColor: controller.isGenerating.value
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                    onPressed: controller.isGenerating.value
                        ? controller.stopGeneration
                        : controller.sendMessage,
                    child: Icon(
                      controller.isGenerating.value
                          ? Icons.stop_rounded
                          : Icons.send_rounded,
                      color: theme.colorScheme.onPrimary,
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
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.auto_awesome, size: 16, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                  bottomLeft: Radius.circular(4),
                ),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainer.withOpacity(0.8),
                      border: Border.all(color: theme.colorScheme.outline.withOpacity(0.3)),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                        bottomLeft: Radius.circular(4),
                      ),
                    ),
                    child: Obx(() => Text(
                      controller.currentResponseText.value,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 15,
                        height: 1.6,
                      ),
                    )),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
