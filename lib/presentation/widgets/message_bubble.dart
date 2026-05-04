import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/source_citation_service.dart';
import 'package:get/get.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool animate;

  const MessageBubble({
    super.key,
    required this.message,
    this.animate = false,
  });

  String _cleanAnswerText(String raw) {
    String result = raw;
    
    // 1. Strip citation markers [1], [2]
    result = result.replaceAll(RegExp(r'\[\d+\]'), '');
    
    // 2. Strip legacy citation footer (divider and [N] source, p.X lines)
    // First, remove the divider and everything after it if it looks like the legacy footer
    if (result.contains('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')) {
      result = result.split('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')[0];
    }

    // 3. Strip standalone legacy citation lines just in case
    result = result.replaceAll(RegExp(r'\[\d+\]\s+.*?, p\.\d+'), '');

    // 4. Strip horizontal rules
    result = result.replaceAll(RegExp(r'[-━─]{3,}'), '');
    
    // 5. Strip leaked INSTRUCTION/CONTEXT prompts
    result = result.replaceAll(
        RegExp(r'INSTRUCTION:.*', caseSensitive: false), '');
    result = result.replaceAll(
        RegExp(r'CONTEXT:.*', caseSensitive: false), '');
    
    // 6. Collapse excess newlines
    result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    
    return result.trim();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMe = message.isUser;
    final content = isMe ? message.content : _cleanAnswerText(message.content);
    
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
                            if (!isMe) ...[
                              if (message.isFromKb ?? false)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2ECC71).withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: const Color(0xFF2ECC71).withOpacity(0.4)),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.verified_rounded, size: 10, color: Color(0xFF2ECC71)),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Verified Ground Truth',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF2ECC71),
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else if (message.isSynthesized ?? false)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: theme.colorScheme.primary.withOpacity(0.2)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.auto_awesome, size: 10, color: theme.colorScheme.primary),
                                      const SizedBox(width: 4),
                                      Text(
                                        'AI Synthesized',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: theme.colorScheme.primary,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                            MarkdownBody(
                              data: content,
                              styleSheet: MarkdownStyleSheet(
                                p: TextStyle(
                                  color: isMe ? Colors.white : theme.colorScheme.onSurface,
                                  fontSize: 15,
                                  height: 1.6,
                                ),
                                strong: TextStyle(
                                  color: isMe ? Colors.white : theme.colorScheme.onSurface,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
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
