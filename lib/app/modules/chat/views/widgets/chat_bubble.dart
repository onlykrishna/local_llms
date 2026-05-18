import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/models/chat_message.dart';

const kPrimary     = Color(0xFF6C63FF);
const kPrimaryDark = Color(0xFF4B44CC);
const kBg          = Color(0xFFF8F9FE);
const kCard        = Color(0xFFFFFFFF);
const kBorder      = Color(0xFFE5E7EB);
const kText1       = Color(0xFF1A1A2E);
const kText2       = Color(0xFF6B7280);
const kText3       = Color(0xFF9CA3AF);
const kError       = Color(0xFFEF4444);
const kSuccess     = Color(0xFF10B981);

const kGradient = LinearGradient(
  colors: [Color(0xFF6C63FF), Color(0xFF4B44CC)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatBubble({super.key, required this.message});

  void _showOptions(BuildContext context) {
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: const BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: kBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.copy_outlined, color: kText1),
                title: const Text('Copy Text', style: TextStyle(color: kText1, fontWeight: FontWeight.w600)),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: message.content));
                  Get.back();
                  Get.snackbar(
                    'Copied',
                    'Message copied to clipboard',
                    snackPosition: SnackPosition.BOTTOM,
                    backgroundColor: kPrimary,
                    colorText: Colors.white,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.share_outlined, color: kText1),
                title: const Text('Share Message', style: TextStyle(color: kText1, fontWeight: FontWeight.w600)),
                onTap: () {
                  Get.back();
                  Share.share(message.content);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    final isError = message.isError;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showOptions(context),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          decoration: BoxDecoration(
            gradient: isUser && !isError ? kGradient : null,
            color: isError
                ? kError.withOpacity(0.08)
                : isUser
                    ? null
                    : kCard,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: isUser ? const Radius.circular(16) : const Radius.circular(4),
              bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(16),
            ),
            border: isUser ? null : Border.all(color: kBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              )
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isError)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded, color: kError, size: 18),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        message.content,
                        style: const TextStyle(
                          color: kError,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                )
              else if (isUser)
                SelectableText(
                  message.content,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.4,
                  ),
                )
              else
                MarkdownBody(
                  data: message.content,
                  selectable: true,
                  styleSheet: MarkdownStyleSheet(
                    p: const TextStyle(
                      color: kText1,
                      fontSize: 15,
                      height: 1.4,
                    ),
                    code: const TextStyle(
                      backgroundColor: kBg,
                      color: kPrimaryDark,
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                    codeblockDecoration: BoxDecoration(
                      color: kBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: kBorder),
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    DateFormat('hh:mm a').format(message.timestamp),
                    style: TextStyle(
                      color: isUser && !isError
                          ? Colors.white.withOpacity(0.7)
                          : kText3,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 350.ms)
        .slideY(begin: 0.15, end: 0, curve: Curves.easeOutQuad);
  }
}
