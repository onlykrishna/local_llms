import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/models/chat_message.dart';
import '../../../../core/theme/app_theme.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatBubble({super.key, required this.message});

  void _showOptions(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    Get.bottomSheet(
      Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: AppRadius.lg),
        ),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor,
                borderRadius: const BorderRadius.all(AppRadius.full),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Copy'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: message.content));
                Get.back();
                Get.snackbar(
                  'Copied',
                  'Message copied to clipboard',
                  snackPosition: SnackPosition.BOTTOM,
                  duration: const Duration(seconds: 2),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Share'),
              onTap: () {
                Get.back();
                Share.share(message.content);
              },
            ),
            if (isUser)
              ListTile(
                leading: Icon(Icons.delete_outline, color: AppColors.error),
                title: Text('Delete', style: TextStyle(color: AppColors.error)),
                onTap: () {
                  Get.back();
                  // Controller handles removal; bubble is already shown
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    final isError = message.isError;
    final theme = Theme.of(context);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showOptions(context),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.8,
          ),
          decoration: BoxDecoration(
            color: isError
                ? AppColors.error.withAlpha(30)
                : isUser
                    ? AppColors.userBubble
                    : (theme.brightness == Brightness.dark
                        ? AppColors.aiBubbleDark
                        : AppColors.aiBubbleLight),
            borderRadius: BorderRadius.only(
              topLeft: AppRadius.lg,
              topRight: AppRadius.lg,
              bottomLeft: isUser ? AppRadius.lg : Radius.zero,
              bottomRight: isUser ? Radius.zero : AppRadius.lg,
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isError)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, color: AppColors.error, size: 16),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        message.content,
                        style: AppTextStyles.body.copyWith(color: AppColors.error),
                      ),
                    ),
                  ],
                )
              else if (isUser)
                SelectableText(
                  message.content,
                  style: AppTextStyles.body.copyWith(color: Colors.white),
                )
              else
                MarkdownBody(
                  data: message.content,
                  selectable: true,
                  styleSheet: MarkdownStyleSheet(
                    p: AppTextStyles.body.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                DateFormat('hh:mm a').format(message.timestamp),
                style: AppTextStyles.caption.copyWith(
                  color: isUser
                      ? Colors.white.withAlpha(160)
                      : theme.colorScheme.onSurface.withAlpha(120),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 200.ms)
        .slideY(begin: 0.05, duration: 200.ms, curve: Curves.easeOut);
  }
}
