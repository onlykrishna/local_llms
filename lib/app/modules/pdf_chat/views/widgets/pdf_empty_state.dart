import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/pdf_chat_controller.dart';

class PdfEmptyState extends GetView<PdfChatController> {
  const PdfEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final suggestions = [
      "Summarise this document",
      "What are the key findings?",
      "List the main topics covered",
    ];

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.auto_stories_outlined,
              size: 72,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              "Ask about your PDFs",
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              "Upload PDFs using the panel on the left, "
              "then ask any question about their content.",
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: suggestions.map((text) {
                return ActionChip(
                  label: Text(text),
                  onPressed: () => controller.sendQuestion(text),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
