import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../pdf_chat/controllers/pdf_chat_controller.dart';
import '../../../core/services/embedding_service.dart';
import '../../../core/models/pdf_document.dart';
import '../../../core/services/storage_service.dart';
import '../../../routes/app_pages.dart';

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

class SetupScreen extends GetView<PdfChatController> {
  const SetupScreen({super.key});

  void _confirmDelete(BuildContext context, PdfDocument doc) {
    Get.dialog(
      AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          "Delete Document?",
          style: TextStyle(color: kText1, fontWeight: FontWeight.bold),
        ),
        content: Text(
          "Are you sure you want to remove \"${doc.fileName}\"? This will also delete all generated embedding chunks.",
          style: const TextStyle(color: kText2, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text("Cancel", style: TextStyle(color: kText3)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kError,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Get.back();
              controller.deleteDocument(doc);
            },
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final embeddingService = Get.find<EmbeddingService>();
    
    // Dismiss any active keyboard from login transition to prevent layout distortion
    FocusManager.instance.primaryFocus?.unfocus();

    return Scaffold(
      backgroundColor: kBg,
      resizeToAvoidBottomInset: false,
      body: Column(
        children: [
          // Elegant Header Gradient Box
          Container(
            width: double.infinity,
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 24,
              bottom: 24,
              left: 24,
              right: 24,
            ),
            decoration: const BoxDecoration(
              gradient: kGradient,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(32),
                bottomRight: Radius.circular(32),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        "Setup Knowledge Base",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Active Provider Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircleAvatar(
                            radius: 4,
                            backgroundColor: kSuccess,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            embeddingService.activeProviderName.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  "Upload and index your PDF documents to supply structural knowledge to the AI chat model.",
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),

          // Main body content
          Expanded(
            child: Obx(() {
              if (controller.isLoadingDocs.value) {
                return const Center(
                  child: CircularProgressIndicator(color: kPrimary),
                );
              }

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),

                    // Upload Progress Stream Card
                    if (controller.isUploading.value)
                      SliverToBoxAdapter(
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 20),
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: kCard,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: kBorder),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              )
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.cloud_upload_rounded, color: kPrimary),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      "Indexing PDF Document",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: kText1,
                                        fontSize: 15,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    "${(controller.uploadProgress.value * 100).toInt()}%",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: kPrimary,
                                      fontSize: 15,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: controller.uploadProgress.value,
                                  backgroundColor: kBg,
                                  color: kPrimary,
                                  minHeight: 6,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                controller.uploadStage.value.isNotEmpty
                                    ? controller.uploadStage.value
                                    : "Parsing and chunking pages...",
                                style: const TextStyle(fontSize: 12, color: kText2),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Indexed PDFs count/header
                    SliverToBoxAdapter(
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              "Indexed PDFs (${controller.documents.length})",
                              style: const TextStyle(
                                color: kText1,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: () => controller.pickAndUploadPdf(),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add_rounded, color: kPrimary, size: 18),
                                SizedBox(width: 4),
                                Text(
                                  "Add New",
                                  style: TextStyle(
                                    color: kPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SliverToBoxAdapter(child: SizedBox(height: 16)),

                    // Document List or Empty State
                    if (controller.documents.isEmpty)
                      SliverToBoxAdapter(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
                          decoration: BoxDecoration(
                            color: kCard,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: kBorder),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: kBg,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.picture_as_pdf_rounded,
                                  color: kText3,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                "No PDFs Uploaded Yet",
                                style: TextStyle(
                                  color: kText1,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                "Upload PDF knowledge files to index them for deep AI analysis and smart RAG retrieval.",
                                style: TextStyle(color: kText2, fontSize: 13, height: 1.4),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 20),
                              GestureDetector(
                                onTap: () => controller.pickAndUploadPdf(),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: kPrimary.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text(
                                    "Pick Document",
                                    style: TextStyle(
                                      color: kPrimary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final doc = controller.documents[index];
                            final num = index + 1;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: kCard,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: kBorder),
                              ),
                              child: Row(
                                children: [
                                  // Index Circle Icon
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: kBg,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(
                                        "#$num",
                                        style: const TextStyle(
                                          color: kPrimary,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),

                                  // Filename & stats
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          doc.fileName,
                                          style: const TextStyle(
                                            color: kText1,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          "${doc.pageCount} pages • ${doc.chunkCount} chunks",
                                          style: const TextStyle(
                                            color: kText2,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Delete Action
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      color: kError,
                                      size: 20,
                                    ),
                                    onPressed: () => _confirmDelete(context, doc),
                                  ),
                                ],
                              ),
                            );
                          },
                          childCount: controller.documents.length,
                        ),
                      ),

                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                ),
              );
            }),
          ),
        ],
      ),

      // Bottom Bar Navigation to Chat
      bottomNavigationBar: Container(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.of(context).padding.bottom + 16,
          top: 16,
        ),
        decoration: BoxDecoration(
          color: kCard,
          border: const Border(top: BorderSide(color: kBorder)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, -4),
            )
          ],
        ),
        child: SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: () async {
              try {
                final storage = Get.find<StorageService>();
                await storage.setBool('setupComplete', true);
              } catch (e) {
                debugPrint("⚠️ Failed to write setupComplete on button press: $e");
              }
              Get.offAllNamed(AppRoutes.CHAT);
            },
            child: Ink(
              decoration: BoxDecoration(
                gradient: kGradient,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                alignment: Alignment.center,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Start AI Chat",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
