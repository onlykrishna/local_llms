import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/pdf_chat_controller.dart';

class PdfListPanel extends GetView<PdfChatController> {
  const PdfListPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Obx(() => Text(
                'Your PDFs (${controller.documents.length})',
                style: theme.textTheme.titleMedium,
              )),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('Add'),
                onPressed: controller.pickAndUploadPdf,
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                label: const Text('Purge'),
                onPressed: controller.purgeAllData,
                style: TextButton.styleFrom(foregroundColor: colorScheme.error),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Obx(() {
            if (controller.isLoadingDocs.value) {
              return const Center(child: CircularProgressIndicator());
            }

            if (controller.documents.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.folder_open_outlined,
                      size: 48,
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 16),
                    const Text('No PDFs uploaded yet'),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: controller.pickAndUploadPdf,
                      child: const Text('Upload your first PDF'),
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              itemCount: controller.documents.length,
              itemBuilder: (context, index) {
                final doc = controller.documents[index];
                final isSelected =
                    controller.selectedDocIds.contains(doc.id);

                return ListTile(
                  leading: Icon(
                    Icons.picture_as_pdf_outlined,
                    color: isSelected
                        ? colorScheme.error
                        : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                  title: Text(
                    doc.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${doc.pageCount} pages · ${doc.chunkCount} chunks',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Re-index button — replaces chunks with new model
                      IconButton(
                        icon: Icon(
                          Icons.refresh_outlined,
                          size: 18,
                          color: colorScheme.primary,
                        ),
                        tooltip: 'Re-index with current embedding model',
                        onPressed: () => controller.reIndexDocument(doc),
                      ),
                      // Delete button
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Delete PDF',
                        onPressed: () {
                          Get.defaultDialog(
                            title: 'Delete PDF',
                            middleText:
                                'Are you sure you want to remove "${doc.fileName}"? '
                                'This cannot be undone.',
                            textConfirm: 'Delete',
                            textCancel: 'Cancel',
                            confirmTextColor: colorScheme.onError,
                            buttonColor: colorScheme.error,
                            onConfirm: () {
                              controller.deleteDocument(doc);
                              Get.back();
                            },
                          );
                        },
                      ),
                    ],
                  ),
                  tileColor: isSelected
                      ? colorScheme.primaryContainer.withValues(alpha: 0.3)
                      : null,
                  onTap: () => controller.toggleDocSelection(doc.id),
                );
              },
            );
          }),
        ),
      ],
    );
  }
}
