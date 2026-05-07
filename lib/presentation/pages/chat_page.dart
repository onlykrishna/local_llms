import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../controllers/chat_controller.dart';
import '../widgets/message_bubble.dart';
import '../widgets/typing_indicator.dart';
import '../widgets/backend_status_bar.dart';
import '../../domain/kb_embedding_service.dart';
import '../../domain/services/inference_router.dart';

class ChatPage extends GetView<ChatController> {
  const ChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      children: [
        Column(
          children: [
            const SizedBox(height: 100),
            const BackendStatusBar(),
            _buildKbStatusBar(), // KB Status Panel

            Expanded(
              child: Obx(() {
                if (controller.messages.isEmpty &&
                    !controller.isGenerating.value) {
                  return const _EmptyChatView();
                }
                return ListView.builder(
                  controller: controller.scrollController,
                  reverse: true,
                  physics: const BouncingScrollPhysics(),
                  itemCount: controller.messages.length +
                      (controller.isGenerating.value ? 1 : 0),
                  padding: const EdgeInsets.only(bottom: 0, top: 12),
                  itemBuilder: (context, index) {
                    if (index == 0 && controller.isGenerating.value) {
                      if (controller.currentResponseText.value.isEmpty) {
                        return Animate(child: const TypingIndicator())
                            .fadeIn(duration: 400.ms)
                            .slideY(begin: 0.1, end: 0);
                      } else {
                        return Animate(
                                child: _StreamingBubble(controller: controller))
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
                );
              }),
            ),
            _buildInputArea(context),
          ],
        ),
        // Initialization overlay
        Obx(() {
          if (controller.isModelInitializing.value) {
            return Positioned(
              top: 150,
              left: 16,
              right: 16,
              child: Animate(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: theme.colorScheme.primary.withOpacity(0.3)),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 4)),
                      ]),
                  child: Row(
                    children: [
                      SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.colorScheme.primary)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Initializing local engine...',
                              style: TextStyle(
                                  color: theme.colorScheme.onSurface,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13),
                            ),
                            const SizedBox(height: 4),
                            Obx(() => Text(
                                  controller.loadingStage.value,
                                  style: TextStyle(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 12),
                                )),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ).fadeIn(duration: 300.ms).slideY(begin: -0.2, end: 0),
            );
          }
          return const SizedBox.shrink();
        }),
      ],
    );
  }

  Widget _buildKbStatusBar() {
    final kbService = Get.find<KbEmbeddingService>();
    return StreamBuilder<KbInitStatus>(
      stream: kbService.statusStream,
      builder: (context, snapshot) {
        final status = snapshot.data;
        if (status == null) return const SizedBox.shrink();

        switch (status.stage) {
          case KbInitStage.loading:
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.15),
                border: Border(
                    bottom: BorderSide(color: Colors.purple.withOpacity(0.3))),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFF9B59B6)),
                    ),
                    const SizedBox(width: 8),
                    Text(status.message,
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontFamily: 'Inter')),
                  ]),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: status.progress,
                      backgroundColor: Colors.white10,
                      valueColor:
                          const AlwaysStoppedAnimation(Color(0xFF9B59B6)),
                      minHeight: 2,
                    ),
                  ),
                  if (status.currentEntry != null) ...[
                    const SizedBox(height: 2),
                    Text(status.currentEntry!,
                        style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 9,
                            fontFamily: 'Inter',
                            overflow: TextOverflow.ellipsis),
                        maxLines: 1),
                  ],
                ],
              ),
            );
          case KbInitStage.ready:
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(children: [
                const Icon(Icons.check_circle_outline,
                    size: 12, color: Color(0xFF2ECC71)),
                const SizedBox(width: 6),
                Text(status.message,
                    style: const TextStyle(
                        color: Color(0xFF2ECC71),
                        fontSize: 10,
                        fontFamily: 'Inter')),
              ]),
            );
          case KbInitStage.error:
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(children: [
                const Icon(Icons.error_outline,
                    size: 12, color: Colors.redAccent),
                const SizedBox(width: 6),
                Text(status.message,
                    style:
                        const TextStyle(color: Colors.redAccent, fontSize: 10)),
              ]),
            );
        }
      },
    );
  }

  Widget _buildQueryStatusIndicator() {
    final router = Get.find<InferenceRouterService>();
    return StreamBuilder<QueryStatus>(
      stream: router.queryStatusStream,
      builder: (context, snapshot) {
        final status = snapshot.data;
        if (status == null || status.stage == QueryStage.done) {
          return const SizedBox.shrink();
        }

        final icon = switch (status.stage) {
          QueryStage.expanding => Icons.manage_search,
          QueryStage.embedding => Icons.bubble_chart,
          QueryStage.searching => Icons.travel_explore,
          QueryStage.reranking => Icons.sort,
          QueryStage.generating => Icons.psychology,
          QueryStage.done => Icons.check,
        };

        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(children: [
            const _PulsingDot(color: Color(0xFF9B59B6)),
            const SizedBox(width: 10),
            Icon(icon, size: 14, color: Colors.purpleAccent),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(status.message,
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                  if (status.detail != null)
                    Text(status.detail!,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 10)),
                ],
              ),
            ),
          ]),
        );
      },
    );
  }

  Widget _buildInputArea(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
            top: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2))),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Column(
                children: [
                  _buildQueryStatusIndicator(),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainer,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color:
                                    theme.colorScheme.outline.withOpacity(0.5)),
                          ),
                          child: TextField(
                            controller: controller.inputController,
                            maxLines: 4,
                            minLines: 1,
                            style:
                                TextStyle(color: theme.colorScheme.onSurface),
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => controller.sendMessage(),
                            decoration: InputDecoration(
                              hintText: 'Synthesizing with local knowledge...',
                              hintStyle: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant
                                      .withOpacity(0.5),
                                  fontSize: 13),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
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
                                color: theme.colorScheme.onPrimary),
                          )),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        duration: const Duration(milliseconds: 900), vsync: this)
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(_ctrl);
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                  color: widget.color.withOpacity(0.6),
                  blurRadius: 6,
                  spreadRadius: 2)
            ]),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
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
              child: Icon(Icons.auto_awesome,
                  size: 16, color: theme.colorScheme.primary),
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
                      color:
                          theme.colorScheme.surfaceContainer.withOpacity(0.8),
                      border: Border.all(
                          color: theme.colorScheme.outline.withOpacity(0.3)),
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

class _EmptyChatView extends StatelessWidget {
  const _EmptyChatView();
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary.withOpacity(0.05),
                border: Border.all(
                    color: theme.colorScheme.primary.withOpacity(0.1)),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withOpacity(0.1),
                    blurRadius: 40,
                    spreadRadius: 2,
                  )
                ],
              ),
              child: Icon(Icons.auto_awesome,
                  size: 72, color: theme.colorScheme.primary.withOpacity(0.6)),
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scale(
                    duration: const Duration(seconds: 2),
                    begin: const Offset(1, 1),
                    end: const Offset(1.15, 1.15))
                .fadeIn(duration: 800.ms),
            const SizedBox(height: 48),
            Text(
              'Grounded Intelligence Ready',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: theme.colorScheme.onSurface,
                letterSpacing: -1.0,
              ),
            ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.3, end: 0),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 56),
              child: Text(
                'Ask any question based on your uploaded documents. All intelligence remains strictly on-device.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
                  height: 1.6,
                ),
              ),
            ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.3, end: 0),
            const SizedBox(height: 32),
            _buildVerifiedQuestions(context),
            const SizedBox(height: 44),
            Icon(Icons.keyboard_arrow_down_rounded,
                    color: theme.colorScheme.primary.withOpacity(0.3))
                .animate(onPlay: (c) => c.repeat())
                .move(
                    duration: 800.ms,
                    begin: const Offset(0, 0),
                    end: const Offset(0, 10))
                .fadeOut(duration: 800.ms),
          ],
        ),
      ),
    );
  }

  Widget _buildVerifiedQuestions(BuildContext context) {
    final theme = Theme.of(context);
    final controller = Get.find<ChatController>();

    void ask(String question) {
      controller.inputController.text = question;
      controller.sendMessage();
    }

    return Column(
      children: [
        Text(
          'SUGGESTED QUESTIONS',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary.withOpacity(0.5),
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            _QuestionChip(
                label: 'What is an EMI?', onTap: () => ask('What is an EMI?')),
            _QuestionChip(
                label: 'Home Loan Eligibility?',
                onTap: () => ask('Who can avail a home loan?')),
            _QuestionChip(
                label: 'Business Loan Docs?',
                onTap: () => ask(
                    'What documents are needed for a working capital loan?')),
          ],
        ).animate().fadeIn(delay: 600.ms),
      ],
    );
  }
}

class _QuestionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _QuestionChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      backgroundColor: theme.colorScheme.surfaceContainer,
      labelStyle: TextStyle(color: theme.colorScheme.primary),
      side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.2)),
      onPressed: onTap,
    );
  }
}
