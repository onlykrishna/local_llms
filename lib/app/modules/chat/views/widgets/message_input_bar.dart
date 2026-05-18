import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import '../../../../core/theme/app_theme.dart';

class MessageInputBar extends StatefulWidget {
  final RxBool isTyping;
  final Function(String) onSend;
  final String? hintText;

  const MessageInputBar({
    super.key,
    required this.isTyping,
    required this.onSend,
    this.hintText,
  });

  @override
  State<MessageInputBar> createState() => _MessageInputBarState();
}

class _MessageInputBarState extends State<MessageInputBar> {
  final TextEditingController _controller = TextEditingController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasText) setState(() => _hasText = hasText);
    });
  }

  void _handleSend() {
    if (_controller.text.trim().isNotEmpty && !widget.isTyping.value) {
      HapticFeedback.lightImpact();
      widget.onSend(_controller.text);
      _controller.clear();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.dividerColor,
            width: 0.5,
          ),
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withAlpha(120),
                  borderRadius: const BorderRadius.all(AppRadius.xl),
                ),
                child: TextField(
                  controller: _controller,
                  maxLines: 5,
                  minLines: 1,
                  textInputAction: TextInputAction.newline,
                  style: AppTextStyles.body,
                  decoration: InputDecoration(
                    hintText: widget.hintText ?? 'Ask anything...',
                    hintStyle: AppTextStyles.body.copyWith(
                      color: theme.colorScheme.onSurface.withAlpha(100),
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm + 2,
                    ),
                  ),
                  onSubmitted: (_) => _handleSend(),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Obx(() {
              final disabled = widget.isTyping.value;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: disabled
                      ? theme.disabledColor
                      : AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.send_rounded, color: Colors.white),
                  onPressed: disabled ? null : _handleSend,
                )
                    .animate(target: _hasText && !disabled ? 1.0 : 0.0)
                    .scale(
                      begin: const Offset(0.8, 0.8),
                      end: const Offset(1.0, 1.0),
                      duration: 150.ms,
                    )
                    .fade(begin: 0.4, end: 1.0, duration: 150.ms),
              );
            }),
          ],
        ),
      ),
    );
  }
}
