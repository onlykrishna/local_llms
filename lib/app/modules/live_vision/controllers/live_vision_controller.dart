import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image/image.dart' as img;

import '../../../core/services/voice_service.dart';
import '../services/live_vision_service.dart';

// Top-level function for compute() to avoid capturing instance state
Uint8List _compressImageIsolate(Map<String, dynamic> params) {
  final rawBytes = params['bytes'] as Uint8List;
  final targetWidth = params['targetWidth'] as int;
  final quality = params['quality'] as int;
  
  try {
    final image = img.decodeImage(rawBytes);
    if (image == null) return rawBytes;
    
    var resized = image;
    if (image.width > targetWidth) {
      resized = img.copyResize(image, width: targetWidth);
    }
    return Uint8List.fromList(img.encodeJpg(resized, quality: quality));
  } catch (_) {
    return rawBytes;
  }
}

/// Controls the Live Vision screen.
///
/// Responsibilities:
///  • Camera lifecycle (reused pattern from LiveScanController)
///  • Coordinated, sequential STT/TTS loop (prevents parallel audio focus conflicts)
///  • Manual "Test Speak" debug trigger for isolated audio verification
class LiveVisionController extends GetxController {
  // ── Services ───────────────────────────────────────────────────────────────

  late final LiveVisionService _visionSvc;
  late final VoiceService _voice;

  // ── Camera ─────────────────────────────────────────────────────────────────

  CameraController? cameraController;
  List<CameraDescription> cameras = [];
  int _activeCameraIndex = 0;

  final RxBool isCameraInitialized = false.obs;
  final RxBool isPermissionDenied = false.obs;

  // ── Interaction state ──────────────────────────────────────────────────────

  /// Whether the overall live-vision session is running.
  final RxBool isRunning = false.obs;

  /// Whether the STT is currently listening for user speech.
  final RxBool isListening = false.obs;

  /// Whether an LLM vision call is in-flight.
  RxBool get isFetching => _visionSvc.isFetching;

  /// Whether TTS is currently speaking.
  RxBool get isSpeaking => _voice.isSpeaking;

  /// Latest narration text (ambient or Q&A reply).
  RxString get latestNarration => _visionSvc.latestNarration;

  /// Live partial transcript from STT.
  final RxString liveTranscript = ''.obs;

  /// Current status label shown in the UI status pill.
  final RxString statusText = 'Tap to start...'.obs;

  // ── Loop control ───────────────────────────────────────────────────────────

  bool _sttLoopActive = false;
  bool _isReleasingMic = false;

  // ── Generation counter for request cancellation ────────────────────────────
  int _latestQueryGeneration = 0;
  int _latestUserQueryGeneration = 0;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
    _visionSvc = Get.find<LiveVisionService>();
    _voice = Get.find<VoiceService>();

    // Register our frame-capture callback with the vision service
    _visionSvc.registerFrameCapture(_captureFrameAsBase64);

    _initCamera();
  }

  @override
  void onClose() {
    _stop();
    _tearDownCamera();
    super.onClose();
  }

  // ── Public controls ────────────────────────────────────────────────────────

  Future<void> toggleSession() async {
    if (isRunning.value) {
      await _stop();
    } else {
      await _start();
    }
  }

  Future<void> _start() async {
    isRunning.value = true;
    statusText.value = 'Listening for you...';
    _runSttLoop();
  }

  Future<void> _stop() async {
    _sttLoopActive = false;
    isRunning.value = false;
    isListening.value = false;
    await _voice.stopListening();
    await _voice.stopSpeaking();
    statusText.value = 'Tap to start...';
    liveTranscript.value = '';
  }

  /// Close the screen and clean up.
  Future<void> close() async {
    await _stop();
    Get.back();
  }

  // ── Isolated Test Speak Debug Trigger ──────────────────────────────────────

  Future<void> testSpeak() async {
    debugPrint('🧪 LiveVisionController [Test Speak]: Button pressed.');
    statusText.value = 'Testing audio...';
    try {
      final text = 'This is an audio playback check. If you can hear this, the Text to Speech pipeline is working perfectly.';
      debugPrint('🧪 LiveVisionController [Test Speak]: Calling voice.speak("$text")...');
      await _voice.speak(text);
      debugPrint('🧪 LiveVisionController [Test Speak]: voice.speak() finished call.');
      statusText.value = isRunning.value ? 'Listening...' : 'Tap to start...';
    } catch (e) {
      debugPrint('❌ LiveVisionController [Test Speak] error: $e');
      statusText.value = 'Test failed: $e';
    }
  }

  // ── Coordinated Loop (mirrors LiveVoiceController pattern) ─────────────────

  Future<void> _runSttLoop() async {
    _sttLoopActive = true;
    
    // Counter to track periodic intervals when user is silent
    int silenceCycles = 0;

    while (_sttLoopActive && isRunning.value) {
      try {
        // Guard: Wait if TTS is playing (shouldn't happen with sequential logic, but safe fallback)
        if (_voice.isSpeaking.value) {
          debugPrint('🎙️ LiveVisionController: Loop blocked — TTS is speaking.');
          await Future.doWhile(() async {
            await Future.delayed(const Duration(milliseconds: 200));
            return _voice.isSpeaking.value && _sttLoopActive;
          });
          if (!_sttLoopActive) break;
          await Future.delayed(const Duration(milliseconds: 600));
        }

        // ── STEP 1: LISTEN ──────────────────────────────────────────────────
        isListening.value = true;
        liveTranscript.value = '';
        statusText.value = 'Listening...';
        debugPrint('🎙️ LiveVisionController: Starting STT listening session...');

        final completer = Completer<String>();

        await _voice.startListening(
          onResult: (text) {
            if (!completer.isCompleted) {
              debugPrint('🎙️ LiveVisionController: STT final transcript: "$text"');
              completer.complete(text);
            }
          },
          onPartial: (partial) {
            liveTranscript.value = partial;
            statusText.value = partial.isNotEmpty ? partial : 'Listening...';
          },
        );

        String userText = '';
        try {
          // Listen for up to 6 seconds. If user remains silent, time out and perform ambient narration.
          userText = await completer.future.timeout(
            const Duration(seconds: 6),
          );
        } catch (_) {
          debugPrint('🎙️ LiveVisionController: Listening timeout (no speech detected).');
          userText = '';
        }

        isListening.value = false;
        if (!_sttLoopActive) break;

        // CRITICAL HANDOFF: Release the microphone recognizer fully before doing LLM or speaking.
        // This avoids audio focus lock conflicts.
        if (!_isReleasingMic) {
          _isReleasingMic = true;
          debugPrint('🎙️ LiveVisionController: Releasing STT recognizer...');
          await _voice.releaseRecognizer();
          _isReleasingMic = false;
        }
        if (!_sttLoopActive) break;

        liveTranscript.value = '';

        // Increment query generations
        _latestQueryGeneration++;
        final isUserQuery = userText.trim().isNotEmpty;
        if (isUserQuery) {
          _latestUserQueryGeneration = _latestQueryGeneration;
        }

        final currentGen = _latestQueryGeneration;
        final currentLatestUserGen = _latestUserQueryGeneration;

        // ── STEP 2: DISPATCH LLM & SPEAK ────────────────────────────────────
        if (isUserQuery) {
          // Case A: User asked a question! Prioritize this over ambient narration.
          debugPrint('🎙️ LiveVisionController: Query detected. Triggering Q&A flow...');
          
          final loopStart = DateTime.now();
          debugPrint('⏱️ [1/6] Final transcript received at ${loopStart.toLocal()}');
          
          statusText.value = 'Thinking...';
          
          // sendVisionQuery will trigger camera frame capture inside
          final reply = await _visionSvc.sendVisionQuery(
            userText.trim(),
            generation: currentGen,
            latestUserQueryGeneration: currentLatestUserGen,
          );
          
          if (!_sttLoopActive) break;

          // Check if discarded
          if (currentGen < _latestUserQueryGeneration) {
            debugPrint('⏱️ [CANCELLED] Q&A response discarded because a newer user query started.');
            continue;
          }

          if (reply.trim().isNotEmpty) {
            statusText.value = 'Speaking...';
            
            final ttsStart = DateTime.now();
            debugPrint('⏱️ [6/6] TTS speak() called at ${ttsStart.toLocal()} (LLM turnaround: ${ttsStart.difference(loopStart).inMilliseconds}ms)');
            
            await _voice.speak(reply);
            
            debugPrint('⏱️ TTS finished in ${DateTime.now().difference(ttsStart).inMilliseconds}ms');
          } else {
            debugPrint('🎙️ LiveVisionController: Q&A response was empty.');
          }
          
          // Reset silence cycles since user interacted
          silenceCycles = 0;
        } else {
          // Case B: Silence timeout. Ambiently narrate every cycle.
          silenceCycles++;
          if (silenceCycles >= 1) {
            debugPrint('🎙️ LiveVisionController: User is silent. Triggering ambient narration...');
            statusText.value = 'Observing...';
            
            final narration = await _visionSvc.triggerAmbientNarration(
              generation: currentGen,
              latestUserQueryGeneration: currentLatestUserGen,
            );
            if (!_sttLoopActive) break;

            // Check if discarded (discard ambient narration if any user query started since)
            if (currentGen < _latestUserQueryGeneration) {
              debugPrint('⏱️ [DISCARDED] Ambient narration response discarded due to active user query.');
              continue;
            }

            if (narration.trim().isNotEmpty) {
              statusText.value = 'Narrating...';
              debugPrint('🎙️ LiveVisionController: Narration response received. Invoking speak...');
              await _voice.speak(narration);
              debugPrint('🎙️ LiveVisionController: Speak call completed.');
            } else {
              debugPrint('🎙️ LiveVisionController: Narration response was empty or NO_CHANGE.');
            }
            silenceCycles = 0;
          }
        }

        // Slight pause before restarting the STT microphone to let audio focus settle
        await Future.delayed(const Duration(milliseconds: 800));

      } catch (e, st) {
        isListening.value = false;
        debugPrint('❌ LiveVisionController STT loop error: $e\n$st');
        statusText.value = 'Error — retrying in 2s';
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    isListening.value = false;
    if (isRunning.value) statusText.value = 'Listening...';
  }

  // ── Camera ─────────────────────────────────────────────────────────────────

  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (status.isPermanentlyDenied || status.isDenied) {
      isPermissionDenied.value = true;
      return;
    }
    await _startCamera();
  }

  Future<void> _startCamera({int? cameraIndex}) async {
    try {
      cameras = await availableCameras();
      if (cameras.isEmpty) throw Exception('No cameras available.');

      final idx = cameraIndex ??
          cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
      _activeCameraIndex = idx < 0 ? 0 : idx;

      final cc = CameraController(
        cameras[_activeCameraIndex],
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await cc.initialize();
      cameraController = cc;
      isCameraInitialized.value = true;
      isPermissionDenied.value = false;
    } catch (e) {
      debugPrint('❌ LiveVisionController: Camera init error: $e');
      isCameraInitialized.value = false;
    }
  }

  Future<void> _tearDownCamera() async {
    final cc = cameraController;
    cameraController = null;
    isCameraInitialized.value = false;
    if (cc != null) {
      try {
        await cc.dispose();
      } catch (_) {}
    }
  }

  Future<void> flipCamera() async {
    if (cameras.length < 2) return;
    final nextIdx = (_activeCameraIndex + 1) % cameras.length;
    isCameraInitialized.value = false;
    await _tearDownCamera();
    await Future.delayed(const Duration(milliseconds: 300));
    await _startCamera(cameraIndex: nextIdx);
  }

  Future<void> retryCamera() async {
    await _tearDownCamera();
    await _initCamera();
  }

  // ── Frame capture (used by LiveVisionService) ──────────────────────────────

  Future<String?> _captureFrameAsBase64({bool isQuery = false}) async {
    final cc = cameraController;
    if (cc == null || !cc.value.isInitialized) return null;
    try {
      final captureStart = DateTime.now();
      debugPrint('⏱️ [2/6] Frame capture started at ${captureStart.toLocal()}');
      
      final XFile file = await cc.takePicture();
      
      final captureEnd = DateTime.now();
      debugPrint('⏱️ [3/6] Frame capture complete at ${captureEnd.toLocal()} (duration: ${captureEnd.difference(captureStart).inMilliseconds}ms)');
      
      final bytes = await file.readAsBytes();
      
      // Delete temp file to avoid storage accumulation
      try { await File(file.path).delete(); } catch (_) {}

      // Asynchronous image compression via compute() to keep UI thread fluid
      final targetWidth = isQuery ? 1280 : 800; // Higher resolution for text readability
      final quality = isQuery ? 80 : 60;        // Higher quality for text readability
      
      final compressStart = DateTime.now();
      final compressedBytes = await compute(_compressImageIsolate, {
        'bytes': bytes,
        'targetWidth': targetWidth,
        'quality': quality,
      });
      final compressEnd = DateTime.now();
      debugPrint('⏱️ [4/6] Image compressed to ${compressedBytes.length} bytes (duration: ${compressEnd.difference(compressStart).inMilliseconds}ms)');
      
      final encodeStart = DateTime.now();
      final base64String = base64Encode(compressedBytes);
      final encodeEnd = DateTime.now();
      debugPrint('⏱️ [5/6] Image base64 encode complete at ${encodeEnd.toLocal()} (duration: ${encodeEnd.difference(encodeStart).inMilliseconds}ms)');

      return base64String;
    } catch (e) {
      debugPrint('❌ LiveVisionController: Frame capture error: $e');
      return null;
    }
  }
}
