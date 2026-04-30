import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../controllers/pdf_library_controller.dart';
import '../../data/models/pdf_document_meta.dart';

class PdfLibraryPage extends GetView<PdfLibraryController> {
  const PdfLibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = Get.put(PdfLibraryController());

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('PDF Library'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
      ),
      body: Stack(
        children: [
          // Background Gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.colorScheme.surface,
                  theme.colorScheme.surfaceContainerHighest.withOpacity(0.8),
                ],
              ),
            ),
          ),
          
          Obx(() {
            if (controller.documents.isEmpty) {
              return _buildEmptyState(theme);
            }
            
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 120, 16, 100),
              itemCount: controller.documents.length,
              itemBuilder: (context, index) {
                final doc = controller.documents[index];
                return _buildPdfCard(context, doc, theme)
                    .animate(delay: (index * 50).ms)
                    .fadeIn(duration: 400.ms)
                    .slideX(begin: 0.1, end: 0);
              },
            );
          }),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: controller.addNewPdf,
        label: const Text('Add PDF', style: TextStyle(fontWeight: FontWeight.bold)),
        icon: const Icon(Icons.add_rounded),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
      ).animate().scale(delay: 400.ms, duration: 400.ms, curve: Curves.easeOutBack),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.library_books_rounded, size: 80, color: theme.colorScheme.primary.withOpacity(0.2)),
          const SizedBox(height: 16),
          Text(
            'No PDFs found in your library',
            style: TextStyle(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add your first PDF to start indexing',
            style: TextStyle(
              color: theme.colorScheme.onSurface.withOpacity(0.4),
              fontSize: 14,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 600.ms);
  }

  Widget _buildPdfCard(BuildContext context, PdfDocumentMeta doc, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withOpacity(0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _buildFileIcon(doc, theme),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        doc.fileName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _buildStatusBadge(doc, theme),
                          const SizedBox(width: 8),
                          _buildSourceBadge(doc, theme),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Embedded: ${DateFormat('MMM dd, yyyy').format(doc.embeddedAt)} • ${doc.pageCount} Pages',
                        style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                _buildActionMenu(context, doc, controller),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFileIcon(PdfDocumentMeta doc, ThemeData theme) {
    Color iconColor;
    switch (doc.status) {
      case 'indexed': iconColor = Colors.green; break;
      case 'processing': iconColor = Colors.orange; break;
      default: iconColor = Colors.red;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: iconColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(Icons.picture_as_pdf_rounded, color: iconColor),
    );
  }

  Widget _buildStatusBadge(PdfDocumentMeta doc, ThemeData theme) {
    Color color;
    String label;
    
    switch (doc.status) {
      case 'indexed':
        color = Colors.green;
        label = 'Indexed';
        break;
      case 'processing':
        color = Colors.orange;
        label = 'Processing';
        break;
      default:
        color = Colors.red;
        label = 'Failed';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildSourceBadge(PdfDocumentMeta doc, ThemeData theme) {
    final isBundled = doc.source == 'bundled';
    final color = isBundled ? theme.colorScheme.secondary : theme.colorScheme.primary;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        isBundled ? 'Bundled' : 'Uploaded',
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildActionMenu(BuildContext context, PdfDocumentMeta doc, PdfLibraryController controller) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      onSelected: (value) {
        if (value == 'delete') {
          _showDeleteConfirm(context, doc, controller);
        } else if (value == 'reindex') {
          controller.reIndexPdf(doc.id);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'reindex',
          child: Row(
            children: [
              Icon(Icons.refresh_rounded, size: 20),
              SizedBox(width: 8),
              Text('Re-index'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded, size: 20, color: Colors.red),
              SizedBox(width: 8),
              Text('Delete', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    );
  }

  void _showDeleteConfirm(BuildContext context, PdfDocumentMeta doc, PdfLibraryController controller) {
    final theme = Theme.of(context);
    Get.dialog(
      BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: AlertDialog(
          backgroundColor: theme.colorScheme.surface.withOpacity(0.9),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Delete Document?'),
          content: Text('This will remove "${doc.fileName}" and all its embeddings from the library. This cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Get.back(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                controller.deletePdf(doc.id);
                Get.back();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
  }
}
