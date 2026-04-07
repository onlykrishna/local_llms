import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import '../../domain/entities/chat_message.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool animate;

  const MessageBubble({
    super.key,
    required this.message,
    this.animate = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMe = message.isUser;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe) _buildAvatar(theme, isMe),
              const SizedBox(width: 8),
              Flexible(
                child: GestureDetector(
                  onLongPress: () => _copyToClipboard(context, message.content),
                  child: ClipRRect(
                    borderRadius: _bubbleBorderRadius(isMe),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          gradient: isMe ? _userGradient(theme) : null,
                          color: isMe ? null : theme.colorScheme.surfaceContainer.withOpacity(0.8),
                          borderRadius: _bubbleBorderRadius(isMe),
                          border: Border.all(
                            color: isMe 
                                ? Colors.white.withOpacity(0.1) 
                                : theme.colorScheme.outline.withOpacity(0.2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MarkdownBody(
                              data: message.content,
                              styleSheet: MarkdownStyleSheet(
                                p: TextStyle(
                                  color: isMe ? Colors.white : theme.colorScheme.onSurface,
                                  fontSize: 15,
                                  height: 1.6,
                                ),
                                code: TextStyle(
                                  backgroundColor: isMe ? Colors.black26 : theme.colorScheme.primary.withOpacity(0.1),
                                  fontFamily: 'monospace',
                                  fontSize: 13,
                                  color: isMe ? Colors.white : theme.colorScheme.primary,
                                ),
                                codeblockDecoration: BoxDecoration(
                                  color: isMe ? Colors.black38 : theme.colorScheme.surfaceContainer.withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              DateFormat('hh:mm').format(message.timestamp),
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: isMe 
                                    ? Colors.white.withOpacity(0.5) 
                                    : theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (isMe) _buildAvatar(theme, isMe),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(ThemeData theme, bool isMe) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.1),
        shape: BoxShape.circle,
        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.2)),
      ),
      child: Icon(
        isMe ? Icons.person_rounded : Icons.auto_awesome_rounded,
        size: 14,
        color: theme.colorScheme.primary,
      ),
    );
  }

  LinearGradient _userGradient(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return LinearGradient(
      colors: isDark 
        ? [const Color(0xFF5D38BB), const Color(0xFF2E1A47)] 
        : [theme.colorScheme.primary, theme.colorScheme.primary.withOpacity(0.8)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  BorderRadius _bubbleBorderRadius(bool isMe) {
    return BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(isMe ? 16 : 4),
      bottomRight: Radius.circular(isMe ? 4 : 16),
    );
  }

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Message copied to neural buffer'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 1),
      ),
    );
  }
}
