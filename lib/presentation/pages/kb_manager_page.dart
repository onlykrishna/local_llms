import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import '../../domain/document_ingestion_service.dart';
import '../../domain/kb_domain.dart';
import '../../data/source_document.dart';
import '../../data/document_chunk.dart';
import '../../objectbox.g.dart';

class KbManagerController extends GetxController {
  final DocumentIngestionService ingestionService = Get.find();
  final Store store;
  late final Box<SourceDocument> docBox;

  final Rx<KbDomain> selectedDomain = KbDomain.health.obs;
  final RxList<SourceDocument> documents = <SourceDocument>[].obs;
  final RxBool isIngesting = false.obs;

  KbManagerController() : store = Get.find() {
    docBox = store.box<SourceDocument>();
  }

  @override
  void onInit() {
    super.onInit();
    loadDocuments();
  }

  void loadDocuments() {
    final query = docBox.query(SourceDocument_.domain.equals(selectedDomain.value.name))
        .order(SourceDocument_.uploadedAt, flags: Order.descending)
        .build();
    documents.value = query.find();
    query.close();
  }

  void changeDomain(KbDomain domain) {
    selectedDomain.value = domain;
    loadDocuments();
  }

  Future<void> pickAndIngestPdf() async {
    if (isIngesting.value) return; // Guard against multiple clicks
    
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
    } catch (e) {
      if (e.toString().contains('already_active')) {
         Get.snackbar('Picker Busy', 'Please wait for the current picker to close');
      }
      return;
    }

    if (result != null && result.files.single.path != null) {
      File file = File(result.files.single.path!);
      isIngesting.value = true;
      try {
        await ingestionService.ingestDocument(file, selectedDomain.value);
        Get.snackbar('Success', 'Document ingested successfully');
      } catch (e) {
        Get.snackbar('Error', 'Failed to ingest document: $e', backgroundColor: Colors.redAccent, colorText: Colors.white);
      } finally {
        isIngesting.value = false;
        loadDocuments();
      }
    }
  }

  void deleteDocument(SourceDocument doc) {
    // Note: To be fully correct, we should also delete chunks from chunkBox.
    // Since chunkBox has a relation, ObjectBox handles this if configured,
    // otherwise manual deletion:
    final chunkBox = store.box<DocumentChunk>();
    final query = chunkBox.query(DocumentChunk_.sourceDocId.equals(doc.id)).build();
    final chunkIds = query.findIds();
    query.close();
    chunkBox.removeMany(chunkIds);

    docBox.remove(doc.id);
    loadDocuments();
  }
}

class KbManagerPage extends StatelessWidget {
  const KbManagerPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(KbManagerController());
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Knowledge Base'),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildDomainSelector(controller, theme),
          const Divider(height: 1),
          Obx(() {
            if (controller.isIngesting.value) {
              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Text('Ingesting Document...'),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: controller.ingestionService.ingestionProgress.value,
                    ),
                  ],
                ),
              );
            }
            return const SizedBox.shrink();
          }),
          Expanded(
            child: Obx(() {
              if (controller.documents.isEmpty) {
                return Center(
                  child: Text('No documents in this domain.', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                );
              }
              return ListView.builder(
                itemCount: controller.documents.length,
                itemBuilder: (context, index) {
                  final doc = controller.documents[index];
                  return ListTile(
                    leading: const Icon(Icons.picture_as_pdf, color: Colors.redAccent),
                    title: Text(doc.fileName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: Text('${doc.pageCount} pages • ${doc.chunkCount} chunks • ${DateFormat('MMM dd, yyyy').format(doc.uploadedAt)}', style: const TextStyle(fontSize: 12)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      onPressed: () => controller.deleteDocument(doc),
                    ),
                  );
                },
              );
            }),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: controller.isIngesting.value ? null : controller.pickAndIngestPdf,
        icon: const Icon(Icons.add),
        label: const Text('Add PDF'),
      ),
    );
  }

  Widget _buildDomainSelector(KbManagerController controller, ThemeData theme) {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: KbDomain.values.length,
        itemBuilder: (context, index) {
          final domain = KbDomain.values[index];
          return Obx(() {
            final isSelected = controller.selectedDomain.value == domain;
            return Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: ChoiceChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SvgPicture.asset(
                      domain.icon,
                      width: 16,
                      height: 16,
                      colorFilter: ColorFilter.mode(
                        isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant,
                        BlendMode.srcIn,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(domain.label),
                  ],
                ),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) controller.changeDomain(domain);
                },
                selectedColor: theme.colorScheme.primary,
                labelStyle: TextStyle(
                  color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            );
          });
        },
      ),
    );
  }
}
