import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

void main() {
  test('inspect model', () async {
    final file = File('assets/models/object_labeler.tflite');
    expect(file.existsSync(), isTrue);
    final interpreter = Interpreter.fromFile(file);
    print('=== Model Tensors ===');
    print('Inputs:');
    for (var i = 0; i < interpreter.getInputTensors().length; i++) {
      final t = interpreter.getInputTensor(i);
      print('Input $i: name=${t.name}, shape=${t.shape}, type=${t.type}');
    }
    print('Outputs:');
    for (var i = 0; i < interpreter.getOutputTensors().length; i++) {
      final t = interpreter.getOutputTensor(i);
      print('Output $i: name=${t.name}, shape=${t.shape}, type=${t.type}');
    }
    interpreter.close();
  });
}
