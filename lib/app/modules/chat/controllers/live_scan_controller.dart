import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../../core/services/live_scan_service.dart';
import '../controllers/chat_controller.dart';

class LiveScanController extends GetxController {
  final LiveScanService _scanService = Get.find<LiveScanService>();
  Worker? _detectionsWorker;

  CameraController? cameraController;
  List<CameraDescription> cameras = [];

  // ── Reactive States ────────────────────────────────────────────────────────

  final RxBool isCameraInitialized = false.obs;
  final RxBool isPermissionDenied = false.obs;

  /// 'ocr' | 'object'
  final RxString scanMode = 'ocr'.obs;

  /// Service lifecycle stage.
  RxString get initStatus => _scanService.initStatus;

  final RxList<String> detectedTexts = <String>[].obs;
  final RxList<DetectedObject> detectedObjects = <DetectedObject>[].obs;

  /// Last recognised text result — used for bounding box overlay.
  final Rx<RecognizedText?> lastOcrResult = Rx<RecognizedText?>(null);

  final Rx<Size?> absoluteImageSize = Rx<Size?>(null);
  final Rx<InputImageRotation?> imageRotation = Rx<InputImageRotation?>(null);

  /// Frozen-frame state — when true the stream is paused for capture.
  final RxBool isFrozen = false.obs;

  // ── Camera controls ────────────────────────────────────────────────────────

  final RxBool isTorchOn = false.obs;

  /// Zoom level (1.0 – max, clamped by device capability).
  final RxDouble zoomLevel = 1.0.obs;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;

  /// Minimum confidence threshold for object detection (0.0 – 1.0).
  final RxDouble confidenceThreshold = 0.45.obs;

  // ── Frame-processing throttle ───────────────────────────────────────────────────

  /// DateTime-based throttle — avoids holding async context across frames.
  DateTime _lastProcessed = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isProcessingFrame = false;
  /// 300ms throttle (~3 FPS ML processing) keeps the camera feed smooth.
  static const _throttleMs = 300;

  /// Index of the currently active camera (0 = back, 1 = front on most devices).
  int _activeCameraIndex = 0;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
    _initializeCameraAndDetectors();
  }

  @override
  void onClose() {
    _tearDown();
    super.onClose();
  }

  /// Public method for UI retry button after initialization failure.
  Future<void> retryInitialization() => _initializeCameraAndDetectors();

  // ── Initialization ─────────────────────────────────────────────────────────

  Future<void> _initializeCameraAndDetectors() async {
    // Step 1: Request permission
    final status = await Permission.camera.request();
    if (status.isPermanentlyDenied || status.isDenied) {
      isPermissionDenied.value = true;
      return;
    }

    // Step 2: Initialize ML detectors (OCR + YOLO via flutter_vision)
    try {
      await _scanService.initializeDetectors();

      // Bind to service's reactive detections stream.
      _detectionsWorker?.dispose();
      _detectionsWorker = ever(_scanService.latestDetections, (detections) {
        if (scanMode.value == 'object') {
          final filtered = detections.where((obj) {
            if (obj.labels.isEmpty) return false;
            return obj.labels.first.confidence >= confidenceThreshold.value;
          }).toList();

          detectedObjects.assignAll(filtered);
          detectedTexts.clear();
        }
      });
    } catch (e) {
      debugPrint('❌ LiveScanController: Detector init failed: $e');
      return;
    }

    // Step 3: Initialize camera (single controller for both OCR and YOLO)
    await _startCamera();
  }

  Future<void> _startCamera({int? cameraIndex}) async {
    try {
      cameras = await availableCameras();
      if (cameras.isEmpty) throw Exception('No cameras available on this device.');

      final idx = cameraIndex ??
          cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
      _activeCameraIndex = idx < 0 ? 0 : idx;

      final cc = CameraController(
        cameras[_activeCameraIndex],
        ResolutionPreset.medium, // Medium = better FPS for YOLO
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await cc.initialize();
      _minZoom = await cc.getMinZoomLevel();
      _maxZoom = await cc.getMaxZoomLevel();
      await cc.startImageStream(_onCameraFrameReceived);

      cameraController = cc;
      isCameraInitialized.value = true;
      isPermissionDenied.value = false;
    } catch (e) {
      debugPrint('❌ LiveScanController: Camera init error: $e');
      cameraController = null;
      isCameraInitialized.value = false;
      Get.snackbar(
        'Camera Error',
        'Could not start camera: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.redAccent.withAlpha(200),
        colorText: Colors.white,
      );
    }
  }

  Future<void> _tearDown() async {
    _detectionsWorker?.dispose();
    _detectionsWorker = null;

    if (cameraController != null) {
      try {
        if (cameraController!.value.isStreamingImages) {
          await cameraController!.stopImageStream();
        }
        await cameraController!.dispose();
      } catch (e) {
        debugPrint('⚠️ LiveScanController: Camera dispose error: $e');
      } finally {
        cameraController = null;
        isCameraInitialized.value = false;
      }
    }
    await _scanService.closeDetectors();
  }

  // ── Mode Toggle ────────────────────────────────────────────────────────────

  void toggleScanMode(String mode) {
    if (scanMode.value == mode) return;
    scanMode.value = mode;
    _clearResults();
    if (isFrozen.value) isFrozen.value = false;
    // Both modes use the same camera stream — no camera restart needed.
  }

  void _clearResults() {
    detectedTexts.clear();
    detectedObjects.clear();
    lastOcrResult.value = null;
    absoluteImageSize.value = null;
    imageRotation.value = null;
    _scanService.latestDetections.clear();
  }

  // ── Camera Controls ────────────────────────────────────────────────────────

  Future<void> toggleTorch() async {
    if (cameraController == null || !cameraController!.value.isInitialized) return;
    try {
      final newState = !isTorchOn.value;
      await cameraController!.setFlashMode(
        newState ? FlashMode.torch : FlashMode.off,
      );
      isTorchOn.value = newState;
    } catch (e) {
      debugPrint('⚠️ LiveScanController: Torch toggle failed: $e');
    }
  }

  Future<void> setZoom(double zoom) async {
    if (cameraController == null || !cameraController!.value.isInitialized) return;
    final clamped = zoom.clamp(_minZoom, _maxZoom);
    if (clamped == zoomLevel.value) return;
    try {
      await cameraController!.setZoomLevel(clamped);
      zoomLevel.value = clamped;
    } catch (e) {
      debugPrint('⚠️ LiveScanController: Zoom failed: $e');
    }
  }

  void setConfidenceThreshold(double threshold) {
    confidenceThreshold.value = threshold.clamp(0.1, 1.0);
    if (scanMode.value == 'object') {
      detectedObjects.removeWhere(
        (obj) => obj.labels.isEmpty || obj.labels.first.confidence < confidenceThreshold.value,
      );
    }
  }

  double get minZoom => _minZoom;
  double get maxZoom => _maxZoom;

  /// Switches between front and back camera.
  Future<void> flipCamera() async {
    if (cameras.length < 2) return;
    final nextIndex = (_activeCameraIndex + 1) % cameras.length;
    try {
      isCameraInitialized.value = false;

      if (cameraController != null) {
        if (cameraController!.value.isStreamingImages) {
          try { await cameraController!.stopImageStream(); } catch (_) {}
        }
        await cameraController!.dispose();
        cameraController = null;
      }

      await Future.delayed(const Duration(milliseconds: 300));
      await _startCamera(cameraIndex: nextIndex);
    } catch (e) {
      debugPrint('⚠️ LiveScanController: Flip camera error: $e');
      await Future.delayed(const Duration(milliseconds: 500));
      _initializeCameraAndDetectors();
    }
  }

  // ── Freeze-Frame Capture ───────────────────────────────────────────────────

  CameraImage? _lastCapturedImage;

  /// Freezes the live stream and processes the last frame.
  Future<void> captureSnapshot() async {
    if (isFrozen.value) return;
    HapticFeedback.mediumImpact();
    try {
      isFrozen.value = true;
      if (cameraController != null && cameraController!.value.isStreamingImages) {
        await cameraController!.stopImageStream();
      }
      if (_lastCapturedImage != null && scanMode.value == 'ocr') {
        await _processFrame(_lastCapturedImage!);
      }
    } catch (e) {
      debugPrint('❌ LiveScanController: Freeze-frame error: $e');
    }
  }

  Future<void> _resumeStream() async {
    try {
      if (cameraController != null && !cameraController!.value.isStreamingImages) {
        await cameraController!.startImageStream(_onCameraFrameReceived);
      }
    } catch (e) {
      debugPrint('⚠️ LiveScanController: Resume stream error: $e');
    } finally {
      isFrozen.value = false;
    }
  }

  void resumeScan() => _resumeStream();

  // ── Frame Processing Pipeline ──────────────────────────────────────────────

  void _onCameraFrameReceived(CameraImage image) {
    if (cameraController == null || !cameraController!.value.isInitialized) return;
    if (isCameraInitialized.value == false) return;
    if (_isProcessingFrame || _scanService.isBusy) return;

    final now = DateTime.now();
    if (now.difference(_lastProcessed).inMilliseconds < _throttleMs) return;
    if (isFrozen.value) return;
    _lastProcessed = now;

    _lastCapturedImage = image;
    _isProcessingFrame = true;
    _processFrame(image).then((_) {
      _isProcessingFrame = false;
    }).catchError((e) {
      _isProcessingFrame = false;
    });
  }

  Future<void> _processFrame(CameraImage image) async {
    if (scanMode.value == 'ocr') {
      // ── OCR path ────────────────────────────────────────────────────────
      final camera = cameras.isNotEmpty ? cameras[_activeCameraIndex] : null;
      if (camera == null) return;

      final rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation)
          ?? (Platform.isAndroid
              ? InputImageRotation.rotation90deg
              : InputImageRotation.rotation0deg);

      final bool isRotated = rotation == InputImageRotation.rotation90deg ||
          rotation == InputImageRotation.rotation270deg;
      final double portraitW = isRotated ? image.height.toDouble() : image.width.toDouble();
      final double portraitH = isRotated ? image.width.toDouble() : image.height.toDouble();

      final inputImage = _buildInputImage(image);
      if (inputImage == null) return;

      final result = await _scanService.processOcr(inputImage);
      if (result == null) return;
      lastOcrResult.value = result;

      final seen = <String>{};
      final ordered = <String>[];
      for (final block in result.blocks) {
        for (final line in block.lines) {
          final text = line.text.trim();
          if (text.isNotEmpty && seen.add(text)) ordered.add(text);
        }
      }
      detectedTexts.assignAll(ordered);
      detectedObjects.clear();

      absoluteImageSize.value = Size(portraitW, portraitH);
      imageRotation.value = rotation;
    } else {
      // ── YOLO object detection path ──────────────────────────────────────
      final camera = cameras.isNotEmpty ? cameras[_activeCameraIndex] : null;
      if (camera == null) return;

      final rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation)
          ?? (Platform.isAndroid
              ? InputImageRotation.rotation90deg
              : InputImageRotation.rotation0deg);

      final bool isRotated = rotation == InputImageRotation.rotation90deg ||
          rotation == InputImageRotation.rotation270deg;
      final double portraitW = isRotated ? image.height.toDouble() : image.width.toDouble();
      final double portraitH = isRotated ? image.width.toDouble() : image.height.toDouble();

      absoluteImageSize.value = Size(portraitW, portraitH);
      imageRotation.value = rotation;

      // Do not await processYolo so the UI thread doesn't pause for isolate messaging
      _scanService.processYolo(
        image,
        rotation,
        confidenceThreshold: confidenceThreshold.value,
      );
    }
  }

  // ── Input Image Builder (OCR Only) ─────────────────────────────────────────

  InputImage? _buildInputImage(CameraImage image) {
    try {
      final camera = cameras.isNotEmpty ? cameras[_activeCameraIndex] : null;
      if (camera == null) return null;

      final rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation)
          ?? (Platform.isAndroid
              ? InputImageRotation.rotation90deg
              : InputImageRotation.rotation0deg);

      final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());

      if (Platform.isAndroid) {
        final WriteBuffer allBytes = WriteBuffer();
        for (final Plane plane in image.planes) {
          allBytes.putUint8List(plane.bytes);
        }
        final bytes = allBytes.done().buffer.asUint8List();
        final metadata = InputImageMetadata(
          size: imageSize,
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: image.planes[0].bytesPerRow,
        );
        return InputImage.fromBytes(bytes: bytes, metadata: metadata);
      } else {
        final metadata = InputImageMetadata(
          size: imageSize,
          rotation: rotation,
          format: InputImageFormat.bgra8888,
          bytesPerRow: image.planes[0].bytesPerRow,
        );
        return InputImage.fromBytes(
          bytes: image.planes[0].bytes,
          metadata: metadata,
        );
      }
    } catch (e) {
      debugPrint('⚠️ LiveScanController: Failed to build InputImage: $e');
      return null;
    }
  }

  // ── Item Selection ─────────────────────────────────────────────────────────

  void selectItem(String text) {
    HapticFeedback.lightImpact();
    try {
      final chatController = Get.find<ChatController>();
      chatController.appendText(text);
      Get.snackbar(
        'Added to Chat',
        '"$text" inserted into chat input.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 1),
        backgroundColor: Colors.green.withAlpha(200),
        colorText: Colors.white,
      );
    } catch (e) {
      debugPrint('⚠️ LiveScanController: ChatController not registered: $e');
    }
  }

  /// Copies all detected OCR lines to clipboard.
  void copyAllOcrText() {
    if (detectedTexts.isEmpty) return;
    final all = detectedTexts.join('\n');
    Clipboard.setData(ClipboardData(text: all));
    HapticFeedback.lightImpact();
    Get.snackbar(
      'Copied',
      'All detected text copied to clipboard.',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 1),
    );
  }
}
