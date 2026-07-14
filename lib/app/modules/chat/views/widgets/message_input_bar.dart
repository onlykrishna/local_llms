import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../../controllers/chat_controller.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/services/voice_service.dart';
import '../../../../core/services/api_provider_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../routes/app_pages.dart';

/// Attachment type passed to [onAttach] so each screen can handle it appropriately.
enum AttachmentType { camera, photos, files, liveScan, liveVision }

class MessageInputBar extends StatefulWidget {
  final RxBool isTyping;
  final Function(String text, {String? attachmentPath}) onSend;

  /// Called when the user picks an attachment.
  /// Nullable — screens that don't handle attachments can pass null.
  final Function(String filePath, AttachmentType type)? onAttach;

  /// Called by live voice mode to send a message and get the reply.
  /// Returns the assistant reply as a `Future<String>` so LiveVoiceController
  /// can speak it without guessing messages.last.
  final Future<String> Function(String text)? onVoiceSend;

  final ChatController? chatController;

  const MessageInputBar({
    super.key,
    required this.isTyping,
    required this.onSend,
    this.onAttach,
    this.onVoiceSend,
    this.chatController,
  });

  @override
  State<MessageInputBar> createState() => _MessageInputBarState();
}

class _MessageInputBarState extends State<MessageInputBar> {
  final TextEditingController _textController = TextEditingController();
  bool _hasText = false;

  String? _draftAttachmentPath;

  @override
  void initState() {
    super.initState();
    _textController.addListener(() {
      final hasText = _textController.text.trim().isNotEmpty;
      if (hasText != _hasText) setState(() => _hasText = hasText);
    });

    if (widget.chatController != null) {
      widget.chatController!.onAppendTextCallback = (text) {
        final currentText = _textController.text;
        final separator = currentText.isEmpty || currentText.endsWith(' ') ? '' : ' ';
        _textController.text = '$currentText$separator$text';
        _textController.selection = TextSelection.fromPosition(
          TextPosition(offset: _textController.text.length),
        );
      };
    }
  }

  @override
  void dispose() {
    if (widget.chatController != null) {
      widget.chatController!.onAppendTextCallback = null;
    }
    _textController.dispose();
    super.dispose();
  }

  // ── Send ─────────────────────────────────────────────────

  void _handleSend() {
    final text = _textController.text.trim();
    final hasAttachment = _draftAttachmentPath != null ||
        (widget.chatController != null && widget.chatController!.attachedImagePath.value != null) ||
        (widget.chatController != null && widget.chatController!.attachedPdfName.value.isNotEmpty);

    if ((text.isNotEmpty || hasAttachment) && !widget.isTyping.value) {
      HapticFeedback.lightImpact();

      // 1. Stop any active STT session immediately
      //    (prevents late onResult callbacks from refilling the field)
      try {
        Get.find<VoiceService>().stopListening();
      } catch (_) {}

      // 2. Clear the field FIRST, before triggering any state change
      _textController.clear();

      // 3. Then send — response may trigger a rebuild, but field is already empty
      widget.onSend(text, attachmentPath: _draftAttachmentPath);

      setState(() {
        _draftAttachmentPath = null;
      });
      if (widget.chatController != null) {
        widget.chatController!.attachedImagePath.value = null;
        widget.chatController!.attachedImageBase64.value = null;
        widget.chatController!.attachedImageMime.value = null;
        widget.chatController!.attachedPdfText.value = '';
        widget.chatController!.attachedPdfName.value = '';
      }
    }
  }

  // ── Attachment menu ───────────────────────────────────────

  void _showAttachmentSheet() {
    HapticFeedback.mediumImpact();
    Get.bottomSheet(
      _AttachmentSheet(onSelected: _handleAttachment),
      backgroundColor: AppColors.cardLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: AppRadius.lg,
          topRight: AppRadius.lg,
        ),
      ),
      isScrollControlled: true,
    );
  }

  Future<void> _handleAttachment(AttachmentType type) async {
    Get.back(); // close sheet first
    final analytics = Get.find<AnalyticsService>();

    switch (type) {
      case AttachmentType.liveScan:
        analytics.logAttachmentUsed('live_scan');
        widget.onAttach?.call('', AttachmentType.liveScan);
        break;

      case AttachmentType.liveVision:
        analytics.logAttachmentUsed('live_vision');
        widget.onAttach?.call('', AttachmentType.liveVision);
        break;

      case AttachmentType.camera:
        try {
          final picker = ImagePicker();
          final image = await picker.pickImage(source: ImageSource.camera);
          if (image != null) {
            setState(() {
              _draftAttachmentPath = image.path;
            });
            analytics.logAttachmentUsed('camera');
            widget.onAttach?.call(image.path, AttachmentType.camera);
          }
        } catch (e) {
          Get.snackbar('Camera Error', 'Could not open camera: $e',
              snackPosition: SnackPosition.BOTTOM);
        }
        break;

      case AttachmentType.photos:
        try {
          final picker = ImagePicker();
          final image = await picker.pickImage(source: ImageSource.gallery);
          if (image != null) {
            setState(() {
              _draftAttachmentPath = image.path;
            });
            analytics.logAttachmentUsed('photos');
            widget.onAttach?.call(image.path, AttachmentType.photos);
          }
        } catch (e) {
          Get.snackbar('Gallery Error', 'Could not open photos: $e',
              snackPosition: SnackPosition.BOTTOM);
        }
        break;

      case AttachmentType.files:
        if (widget.chatController != null) {
          try {
            final result = await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: ['pdf'],
            );
            if (result != null && result.files.single.path != null) {
              final path = result.files.single.path!;
              widget.onAttach?.call(path, AttachmentType.files);
            }
          } catch (e) {
            Get.snackbar('File Error', 'Could not pick file: $e',
                snackPosition: SnackPosition.BOTTOM);
          }
        } else {
          // Delegates to the onAttach callback — PdfChatScreen will trigger its
          // existing pickAndUploadPdf() pipeline.
          widget.onAttach?.call('', AttachmentType.files);
        }
        analytics.logAttachmentUsed('files');
        break;
    }
  }

  // ── Voice ─────────────────────────────────────────────────

  Future<void> _handleMicTap() async {
    final apiService = Get.find<ApiProviderService>();
    if (!apiService.isReady) {
      HapticFeedback.heavyImpact();
      Get.snackbar(
        'Error',
        apiService.readinessError ?? 'Provider not configured.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: AppColors.error.withAlpha(200),
        colorText: Colors.white,
      );
      return;
    }

    final voice = Get.find<VoiceService>();
    final analytics = Get.find<AnalyticsService>();

    if (voice.isListening.value) {
      await voice.stopListening();
      return;
    }

    HapticFeedback.lightImpact();
    analytics.logVoiceInputUsed('stt');

    await voice.startListening(
      onResult: (finalText) {
        if (finalText.trim().isEmpty) return;
        _textController.text = finalText;
        _textController.selection = TextSelection.fromPosition(
          TextPosition(offset: _textController.text.length),
        );
        setState(() => _hasText = true);
      },
      onPartial: (partial) {
        _textController.text = partial;
        _textController.selection = TextSelection.fromPosition(
          TextPosition(offset: _textController.text.length),
        );
        setState(() => _hasText = partial.trim().isNotEmpty);
      },
    );
  }

  void _handleMicLongPress() {
    final apiService = Get.find<ApiProviderService>();
    if (!apiService.isReady) {
      HapticFeedback.heavyImpact();
      Get.snackbar(
        'Error',
        apiService.readinessError ?? 'Provider not configured.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: AppColors.error.withAlpha(200),
        colorText: Colors.white,
      );
      return;
    }

    HapticFeedback.heavyImpact();
    final analytics = Get.find<AnalyticsService>();
    analytics.logVoiceInputUsed('live');

    Get.toNamed(
      AppRoutes.LIVE_VOICE,
      arguments: {
        // Pass the typed Future<String> returning callback so LiveVoiceController
        // gets the reply directly without reading messages.last
        'onVoiceSend': widget.onVoiceSend,
      },
    );
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Listening indicator ────────────────────────
            Obx(() {
              final voice = Get.find<VoiceService>();
              if (!voice.isListening.value) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withAlpha(20),
                  borderRadius: const BorderRadius.all(AppRadius.full),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _PulsingDot(),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      'Listening...',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )
                  .animate()
                  .fadeIn(duration: 200.ms)
                  .slideY(begin: 0.3, duration: 200.ms);
            }),

            // Image chip
            Builder(builder: (context) {
              ChatController? ctrl;
              try { ctrl = Get.find<ChatController>(); } catch (_) {}
              if (ctrl == null) return const SizedBox.shrink();
              return Obx(() {
                final path = ctrl!.attachedImagePath.value;
                if (path == null) return const SizedBox.shrink();
                return Container(
                  margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.all(AppRadius.md),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    ClipRRect(
                      borderRadius: BorderRadius.all(AppRadius.sm),
                      child: Image.file(File(path),
                          width: 44, height: 44, fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.image, size: 44)),
                    ),
                    const SizedBox(width: 8),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Image attached',
                          style: AppTextStyles.caption
                              .copyWith(fontWeight: FontWeight.w600)),
                      Text('Will be sent with your message',
                          style: AppTextStyles.label
                              .copyWith(color: Colors.grey)),
                    ]),
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        ctrl!.attachedImageBase64.value = null;
                        ctrl.attachedImagePath.value = null;
                        ctrl.attachedImageMime.value = null;
                      },
                      child: const Icon(Icons.close, size: 18),
                    ),
                  ]),
                );
              });
            }),

            // PDF chip
            Builder(builder: (context) {
              ChatController? ctrl;
              try { ctrl = Get.find<ChatController>(); } catch (_) {}
              if (ctrl == null) return const SizedBox.shrink();
              return Obx(() {
                final name = ctrl!.attachedPdfName.value;
                if (name.isEmpty) return const SizedBox.shrink();
                return Container(
                  margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.all(AppRadius.md),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.picture_as_pdf, color: Colors.red, size: 22),
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.caption
                                  .copyWith(fontWeight: FontWeight.w600)),
                          Text('PDF context attached',
                              style: AppTextStyles.label
                                  .copyWith(color: Colors.grey)),
                        ],
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        ctrl!.attachedPdfText.value = '';
                        ctrl.attachedPdfName.value = '';
                      },
                      child: const Icon(Icons.close, size: 18),
                    ),
                  ]),
                );
              });
            }),

            // ── Input row ──────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // "+" attachment button
                _AttachButton(onTap: _showAttachmentSheet),
                const SizedBox(width: AppSpacing.xs),

                // Text field
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withAlpha(120),
                      borderRadius: const BorderRadius.all(AppRadius.xl),
                    ),
                    child: TextField(
                      controller: _textController,
                      maxLines: 5,
                      minLines: 1,
                      textInputAction: TextInputAction.newline,
                      style: AppTextStyles.body,
                      decoration: InputDecoration(
                        hintText: 'Ask anything...',
                        hintStyle: AppTextStyles.body.copyWith(
                          color: theme.colorScheme.onSurface.withAlpha(100),
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm + 2,
                        ),
                      ),
                      onSubmitted: (_) => _handleSend(),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),

                // Dynamic trailing: send (has text/attachment) or mic (empty)
                Obx(() {
                  // Read widget.isTyping.value so Obx has at least one observable,
                  // preventing a GetX exception when chatController is null.
                  final _ = widget.isTyping.value;
                  
                  final hasAttachment = _draftAttachmentPath != null ||
                      (widget.chatController != null && widget.chatController!.attachedImagePath.value != null) ||
                      (widget.chatController != null && widget.chatController!.attachedPdfName.value.isNotEmpty);
                  final showSend = _hasText || hasAttachment;

                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, animation) => ScaleTransition(
                      scale: animation,
                      child: FadeTransition(opacity: animation, child: child),
                    ),
                    child: showSend
                        ? _SendButton(
                            key: const ValueKey('send'),
                            isTyping: widget.isTyping,
                            onSend: _handleSend,
                          )
                        : _MicButton(
                            key: const ValueKey('mic'),
                            onTap: _handleMicTap,
                            onLongPress: _handleMicLongPress,
                          ),
                  );
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────

class _AttachButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AttachButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.primary.withAlpha(20),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.add_rounded, color: AppColors.primary, size: 22),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  final RxBool isTyping;
  final VoidCallback onSend;

  const _SendButton({super.key, required this.isTyping, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final disabled = isTyping.value;
      return AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: disabled ? Theme.of(context).disabledColor : AppColors.primary,
          shape: BoxShape.circle,
        ),
        child: IconButton(
          icon: const Icon(Icons.send_rounded, color: Colors.white),
          onPressed: disabled ? null : onSend,
        ),
      );
    });
  }
}

class _MicButton extends StatelessWidget {
  final Future<void> Function() onTap;
  final VoidCallback onLongPress;

  const _MicButton({super.key, required this.onTap, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final voice = Get.find<VoiceService>();
      final isListening = voice.isListening.value;

      return GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isListening
                ? AppColors.primary
                : AppColors.primary.withAlpha(20),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isListening ? Icons.stop_rounded : Icons.mic_rounded,
            color: isListening ? Colors.white : AppColors.primary,
            size: 22,
          ),
        )
            .animate(target: isListening ? 1.0 : 0.0)
            .scaleXY(end: 1.08, duration: 500.ms, curve: Curves.easeInOut)
            .then()
            .scaleXY(end: 1.0, duration: 500.ms, curve: Curves.easeInOut),
      );
    });
  }
}

/// Animated pulsing dot shown in the listening indicator.
class _PulsingDot extends StatelessWidget {
  const _PulsingDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: AppColors.primary,
        shape: BoxShape.circle,
      ),
    )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .scaleXY(end: 1.5, duration: 600.ms, curve: Curves.easeInOut)
        .fade(end: 0.4, duration: 600.ms);
  }
}

// ─────────────────────────────────────────────────────────
// Attachment bottom sheet
// ─────────────────────────────────────────────────────────

class _AttachmentSheet extends StatelessWidget {
  final Function(AttachmentType) onSelected;
  const _AttachmentSheet({required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withAlpha(80),
                borderRadius: const BorderRadius.all(AppRadius.full),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          Text(
            'Add Attachment',
            style: AppTextStyles.title.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: AppSpacing.md),

          _AttachmentRow(
            icon: Icons.document_scanner_rounded,
            label: 'Live Scan',
            subtitle: 'OCR & Object Detection',
            onTap: () => onSelected(AttachmentType.liveScan),
          ),
          _AttachmentRow(
            icon: Icons.visibility_rounded,
            label: 'Live Vision',
            subtitle: 'AI ambient camera narration',
            onTap: () => onSelected(AttachmentType.liveVision),
          ),
          _AttachmentRow(
            icon: Icons.camera_alt_rounded,
            label: 'Camera',
            subtitle: 'Take a photo',
            onTap: () => onSelected(AttachmentType.camera),
          ),
          _AttachmentRow(
            icon: Icons.photo_library_rounded,
            label: 'Photos',
            subtitle: 'Choose from library',
            onTap: () => onSelected(AttachmentType.photos),
          ),
          _AttachmentRow(
            icon: Icons.insert_drive_file_rounded,
            label: 'Files',
            subtitle: 'PDF and documents',
            onTap: () => onSelected(AttachmentType.files),
            isLast: true,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}

class _AttachmentRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final bool isLast;

  const _AttachmentRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.all(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primary.withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.primary, size: 24),
            ),
            const SizedBox(width: AppSpacing.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTextStyles.title),
                Text(
                  subtitle,
                  style: AppTextStyles.caption.copyWith(
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
