import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Sanity Test: Audit TFLite Model with Known Mug Image', () async {

    // 1. Load labels
    final labelsFile = File('assets/models/object_labeler_labels.txt');
    expect(labelsFile.existsSync(), isTrue);
    final labels = labelsFile
        .readAsLinesSync()
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    print('📋 Loaded ${labels.length} labels.');

    // 2. Load model
    final modelFile = File('assets/models/object_labeler.tflite');
    expect(modelFile.existsSync(), isTrue);
    final options = InterpreterOptions()..threads = 1;
    final interpreter = Interpreter.fromFile(modelFile, options: options);

    // 3. Print output tensors details
    final outputTensors = interpreter.getOutputTensors();
    print('📊 Output Tensors:');
    for (int i = 0; i < outputTensors.length; i++) {
      print('  Tensor $i: name=${outputTensors[i].name}, shape=${outputTensors[i].shape}, type=${outputTensors[i].type}');
    }

    // Determine output indices dynamically based on shape/type
    int boxesIdx = 0;
    int classesIdx = 1;
    int scoresIdx = 2;
    int numDetectionsIdx = 3;

    final list2D = <int>[];
    for (int i = 0; i < outputTensors.length; i++) {
      final shape = outputTensors[i].shape;
      if (shape.length == 3 && shape[0] == 1 && shape[2] == 4) {
        boxesIdx = i;
      } else if (shape.length == 2 && shape[0] == 1) {
        list2D.add(i);
      } else if ((shape.length == 1 && shape[0] == 1) || shape.isEmpty) {
        numDetectionsIdx = i;
      }
    }
    if (list2D.length == 2) {
      final name0 = outputTensors[list2D[0]].name.toLowerCase();
      final name1 = outputTensors[list2D[1]].name.toLowerCase();
      if (name0.contains('score') || name1.contains('class')) {
        scoresIdx = list2D[0];
        classesIdx = list2D[1];
      } else {
        classesIdx = list2D[0];
        scoresIdx = list2D[1];
      }
    }
    print('🎯 Discovered Indices: boxesIdx=$boxesIdx, classesIdx=$classesIdx, scoresIdx=$scoresIdx, numDetectionsIdx=$numDetectionsIdx');

    // 4. Load test mug image
    final imageFile = File('/Users/aeologic/.gemini/antigravity-ide/brain/7505cab3-c72f-4c27-b93d-798abea5a1a2/test_mug_1783947766639.png');
    expect(imageFile.existsSync(), isTrue);

    final bytes = imageFile.readAsBytesSync();
    final image = img.decodeImage(bytes);
    expect(image, isNotNull);

    // Resize to 300x300 using bilinear scaling
    final resized = img.copyResize(image!, width: 300, height: 300);

    // Convert to float32 or uint8 depending on input tensor type
    final inputTensor = interpreter.getInputTensor(0);
    print('📥 Input Tensor shape: ${inputTensor.shape}, type: ${inputTensor.type}');

    final Object inputData;
    // We check using toString() to avoid enum version compile errors
    if (inputTensor.type.toString().contains('uint8')) {
      final uint8Buffer = Uint8List(300 * 300 * 3);
      int pixelIdx = 0;
      for (int y = 0; y < 300; y++) {
        for (int x = 0; x < 300; x++) {
          final pixel = resized.getPixel(x, y);
          uint8Buffer[pixelIdx++] = pixel.r.toInt();
          uint8Buffer[pixelIdx++] = pixel.g.toInt();
          uint8Buffer[pixelIdx++] = pixel.b.toInt();
        }
      }
      inputData = uint8Buffer;
    } else {
      // Float32 normalization to [0, 1] or [-1, 1]
      final float32Buffer = Float32List(300 * 300 * 3);
      int pixelIdx = 0;
      for (int y = 0; y < 300; y++) {
        for (int x = 0; x < 300; x++) {
          final pixel = resized.getPixel(x, y);
          float32Buffer[pixelIdx++] = pixel.r.toDouble() / 255.0;
          float32Buffer[pixelIdx++] = pixel.g.toDouble() / 255.0;
          float32Buffer[pixelIdx++] = pixel.b.toDouble() / 255.0;
        }
      }
      inputData = float32Buffer;
    }

    // Allocate output buffers
    final N = 10;
    final outputBoxes = List.generate(1, (_) => List.generate(N, (_) => List.filled(4, 0.0)));
    final outputClasses = List.generate(1, (_) => List.filled(N, 0.0));
    final outputScores = List.generate(1, (_) => List.filled(N, 0.0));
    final numDetections = List.filled(1, 0.0);

    final outputs = <int, Object>{
      boxesIdx: outputBoxes,
      classesIdx: outputClasses,
      scoresIdx: outputScores,
      numDetectionsIdx: numDetections,
    };

    // 5. Run inference
    interpreter.runForMultipleInputs([inputData], outputs);

    final count = numDetections[0].toInt().clamp(0, N);
    print('📊 Detections count: $count');

    // Print all detections
    for (int i = 0; i < count; i++) {
      final score = outputScores[0][i];
      final rawClass = outputClasses[0][i];
      final box = outputBoxes[0][i];
      
      final rawClassIdx = rawClass.round();
      
      print('  Box $i: rawClass=$rawClass, rawClassIdx=$rawClassIdx, score=${score.toStringAsFixed(4)}, box=$box');

      // Map to 1-indexed (with shift-1)
      final labelIdxShift1 = rawClassIdx - 1;
      String labelShift1 = 'Out of Bounds';
      if (labelIdxShift1 >= 0 && labelIdxShift1 < labels.length) {
        labelShift1 = labels[labelIdxShift1];
      }

      // Map to 0-indexed direct
      final labelIdxDirect = rawClassIdx;
      String labelDirect = 'Out of Bounds';
      if (labelIdxDirect >= 0 && labelIdxDirect < labels.length) {
        labelDirect = labels[labelIdxDirect];
      }

      print('    -> Mapped with Shift-1 (rawClassIdx - 1): $labelShift1');
      print('    -> Mapped Direct (rawClassIdx): $labelDirect');
    }

    interpreter.close();
  });
}
