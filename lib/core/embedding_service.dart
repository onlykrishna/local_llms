import 'dart:async';
import 'dart:math';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'embedding_isolate.dart';
import 'services/log_service.dart';

class EmbeddingService {
  SendPort? _isolateSendPort;
  final _isolateReady = Completer<void>();
  bool get isInitialized => _isolateReady.isCompleted;

  // max memory footprint = 200 × 384 × 4 bytes = ~307KB
  final _LruCache<String, List<double>> _cache = _LruCache(200);

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
    LogService.to.log('🚀 [EmbeddingService] Isolate ready and model loaded');

    // Sanity check
    final testEmbed = await embed('test');
    double norm = 0.0;
    for (final v in testEmbed) norm += v * v;
    debugPrint('[EMBED] Normalization check: norm=${sqrt(norm).toStringAsFixed(4)} (expect ~1.0)');
  }

  Future<List<double>> embed(String text) async {
    final cached = _cache.get(text);
    if (cached != null) return cached;
    
    await _isolateReady.future;

    final responsePort = ReceivePort();
    _isolateSendPort!.send(EmbeddingRequest('embed', text, responsePort.sendPort));
    
    final response = await responsePort.first as EmbeddingResponse;
    if (response.isError) throw Exception('Embedding error: ${response.data}');
    
    final raw = (response.data as List).cast<double>();
    final normalized = _l2Normalize(raw);
    _cache.put(text, normalized);
    return normalized;
  }

  List<double> _l2Normalize(List<double> vector) {
    double norm = 0.0;
    for (final v in vector) norm += v * v;
    norm = sqrt(norm);
    if (norm == 0.0) return vector;
    return vector.map((v) => v / norm).toList();
  }

  void clearCache() => _cache.clear();

  Future<List<List<double>>> embedBatch(List<String> texts) async {
    await _isolateReady.future;

    final responsePort = ReceivePort();
    _isolateSendPort!.send(EmbeddingRequest('embedBatch', texts, responsePort.sendPort));
    
    final response = await responsePort.first as EmbeddingResponse;
    if (response.isError) throw Exception('Batch embedding error: ${response.data}');
    
    final rawBatch = (response.data as List).cast<List<dynamic>>();
    return rawBatch.map((raw) => _l2Normalize(raw.cast<double>())).toList();
  }
}

class _LruCache<K, V> {
  final int capacity;
  final void Function(K key, V value)? onEvict;
  final LinkedHashMap<K, V> _map = LinkedHashMap();

  _LruCache(this.capacity, {this.onEvict});

  V? get(K key) {
    if (!_map.containsKey(key)) return null;
    final val = _map.remove(key)!;
    _map[key] = val; // move to end (most recent)
    return val;
  }

  void put(K key, V value) {
    if (_map.containsKey(key)) _map.remove(key);
    _map[key] = value;
    if (_map.length > capacity) {
      final evictedKey = _map.keys.first;
      final evictedValue = _map.remove(evictedKey);
      if (onEvict != null && evictedValue != null) {
        onEvict!(evictedKey, evictedValue);
      }
    }
  }

  void clear() => _map.clear();
  int get length => _map.length;
}

