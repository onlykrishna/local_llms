import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:get/get.dart';
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe) _buildAvatar(theme),
              const SizedBox(width: 8),
              Flexible(
                child: GestureDetector(
                  onLongPress: () => _copyToClipboard(context, message.content),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: isMe ? _userGradient() : null,
                      color: isMe ? null : theme.colorScheme.surfaceVariant.withOpacity(0.4),
                      borderRadius: _bubbleBorderRadius(isMe),
                      boxShadow: isMe ? [
                        BoxShadow(
                          color: Colors.blue.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(2, 4),
                        )
                      ] : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MarkdownBody(
                          data: message.content,
                          styleSheet: MarkdownStyleSheet(
                            p: TextStyle(
                              color: isMe ? Colors.white : theme.textTheme.bodyLarge?.color,
                              fontSize: 15,
                              height: 1.4,
                            ),
                            code: TextStyle(
                              backgroundColor: Colors.black.withOpacity(0.05),
                              fontFamily: 'monospace',
                              fontSize: 13,
                              color: isMe ? Colors.white70 : Colors.tealAccent.shade400,
                            ),
                            codeblockDecoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('hh:mm a').format(message.timestamp),
                          style: TextStyle(
                            fontSize: 10,
                            color: isMe ? Colors.white70 : theme.hintColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (isMe) _buildAvatar(theme),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(ThemeData theme) {
    return CircleAvatar(
      radius: 16,
      backgroundColor: message.isUser ? theme.primaryColor : Colors.teal.shade700,
      child: Icon(
        message.isUser ? Icons.person : Icons.auto_awesome,
        size: 16,
        color: Colors.white,
      ),
    );
  }

  LinearGradient _userGradient() {
    return const LinearGradient(
      colors: [Color(0xFF4A90E2), Color(0xFF357ABD)],
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
      const SnackBar(content: Text('Message copied!'), duration: Duration(seconds: 1)),
    );
  }
}
