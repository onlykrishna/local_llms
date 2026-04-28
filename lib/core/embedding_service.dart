import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'embedding_isolate.dart';

class EmbeddingService {
  SendPort? _isolateSendPort;
  final _isolateReady = Completer<void>();
  final Map<String, List<double>> _cache = {};

  Future<void> init() async {
    final receivePort = ReceivePort();
    await Isolate.spawn(EmbeddingIsolate.spawn, receivePort.sendPort);
    
    final childPort = await receivePort.first as SendPort;
    _isolateSendPort = childPort;

    // Load assets in main thread and send to isolate
    final vocabStr = await rootBundle.loadString('assets/models/vocab.txt');
    final dir = await getApplicationDocumentsDirectory();
    final modelFile = File('${dir.path}/all-minilm-l6-v2.onnx');
    
    if (!await modelFile.exists()) {
      final rawAssetFile = await rootBundle.load('assets/models/all-minilm-l6-v2.onnx');
      await modelFile.writeAsBytes(rawAssetFile.buffer.asUint8List());
    }

    final responsePort = ReceivePort();
    _isolateSendPort!.send(EmbeddingRequest('init', {
      'vocab': vocabStr,
      'modelPath': modelFile.path,
    }, responsePort.sendPort));

    final response = await responsePort.first as EmbeddingResponse;
    if (response.isError) throw Exception('Failed to init embedding isolate: ${response.data}');
    
    _isolateReady.complete();
    debugPrint('🚀 [EmbeddingService] Isolate ready and model loaded');
  }

  Future<List<double>> embed(String text) async {
    if (_cache.containsKey(text)) return _cache[text]!;
    await _isolateReady.future;

    final responsePort = ReceivePort();
    _isolateSendPort!.send(EmbeddingRequest('embed', text, responsePort.sendPort));
    
    final response = await responsePort.first as EmbeddingResponse;
    if (response.isError) throw Exception('Embedding error: ${response.data}');
    
    final vector = response.data as List<double>;
    _cache[text] = vector;
    return vector;
  }

  Future<List<List<double>>> embedBatch(List<String> texts) async {
    await _isolateReady.future;

    final responsePort = ReceivePort();
    _isolateSendPort!.send(EmbeddingRequest('embedBatch', texts, responsePort.sendPort));
    
    final response = await responsePort.first as EmbeddingResponse;
    if (response.isError) throw Exception('Batch embedding error: ${response.data}');
    
    return response.data as List<List<double>>;
  }
}

