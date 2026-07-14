import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:path_provider/path_provider.dart';

/// Service managing:
///  • OCR via Google ML Kit TextRecognizer
///  • Object detection via tflite_flutter (YOLOv8n, COCO 80-class)
///
/// Spawns a persistent background isolate at startup. Real-time frame
/// preprocessing, TFLite inference, and NMS run entirely inside the isolate
/// to keep the main UI thread 100% free and butter-smooth.
class LiveScanService extends GetxService {
  // ── Public state ─────────────────────────────────────────────────────────

  final RxString initStatus = 'idle'.obs;

  /// Detections observed by the controller to drive UI overlays.
  final RxList<DetectedObject> latestDetections = <DetectedObject>[].obs;

  bool get isBusy => _ocrBusy || _detectorIsolateBusy;

  // ── Private fields ───────────────────────────────────────────────────────

  TextRecognizer? _textRecognizer;
  SendPort? _commandPort;
  Isolate? _detectorIsolate;
  ReceivePort? _responsePort;

  bool _ocrBusy = false;
  bool _detectorIsolateBusy = false;
  bool _isInitialized = false;
  String? _cachedModelPath;
  List<String> _labels = [];

  // ── Initialisation ────────────────────────────────────────────────────────

  Future<void> initializeDetectors() async {
    if (_isInitialized) return;
    initStatus.value = 'loading';
    try {
      // 1. Resolve YOLO model file path (copy to local directory if needed)
      _cachedModelPath = await _resolveModelPath();

      // 2. Load labels
      final labelStr = await rootBundle.loadString('assets/models/yolo_labels.txt');
      _labels = labelStr.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      debugPrint('✅ LiveScanService: Loaded ${_labels.length} YOLO labels.');

      // 3. Initialize OCR
      _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

      // 4. Spawn persistent background isolate
      _responsePort = ReceivePort();
      _detectorIsolate = await Isolate.spawn(_isolateEntryPoint, _responsePort!.sendPort);

      // Setup two-way isolate communication
      final completer = Completer<void>();
      _responsePort!.listen((message) {
        if (message is SendPort) {
          _commandPort = message;
          // Send model details to isolate
          _commandPort!.send(IsolateInitRequest(
            modelPath: _cachedModelPath!,
            labels: _labels,
          ));
        } else if (message == 'ready') {
          _isInitialized = true;
          initStatus.value = 'ready';
          if (!completer.isCompleted) completer.complete();
          debugPrint('✅ LiveScanService: Background isolate is ready.');
        } else if (message is String && message.startsWith('error:')) {
          initStatus.value = 'error';
          if (!completer.isCompleted) completer.completeError(Exception(message));
        } else if (message is List<Map<String, dynamic>>) {
          _handleDetections(message);
          _detectorIsolateBusy = false;
        }
      });

      await completer.future;
    } catch (e, st) {
      initStatus.value = 'error';
      debugPrint('❌ LiveScanService: Init failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> closeDetectors() async {
    try { await _textRecognizer?.close(); } catch (_) {}
    _textRecognizer = null;

    // Safely stop background isolate
    _commandPort?.send('exit');
    _commandPort = null;

    _detectorIsolate?.kill(priority: Isolate.beforeNextEvent);
    _detectorIsolate = null;

    _responsePort?.close();
    _responsePort = null;

    _isInitialized = false;
    _ocrBusy = false;
    _detectorIsolateBusy = false;
    latestDetections.clear();
    initStatus.value = 'idle';
    debugPrint('✅ LiveScanService: Detectors closed.');
  }

  // ── OCR ───────────────────────────────────────────────────────────────────

  Future<RecognizedText?> processOcr(InputImage inputImage) async {
    if (_ocrBusy || !_isInitialized || _textRecognizer == null) return null;
    _ocrBusy = true;
    try {
      return await _textRecognizer!.processImage(inputImage);
    } catch (e) {
      debugPrint('❌ OCR failed: $e');
      return null;
    } finally {
      _ocrBusy = false;
    }
  }

  // ── YOLO ──────────────────────────────────────────────────────────────────

  /// Sends a raw frame to the persistent background isolate.
  /// Returns true if sent, false if dropped due to isolate being busy.
  bool processYolo(
    CameraImage image,
    InputImageRotation rotation, {
    double confidenceThreshold = 0.45,
    double iouThreshold = 0.45,
  }) {
    if (!_isInitialized || _commandPort == null || _detectorIsolateBusy) {
      return false;
    }
    _detectorIsolateBusy = true;

    // Convert InputImageRotation to raw degrees
    final int rotationDegrees = _rotationToDegrees(rotation);

    // Package camera image planes by copying them to release native camera buffers immediately
    final List<Uint8List> planesData = image.planes.map((p) => p.bytes.sublist(0)).toList();
    final List<int> planesBytesPerRow = image.planes.map((p) => p.bytesPerRow).toList();
    final List<int?> planesBytesPerPixel = image.planes.map((p) => p.bytesPerPixel).toList();

    final request = IsolateFrameRequest(
      planesData: planesData,
      planesBytesPerRow: planesBytesPerRow,
      planesBytesPerPixel: planesBytesPerPixel,
      width: image.width,
      height: image.height,
      rotationDegrees: rotationDegrees,
      confidenceThreshold: confidenceThreshold,
      iouThreshold: iouThreshold,
    );

    _commandPort!.send(request);
    return true;
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  int _rotationToDegrees(InputImageRotation rotation) {
    switch (rotation) {
      case InputImageRotation.rotation0deg:
        return 0;
      case InputImageRotation.rotation90deg:
        return 90;
      case InputImageRotation.rotation180deg:
        return 180;
      case InputImageRotation.rotation270deg:
        return 270;
    }
  }

  Future<String> _resolveModelPath() async {
    const assetKey = 'assets/models/yolov8n.tflite';
    const fileName = 'yolov8n.tflite';

    final dir = await getApplicationSupportDirectory();
    final modelFile = File('${dir.path}/$fileName');

    if (!await modelFile.exists()) {
      debugPrint('📦 LiveScanService: Copying YOLO model to local storage...');
      final byteData = await rootBundle.load(assetKey);
      await modelFile.writeAsBytes(
        byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
        flush: true,
      );
      debugPrint('✅ LiveScanService: Model copied to ${modelFile.path}');
    }

    return modelFile.path;
  }

  void _handleDetections(List<Map<String, dynamic>> rawDetections) {
    final List<DetectedObject> detections = [];
    for (final raw in rawDetections) {
      final rect = Rect.fromLTRB(
        (raw['left'] as num).toDouble(),
        (raw['top'] as num).toDouble(),
        (raw['right'] as num).toDouble(),
        (raw['bottom'] as num).toDouble(),
      );
      final labelText = raw['label'] as String;
      final confidence = (raw['confidence'] as num).toDouble();
      final classIndex = raw['classIndex'] as int;

      detections.add(DetectedObject(
        boundingBox: rect,
        labels: [
          DetectedObjectLabel(
            text: labelText,
            confidence: confidence,
            index: classIndex,
          ),
        ],
      ));
    }
    latestDetections.assignAll(detections);
  }

  // ── Persistent Isolate Entry Point & Loop ──────────────────────────────────

  static void _isolateEntryPoint(SendPort mainSendPort) async {
    final isolateReceivePort = ReceivePort();
    mainSendPort.send(isolateReceivePort.sendPort);

    Interpreter? interpreter;
    List<String> labels = [];

    await for (final message in isolateReceivePort) {
      if (message == 'exit') {
        interpreter?.close();
        break;
      }

      if (message is IsolateInitRequest) {
        try {
          final opts = InterpreterOptions()..threads = 4;
          interpreter = Interpreter.fromFile(
            File(message.modelPath),
            options: opts,
          );
          interpreter.allocateTensors();
          labels = message.labels;
          mainSendPort.send('ready');
        } catch (e) {
          mainSendPort.send('error: $e');
        }
        continue;
      }

      if (message is IsolateFrameRequest) {
        if (interpreter == null) {
          mainSendPort.send(<Map<String, dynamic>>[]);
          continue;
        }

        try {
          final detections = _processFrameInIsolate(message, interpreter, labels);
          mainSendPort.send(detections);
        } catch (e, st) {
          debugPrint('❌ YOLO Isolate run error: $e\n$st');
          mainSendPort.send(<Map<String, dynamic>>[]);
        }
      }
    }
  }

  static List<Map<String, dynamic>> _processFrameInIsolate(
    IsolateFrameRequest req,
    Interpreter interpreter,
    List<String> labels,
  ) {
    const int inputSize = 640;
    const int numClasses = 80;
    const int numPredictions = 8400;

    // Allocate flat Float32List for FFI zero-copy input
    final input = Float32List(1 * inputSize * inputSize * 3);

    final bool isRotated = req.rotationDegrees == 90 || req.rotationDegrees == 270;
    final int orientedW = isRotated ? req.height : req.width;
    final int orientedH = isRotated ? req.width : req.height;

    final double scaleX = inputSize / orientedW;
    final double scaleY = inputSize / orientedH;
    final double scale = scaleX < scaleY ? scaleX : scaleY;
    final int scaledW = (orientedW * scale).round();
    final int scaledH = (orientedH * scale).round();
    final int padX = (inputSize - scaledW) ~/ 2;
    final int padY = (inputSize - scaledH) ~/ 2;

    if (req.planesData.length > 1) {
      // NV21 (Android)
      final yPlane = req.planesData[0];
      final vuPlane = req.planesData[1];
      final yRowStride = req.planesBytesPerRow[0];
      final uvRowStride = req.planesBytesPerRow[1];
      final uvPixelStride = req.planesBytesPerPixel[1] ?? 2;
      final vuLength = vuPlane.length;

      for (int y = 0; y < inputSize; y++) {
        final int targetY = y - padY;
        final bool outOfBoundsY = targetY < 0 || targetY >= scaledH;

        for (int x = 0; x < inputSize; x++) {
          final int targetX = x - padX;
          final int idx = (y * inputSize + x) * 3;

          if (outOfBoundsY || targetX < 0 || targetX >= scaledW) {
            input[idx] = 0.447;
            input[idx + 1] = 0.447;
            input[idx + 2] = 0.447;
            continue;
          }

          final int orientedX = (targetX / scale).floor().clamp(0, orientedW - 1);
          final int orientedY = (targetY / scale).floor().clamp(0, orientedH - 1);

          int srcX = 0;
          int srcY = 0;
          if (req.rotationDegrees == 90) {
            srcX = orientedY;
            srcY = req.height - 1 - orientedX;
          } else if (req.rotationDegrees == 270) {
            srcX = req.width - 1 - orientedY;
            srcY = orientedX;
          } else if (req.rotationDegrees == 180) {
            srcX = req.width - 1 - orientedX;
            srcY = req.height - 1 - orientedY;
          } else {
            srcX = orientedX;
            srcY = orientedY;
          }

          final int yPos = srcY * yRowStride + srcX;
          if (yPos >= yPlane.length) continue;
          final int yVal = yPlane[yPos] & 0xFF;

          final int uvX = srcX >> 1;
          final int uvY = srcY >> 1;
          final int uvPos = uvY * uvRowStride + uvX * uvPixelStride;

          int uVal = 128;
          int vVal = 128;
          if (uvPos + 1 < vuLength) {
            vVal = vuPlane[uvPos] & 0xFF;
            uVal = vuPlane[uvPos + 1] & 0xFF;
          }

          final int yp = yVal - 16;
          final int up = uVal - 128;
          final int vp = vVal - 128;

          input[idx] = ((298 * yp + 409 * vp + 128) >> 8).clamp(0, 255) / 255.0;
          input[idx + 1] = ((298 * yp - 100 * up - 208 * vp + 128) >> 8).clamp(0, 255) / 255.0;
          input[idx + 2] = ((298 * yp + 516 * up + 128) >> 8).clamp(0, 255) / 255.0;
        }
      }
    } else {
      // BGRA8888 (iOS)
      final bgraPlane = req.planesData[0];
      final rowStride = req.planesBytesPerRow[0];

      for (int y = 0; y < inputSize; y++) {
        final int targetY = y - padY;
        final bool outOfBoundsY = targetY < 0 || targetY >= scaledH;

        for (int x = 0; x < inputSize; x++) {
          final int targetX = x - padX;
          final int idx = (y * inputSize + x) * 3;

          if (outOfBoundsY || targetX < 0 || targetX >= scaledW) {
            input[idx] = 0.447;
            input[idx + 1] = 0.447;
            input[idx + 2] = 0.447;
            continue;
          }

          final int orientedX = (targetX / scale).floor().clamp(0, orientedW - 1);
          final int orientedY = (targetY / scale).floor().clamp(0, orientedH - 1);

          int srcX = 0;
          int srcY = 0;
          if (req.rotationDegrees == 90) {
            srcX = orientedY;
            srcY = req.height - 1 - orientedX;
          } else if (req.rotationDegrees == 270) {
            srcX = req.width - 1 - orientedY;
            srcY = orientedX;
          } else if (req.rotationDegrees == 180) {
            srcX = req.width - 1 - orientedX;
            srcY = req.height - 1 - orientedY;
          } else {
            srcX = orientedX;
            srcY = orientedY;
          }

          final int pos = srcY * rowStride + srcX * 4;
          if (pos + 2 >= bgraPlane.length) continue;

          input[idx] = bgraPlane[pos + 2] / 255.0;     // R
          input[idx + 1] = bgraPlane[pos + 1] / 255.0; // G
          input[idx + 2] = bgraPlane[pos] / 255.0;     // B
        }
      }
    }

    // Direct C++ invocation via FFI setTo and invoke
    final inputTensor = interpreter.getInputTensor(0);
    inputTensor.setTo(input.buffer);
    interpreter.invoke();

    final outputTensor = interpreter.getOutputTensor(0);
    final outputBytes = outputTensor.data;
    final output = Float32List.view(outputBytes.buffer);

    final List<_Box> boxes = [];
    for (int col = 0; col < numPredictions; col++) {
      double bestConf = 0.0;
      int bestClass = -1;
      for (int c = 0; c < numClasses; c++) {
        final double conf = output[(4 + c) * numPredictions + col];
        if (conf > bestConf) {
          bestConf = conf;
          bestClass = c;
        }
      }

      if (bestConf < req.confidenceThreshold) continue;

      final double cx = output[0 * numPredictions + col] * inputSize;
      final double cy = output[1 * numPredictions + col] * inputSize;
      final double w = output[2 * numPredictions + col] * inputSize;
      final double h = output[3 * numPredictions + col] * inputSize;

      boxes.add(_Box(
        x1: cx - w / 2,
        y1: cy - h / 2,
        x2: cx + w / 2,
        y2: cy + h / 2,
        conf: bestConf,
        cls: bestClass,
      ));
    }

    // Sort and execute NMS
    boxes.sort((a, b) => b.conf.compareTo(a.conf));
    final List<bool> suppressed = List.filled(boxes.length, false);
    final List<_Box> kept = [];

    for (int i = 0; i < boxes.length; i++) {
      if (suppressed[i]) continue;
      kept.add(boxes[i]);
      for (int j = i + 1; j < boxes.length; j++) {
        if (suppressed[j]) continue;
        if (boxes[i].cls == boxes[j].cls && _iou(boxes[i], boxes[j]) > req.iouThreshold) {
          suppressed[j] = true;
        }
      }
    }

    // Map back to oriented source space
    final List<Map<String, dynamic>> results = [];
    for (final b in kept) {
      final double ox1 = ((b.x1 - padX) / scale).clamp(0.0, orientedW.toDouble());
      final double oy1 = ((b.y1 - padY) / scale).clamp(0.0, orientedH.toDouble());
      final double ox2 = ((b.x2 - padX) / scale).clamp(0.0, orientedW.toDouble());
      final double oy2 = ((b.y2 - padY) / scale).clamp(0.0, orientedH.toDouble());

      final String label = (b.cls >= 0 && b.cls < labels.length) ? labels[b.cls] : 'Object';

      results.add({
        'left': ox1,
        'top': oy1,
        'right': ox2,
        'bottom': oy2,
        'confidence': b.conf,
        'classIndex': b.cls,
        'label': label,
      });
    }

    return results;
  }

  static double _iou(_Box a, _Box b) {
    final ix1 = a.x1 > b.x1 ? a.x1 : b.x1;
    final iy1 = a.y1 > b.y1 ? a.y1 : b.y1;
    final ix2 = a.x2 < b.x2 ? a.x2 : b.x2;
    final iy2 = a.y2 < b.y2 ? a.y2 : b.y2;
    if (ix2 <= ix1 || iy2 <= iy1) return 0.0;
    final inter = (ix2 - ix1) * (iy2 - iy1);
    final areaA = (a.x2 - a.x1) * (a.y2 - a.y1);
    final areaB = (b.x2 - b.x1) * (b.y2 - b.y1);
    return inter / (areaA + areaB - inter);
  }
}

// ── Isolate request/response DTOs ───────────────────────────────────────────

class IsolateInitRequest {
  final String modelPath;
  final List<String> labels;
  const IsolateInitRequest({required this.modelPath, required this.labels});
}

class IsolateFrameRequest {
  final List<Uint8List> planesData;
  final List<int> planesBytesPerRow;
  final List<int?> planesBytesPerPixel;
  final int width;
  final int height;
  final int rotationDegrees;
  final double confidenceThreshold;
  final double iouThreshold;

  const IsolateFrameRequest({
    required this.planesData,
    required this.planesBytesPerRow,
    required this.planesBytesPerPixel,
    required this.width,
    required this.height,
    required this.rotationDegrees,
    required this.confidenceThreshold,
    required this.iouThreshold,
  });
}

class _Box {
  final double x1, y1, x2, y2, conf;
  final int cls;
  _Box({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.conf,
    required this.cls,
  });
}

// ── Public Bounding Box Types ────────────────────────────────────────────────

class DetectedObject {
  final int? trackingId;
  final Rect boundingBox;
  final List<DetectedObjectLabel> labels;
  const DetectedObject({
    this.trackingId,
    required this.boundingBox,
    required this.labels,
  });
}

class DetectedObjectLabel {
  final String text;
  final double confidence;
  final int index;
  const DetectedObjectLabel({
    required this.text,
    required this.confidence,
    required this.index,
  });
}
