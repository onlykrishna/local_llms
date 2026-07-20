import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'package:get/get.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'api_provider_service.dart';
import 'voice_service.dart';
import '../theme/app_theme.dart';

/// Service coordinating the persistent floating bubble features.
/// On Android: Controls system-wide overlay bubble + media projection.
/// On iOS/Fallback: Controls in-app stack-based draggable overlay bubble.
class FloatingBubbleService extends GetxService {
  static final GlobalKey rootBoundaryKey = GlobalKey();

  final RxBool isBubbleActive = false.obs;
  final RxBool isMuted = false.obs;
  
  // MethodChannel for native Android communication
  static const _channel = MethodChannel('adhoc.aiapp/bubble');

  OverlayEntry? _overlayEntry;
  final RxDouble _bubbleX = 100.0.obs;
  final RxDouble _bubbleY = 200.0.obs;
  final RxBool _isCardExpanded = false.obs;
  final RxString _answerText = 'Tap to analyze current screen.'.obs;
  final RxBool _isAnalyzing = false.obs;

  Uint8List? _lastCapturedBytes;
  final TextEditingController inAppQuestionController = TextEditingController();

  @override
  void onInit() {
    super.onInit();
    if (Platform.isAndroid) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onScreenshotCaptured') {
          final bytes = call.arguments as Uint8List;
          await _handleScreenshotCaptured(bytes);
        } else if (call.method == 'onCustomQuestionSubmitted') {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          final question = args['question'] as String;
          final bytes = args['bytes'] as Uint8List;
          await _handleCustomQuestionSubmitted(question, bytes);
        } else if (call.method == 'stopSpeaking') {
          final voice = Get.find<VoiceService>();
          await voice.stopSpeaking();
        } else if (call.method == 'onServiceStopped') {
          await stopBubble();
        }
      });
    }
  }

  @override
  void onClose() {
    inAppQuestionController.dispose();
    stopBubble();
    super.onClose();
  }

  // ── Public Controls ────────────────────────────────────────────────────────

  Future<void> toggleBubble() async {
    if (isBubbleActive.value) {
      await stopBubble();
    } else {
      await startBubble();
    }
  }

  Future<void> toggleMute() async {
    isMuted.value = !isMuted.value;
    if (Platform.isAndroid) {
      await _channel.invokeMethod('setMuteState', {'isMuted': isMuted.value});
    }
    if (isMuted.value) {
      final voice = Get.find<VoiceService>();
      await voice.stopSpeaking();
    }
  }

  Future<void> startBubble() async {
    if (isBubbleActive.value) return;

    if (Platform.isAndroid) {
      // ── Android System-wide Bubble ──
      try {
        final hasPermission = await _channel.invokeMethod<bool>('checkOverlayPermission') ?? false;
        if (!hasPermission) {
          final rationaleApproved = await _showOverlayPermissionRationale();
          if (!rationaleApproved) return;
          
          await _channel.invokeMethod('requestOverlayPermission');
          return;
        }

        final success = await _channel.invokeMethod<bool>('startBubble') ?? false;
        if (success) {
          isBubbleActive.value = true;
          debugPrint('🎈 FloatingBubbleService: Native Android bubble service started.');
        }
      } catch (e) {
        Get.snackbar(
          'Error',
          'Failed to start floating bubble: $e',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.redAccent.withAlpha(200),
          colorText: Colors.white,
        );
      }
    } else {
      // ── iOS / In-App Overlay Bubble ──
      _showInAppOverlay();
      isBubbleActive.value = true;
      debugPrint('🎈 FloatingBubbleService: In-App overlay bubble started.');
    }
  }

  Future<void> stopBubble() async {
    if (!isBubbleActive.value) return;

    isBubbleActive.value = false;
    _isCardExpanded.value = false;
    _answerText.value = 'Tap to analyze current screen.';

    final voice = Get.find<VoiceService>();
    await voice.stopSpeaking();

    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('stopBubble');
      } catch (_) {}
    } else {
      _removeInAppOverlay();
    }
    
    debugPrint('🎈 FloatingBubbleService: Bubble service stopped cleanly.');
  }

  void copyAnswerToClipboard() {
    final text = _answerText.value;
    if (text.isNotEmpty &&
        !text.startsWith('Tap to analyze') &&
        !text.startsWith('Analyzing') &&
        !text.startsWith('Thinking')) {
      Clipboard.setData(ClipboardData(text: text));
      Get.snackbar(
        'Copied',
        'Answer copied to clipboard',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.black87,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
      );
    }
  }

  // ── Screenshot Capture & API pipeline ──────────────────────────────────────

  Future<void> _handleScreenshotCaptured(Uint8List jpegBytes) async {
    _lastCapturedBytes = jpegBytes;
    if (!isBubbleActive.value) return;

    _isAnalyzing.value = true;
    _answerText.value = 'Analyzing screen context...';
    
    if (Platform.isAndroid) {
      await _channel.invokeMethod('updateAnswer', {'text': 'Analyzing screen context...'});
    } else {
      _isCardExpanded.value = true;
    }

    try {
      final base64Image = base64Encode(jpegBytes);
      final api = Get.find<ApiProviderService>();
      final voice = Get.find<VoiceService>();

      final prompt = 'Analyze this screen. If it contains a readable question, exam paper, '
          'math problem, or worksheet task, solve and output the actual answer directly and concisely. '
          'Otherwise, explain or describe the screen content.';
      
      final systemInstruction = 'You are a helpful visual assistant. '
          'Answer the user\'s screen query directly based on the visible screen pixels. '
          'Be concise. Do not describe the existence of text, solve/answer it directly. '
          'Keep output to 1-2 natural sentences, no markdown, no bullet points.';

      final reply = await api.sendVisionRequest(
        base64Image: base64Image,
        prompt: prompt,
        systemInstruction: systemInstruction,
        prioritizeGroq: true,
        timeout: const Duration(seconds: 8),
      );

      // Guard: Verify bubble is still active after API turnaround
      if (!isBubbleActive.value) {
        debugPrint('🎈 FloatingBubbleService: Service stopped while vision request was in-flight. Discarding.');
        return;
      }

      final resultText = reply.trim().isNotEmpty ? reply.trim() : 'No response from AI.';
      _answerText.value = resultText;

      if (Platform.isAndroid) {
        await _channel.invokeMethod('updateAnswer', {'text': resultText});
      }

      bool currentMute = isMuted.value;
      if (Platform.isAndroid) {
        currentMute = await _channel.invokeMethod<bool>('getMuteState') ?? currentMute;
      }

      if (!currentMute && isBubbleActive.value) {
        await voice.speak(resultText);
      }

    } catch (e) {
      if (!isBubbleActive.value) return;
      final errorText = 'Failed to analyze: $e';
      _answerText.value = errorText;
      if (Platform.isAndroid) {
        await _channel.invokeMethod('updateAnswer', {'text': errorText});
      }
    } finally {
      _isAnalyzing.value = false;
    }
  }

  Future<void> _handleCustomQuestionSubmitted(String question, Uint8List jpegBytes) async {
    _lastCapturedBytes = jpegBytes;
    if (!isBubbleActive.value) return;

    _isAnalyzing.value = true;
    _answerText.value = 'Thinking...';

    if (Platform.isAndroid) {
      await _channel.invokeMethod('updateAnswer', {'text': 'Thinking...'});
    } else {
      _isCardExpanded.value = true;
    }

    try {
      final base64Image = base64Encode(jpegBytes);
      final api = Get.find<ApiProviderService>();
      final voice = Get.find<VoiceService>();

      final systemInstruction = 'You are a helpful visual assistant looking through the user\'s screen. '
          'Answer the user\'s question directly using the visible screen image as context. '
          'Keep output to 1-3 natural conversational sentences. Do not use bullet points or markdown.';

      final reply = await api.sendVisionRequest(
        base64Image: base64Image,
        prompt: question,
        systemInstruction: systemInstruction,
        prioritizeGroq: true,
        timeout: const Duration(seconds: 8),
      );

      // Guard: Verify bubble is still active after API turnaround
      if (!isBubbleActive.value) {
        debugPrint('🎈 FloatingBubbleService: Service stopped while custom question request was in-flight. Discarding.');
        return;
      }

      final resultText = reply.trim().isNotEmpty ? reply.trim() : 'No response from AI.';
      _answerText.value = resultText;

      if (Platform.isAndroid) {
        await _channel.invokeMethod('updateAnswer', {'text': resultText});
      }

      bool currentMute = isMuted.value;
      if (Platform.isAndroid) {
        currentMute = await _channel.invokeMethod<bool>('getMuteState') ?? currentMute;
      }

      if (!currentMute && isBubbleActive.value) {
        await voice.speak(resultText);
      }

    } catch (e) {
      if (!isBubbleActive.value) return;
      final errorText = 'Failed to analyze: $e';
      _answerText.value = errorText;
      if (Platform.isAndroid) {
        await _channel.invokeMethod('updateAnswer', {'text': errorText});
      }
    } finally {
      _isAnalyzing.value = false;
    }
  }

  // ── iOS & In-App Overlay UI ────────────────────────────────────────────────

  void _showInAppOverlay() {
    final context = Get.overlayContext;
    if (context == null) return;

    _overlayEntry = OverlayEntry(
      builder: (context) {
        final screenWidth = MediaQuery.of(context).size.width;
        final screenHeight = MediaQuery.of(context).size.height;

        return Stack(
          children: [
            // ── 1. The Compound Container (Card + Bubble unit) ──
            Obx(() => Positioned(
              left: _bubbleX.value,
              top: _bubbleY.value,
              child: SizedBox(
                width: 280,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Draggable Bubble Button
                    GestureDetector(
                      onPanUpdate: (details) {
                        _bubbleX.value = (_bubbleX.value + details.delta.dx)
                            .clamp(0.0, screenWidth - 280.0);
                        _bubbleY.value = (_bubbleY.value + details.delta.dy)
                            .clamp(44.0, screenHeight - 200.0);
                      },
                      onTap: () {
                        if (_isCardExpanded.value) {
                          _handleInAppScreenshot();
                        } else {
                          _isCardExpanded.value = true;
                          _handleInAppScreenshot();
                        }
                      },
                      onLongPress: stopBubble,
                      child: Material(
                        elevation: 10,
                        shape: const CircleBorder(),
                        color: AppColors.primary,
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                          ),
                          child: Obx(() => Icon(
                            _isAnalyzing.value 
                                ? Icons.hourglass_empty_rounded 
                                : Icons.visibility_rounded, 
                            color: Colors.white, 
                            size: 24,
                          )),
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Expandable Answer Card
                    Obx(() {
                      if (!_isCardExpanded.value) return const SizedBox.shrink();
                      return Material(
                        color: Colors.transparent,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xE61A1A2E),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white24),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black54,
                                blurRadius: 16,
                                offset: Offset(0, 8),
                              )
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'SCREEN ANSWER',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Copy Answer Icon
                                      GestureDetector(
                                        onTap: copyAnswerToClipboard,
                                        child: const Icon(Icons.copy_rounded, color: Colors.white70, size: 16),
                                      ),
                                      const SizedBox(width: 12),
                                      // Mute Toggle Icon
                                      Obx(() => GestureDetector(
                                        onTap: toggleMute,
                                        child: Icon(
                                          isMuted.value
                                              ? Icons.volume_off_rounded
                                              : Icons.volume_up_rounded,
                                          color: isMuted.value ? Colors.white38 : Colors.white70,
                                          size: 18,
                                        ),
                                      )),
                                      const SizedBox(width: 12),
                                      // Collapse Card Icon (X) — collapses card, keeps service active
                                      GestureDetector(
                                        onTap: () => _isCardExpanded.value = false,
                                        child: const Icon(Icons.close, color: Colors.redAccent, size: 18),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const Divider(color: Colors.white24, height: 16),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 120),
                                child: SingleChildScrollView(
                                  child: Obx(() => Text(
                                    _answerText.value,
                                    style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
                                  )),
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Question Input Row
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: inAppQuestionController,
                                      style: const TextStyle(color: Colors.white, fontSize: 12),
                                      decoration: InputDecoration(
                                        hintText: 'Ask a question...',
                                        hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                                        isDense: true,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        filled: true,
                                        fillColor: Colors.white12,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          borderSide: BorderSide.none,
                                        ),
                                      ),
                                      onSubmitted: (text) => _submitInAppQuestion(text),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  ElevatedButton(
                                    onPressed: () => _submitInAppQuestion(inAppQuestionController.text),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    child: const Text('Ask', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ).animate().fadeIn(duration: 200.ms).scale(begin: const Offset(0.9, 0.9));
                    }),
                  ],
                ),
              ),
            )),
          ],
        );
      },
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _submitInAppQuestion(String text) {
    final question = text.trim();
    if (question.isEmpty) return;
    inAppQuestionController.clear();

    if (_lastCapturedBytes != null) {
      _handleCustomQuestionSubmitted(question, _lastCapturedBytes!);
    } else {
      _handleInAppScreenshot();
    }
  }

  void _removeInAppOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  Future<void> _handleInAppScreenshot() async {
    if (_isAnalyzing.value) return;
    
    try {
      final boundary = rootBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        _answerText.value = 'Failed to identify root widget. Try restarting app.';
        _isCardExpanded.value = true;
        return;
      }

      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        _answerText.value = 'Failed to extract pixel bytes.';
        _isCardExpanded.value = true;
        return;
      }
      
      final pngBytes = byteData.buffer.asUint8List();
      _lastCapturedBytes = pngBytes;
      
      await _handleScreenshotCaptured(pngBytes);

    } catch (e) {
      _answerText.value = 'Screenshot capture failed: $e';
      _isCardExpanded.value = true;
    }
  }

  // ── Overlay Rationale Dialog (Android Play Store compliance) ───────────────

  Future<bool> _showOverlayPermissionRationale() async {
    final completer = Completer<bool>();
    Get.dialog(
      AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.visibility_rounded, color: AppColors.primary),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Overlay Permission Needed',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: const Text(
          'To show the floating answer bubble over other applications, '
          'this app requires permission to display over other apps.\n\n'
          'Tapping "Grant" will redirect you to Android System Settings where you must check '
          '"Allow display over other apps" for this application.',
          style: TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Get.back();
              completer.complete(false);
            },
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Get.back();
              completer.complete(true);
            },
            child: const Text('Grant'),
          ),
        ],
      ),
      barrierDismissible: false,
    );
    return completer.future;
  }
}
