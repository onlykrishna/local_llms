import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:collection/collection.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../controllers/chat_controller.dart';
import 'widgets/chat_bubble.dart';
import 'widgets/typing_indicator.dart';
import 'widgets/message_input_bar.dart';
import 'package:flutter_ai_chat_app/app/core/models/ai_provider.dart';
import 'package:flutter_ai_chat_app/app/core/models/chat_message.dart';
import 'package:flutter_ai_chat_app/app/core/services/api_provider_service.dart';
import 'package:flutter_ai_chat_app/app/core/services/storage_service.dart';
import 'package:flutter_ai_chat_app/app/routes/app_pages.dart';
import 'package:flutter_ai_chat_app/app/shared/widgets/no_connection_banner.dart';

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

class ChatScreen extends GetView<ChatController> {
  ChatScreen({super.key});

  final ScrollController _scrollController = ScrollController();

  void _confirmClear(BuildContext context) {
    Get.dialog(
      AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          "Clear Conversation?",
          style: TextStyle(color: kText1, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          "Are you sure you want to clear this conversation? This will delete all messages in this active session.",
          style: TextStyle(color: kText2, fontSize: 14),
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
              controller.clearConversation();
              Get.back();
            },
            child: const Text("Clear"),
          ),
        ],
      ),
    );
  }

  void _showProviderSheet(BuildContext context) {
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(24),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Select AI Provider",
                style: TextStyle(
                  color: kText1,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Choose the model architecture powering your queries.",
                style: TextStyle(color: kText2, fontSize: 13),
              ),
              const SizedBox(height: 20),
              Obx(() {
                final isSelected = controller.activeProvider.value == AiProvider.openai;
                return InkWell(
                  onTap: () {
                    Get.find<ApiProviderService>().switchProvider(AiProvider.openai);
                    Get.back();
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? kPrimary.withValues(alpha: 0.06) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? kPrimary : kBorder,
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.auto_awesome_rounded, color: kPrimary),
                            SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "OpenAI (gpt-4o-mini)",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: kText1,
                                    fontSize: 14,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  "Highly intelligent and contextual",
                                  style: TextStyle(color: kText2, fontSize: 11),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (isSelected)
                          const Icon(Icons.check_circle_rounded, color: kPrimary),
                      ],
                    ),
                  ),
                );
              }),
              Obx(() {
                final isSelected = controller.activeProvider.value == AiProvider.groq;
                return InkWell(
                  onTap: () {
                    Get.find<ApiProviderService>().switchProvider(AiProvider.groq);
                    Get.back();
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: isSelected ? kPrimary.withValues(alpha: 0.06) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? kPrimary : kBorder,
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.bolt_rounded, color: kPrimary),
                            SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Groq (llama3-70b-8192)",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: kText1,
                                    fontSize: 14,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  "Super-fast open-source model",
                                  style: TextStyle(color: kText2, fontSize: 11),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (isSelected)
                          const Icon(Icons.check_circle_rounded, color: kPrimary),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
      isScrollControlled: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final userPhone = user?.phoneNumber ?? "Guest User";

    // Auto-scroll on new message
    ever(controller.messages, (_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    });

    // Auto-scroll when typing indicator appears/disappears
    ever(controller.isTyping, (_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    });

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: kGradient),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'AI Chatbot',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.white,
              ),
            ),
            Obx(() => Text(
              'Active: ${controller.activeProviderName}',
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.85),
                fontWeight: FontWeight.w500,
              ),
            )),
          ],
        ),
        elevation: 0,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.layers_outlined),
            tooltip: 'Select AI Provider',
            onPressed: () => _showProviderSheet(context),
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded),
            tooltip: 'Clear Conversation',
            onPressed: () => _confirmClear(context),
          ),
        ],
      ),

      // Professional Drawer
      drawer: Drawer(
        backgroundColor: kBg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drawer Header with profile card
            Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 24,
                bottom: 24,
                left: 20,
                right: 20,
              ),
              decoration: const BoxDecoration(gradient: kGradient),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Welcome Back",
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          userPhone,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Navigation links
            ListTile(
              leading: const Icon(Icons.storage_rounded, color: kPrimary),
              title: const Text(
                'Setup Knowledge Base',
                style: TextStyle(color: kText1, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('Manage & Index PDFs', style: TextStyle(fontSize: 11)),
              onTap: () {
                Get.back(); // close drawer
                Get.toNamed(AppRoutes.SETUP);
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined, color: kPrimary),
              title: const Text(
                'RAG PDF Chat',
                style: TextStyle(color: kText1, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('Query indexed documents', style: TextStyle(fontSize: 11)),
              onTap: () {
                Get.back(); // close drawer
                Get.toNamed(AppRoutes.PDF_CHAT);
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined, color: kText2),
              title: const Text(
                'Settings',
                style: TextStyle(color: kText1),
              ),
              onTap: () {
                Get.back(); // close drawer
                Get.toNamed(AppRoutes.SETTINGS);
              },
            ),

            const Spacer(),
            const Divider(color: kBorder, height: 1),

            // Clear Conversation
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: kError),
              title: const Text(
                'Clear Chat History',
                style: TextStyle(color: kError, fontWeight: FontWeight.w600),
              ),
              onTap: () {
                Get.back();
                _confirmClear(context);
              },
            ),

            // Logout Action
            ListTile(
              leading: const Icon(Icons.logout_rounded, color: kText2),
              title: const Text(
                'Logout',
                style: TextStyle(color: kText1),
              ),
              onTap: () async {
                Get.back();
                await FirebaseAuth.instance.signOut();
                await Get.find<StorageService>().clearUid();
                Get.offAllNamed(AppRoutes.PHONE_INPUT);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),

      body: Column(
        children: [
          // Connection check banner
          const NoConnectionBanner(),

          // Chat message frame
          Expanded(
            child: Obx(() {
              if (controller.isLoadingHistory.value) {
                return const Center(child: CircularProgressIndicator(color: kPrimary));
              }

              if (controller.messages.isEmpty && !controller.isTyping.value) {
                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Soft Icon card
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: kPrimary.withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 32,
                            color: kPrimary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Start a conversation',
                          style: TextStyle(
                            color: kText1,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Ask anything! I am powered by ${controller.activeProviderName} to deliver highly responsive answers.',
                          style: const TextStyle(
                            color: kText2,
                            fontSize: 13,
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              }

              final itemCount = controller.messages.length +
                  (controller.isTyping.value ? 1 : 0);

              return ListView.builder(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                itemCount: itemCount,
                itemBuilder: (context, index) {
                  if (index < controller.messages.length) {
                    return ChatBubble(message: controller.messages[index]);
                  } else {
                    return const TypingIndicator();
                  }
                },
              );
            }),
          ),

          MessageInputBar(
            chatController: controller,
            isTyping: controller.isTyping,
            onSend: (text, {attachmentPath}) =>
                controller.sendMessage(text),
            onAttach: (filePath, type) {
              controller.setAttachment(filePath, type);
            },
            onVoiceSend: (text) async {
              // Send via ChatController and return the assistant reply string
              // so LiveVoiceController can speak it without reading messages.last
              await controller.sendMessage(text, voiceMode: true);
              final lastNonError = controller.messages.reversed
                  .firstWhereOrNull((m) =>
                      m.role == MessageRole.assistant && !m.isError);
              return lastNonError?.content ?? '';
            },
          ),
        ],
      ),
    );
  }
}
