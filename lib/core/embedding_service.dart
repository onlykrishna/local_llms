import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path_provider/path_provider.dart';

class EmbeddingService {
  OrtSession? _session;
  Map<String, int> _vocab = {};
  int _unkTokenId = 100;
  int _clsTokenId = 101;
  int _sepTokenId = 102;
  int _padTokenId = 0;
  int _maxLen = 256;

  final Map<String, List<double>> _cache = {};

  Future<void> init() async {
    // Fast init: OrtEnv and Vocab only
    OrtEnv.instance.init();
    final sw = Stopwatch()..start();
    final vocabStr = await rootBundle.loadString('assets/models/vocab.txt');
    final lines = const LineSplitter().convert(vocabStr);
    _vocab = {};
    for (int i = 0; i < lines.length; i++) {
      _vocab[lines[i]] = i;
    }
    _unkTokenId = _vocab['[UNK]'] ?? 100;
    _clsTokenId = _vocab['[CLS]'] ?? 101;
    _sepTokenId = _vocab['[SEP]'] ?? 102;
    _padTokenId = _vocab['[PAD]'] ?? 0;
    debugPrint('🚀 [EmbeddingService] Tokenizer ready in ${sw.elapsedMilliseconds}ms');
  }

  Future<void> _ensureSession() async {
    if (_session != null) return;
    final sw = Stopwatch()..start();
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/all-minilm-l6-v2.onnx');
    
    if (!await file.exists()) {
      final rawAssetFile = await rootBundle.load('assets/models/all-minilm-l6-v2.onnx');
      await file.writeAsBytes(rawAssetFile.buffer.asUint8List());
    }
    
    final sessionOptions = OrtSessionOptions();
    _session = OrtSession.fromFile(file, sessionOptions);
    debugPrint('🚀 [EmbeddingService] Heavy ONNX model loaded in ${sw.elapsedMilliseconds}ms');
  }

  Future<List<double>> embed(String text) async {
    // Cache check
    if (_cache.containsKey(text)) return _cache[text]!;

    await _ensureSession();

    final tokenIds = _tokenize(text);
    final seqLen = tokenIds.length;
    
    final inputIds = OrtValueTensor.createTensorWithDataList(Int64List.fromList(tokenIds), [1, seqLen]);
    final attentionMask = OrtValueTensor.createTensorWithDataList(Int64List.fromList(List.filled(seqLen, 1)), [1, seqLen]);
    final tokenTypeIds = OrtValueTensor.createTensorWithDataList(Int64List.fromList(List.filled(seqLen, 0)), [1, seqLen]);
    
    final inputs = {
      'input_ids': inputIds,
      'attention_mask': attentionMask,
      'token_type_ids': tokenTypeIds,
    };

    final runOptions = OrtRunOptions();
    final outputs = _session!.run(runOptions, inputs);
    
    final outputValue = outputs[0]?.value;
    if (outputValue == null) throw Exception('Model output is null');

    List<double> flattened;
    if (outputValue is List<List<List<double>>>) {
      flattened = outputValue[0].expand((e) => e).toList();
    } else if (outputValue is Float32List) {
      flattened = outputValue.toList();
    } else {
      throw Exception('Unexpected model output type: ${outputValue.runtimeType}');
    }

    List<double> pooled = List.filled(384, 0.0);
    for (int i = 0; i < seqLen; i++) {
      for (int j = 0; j < 384; j++) {
        pooled[j] += flattened[i * 384 + j];
      }
    }
    
    double norm = 0.0;
    for (int j = 0; j < 384; j++) {
      pooled[j] /= seqLen;
      norm += pooled[j] * pooled[j];
    }
    norm = sqrt(norm);
    if (norm > 0) {
      for (int j = 0; j < 384; j++) pooled[j] /= norm;
    }
    
    inputIds.release();
    attentionMask.release();
    tokenTypeIds.release();
    runOptions.release();
    for (var out in outputs) out?.release();
    
    // Store in cache
    _cache[text] = pooled;
    return pooled;
  }

  List<int> _tokenize(String text) {
    // 1. Basic cleaning and lowercase
    final cleanText = text.toLowerCase().replaceAll(RegExp(r'[?.,!()]'), ' ');
    final words = cleanText.split(RegExp(r'\s+'));
    
    List<int> ids = [_clsTokenId];
    
    for (var word in words) {
      if (word.isEmpty) continue;
      
      // 2. WordPiece Greedy Maximum Matching
      int start = 0;
      while (start < word.length) {
        int end = word.length;
        String? bestSubword;
        
        while (start < end) {
          String sub = word.substring(start, end);
          // Subwords (not at the start of a word) in BERT/MiniLM vocab start with '##'
          final vocabKey = (start == 0) ? sub : '##$sub';
          
          if (_vocab.containsKey(vocabKey)) {
            bestSubword = vocabKey;
            break;
          }
          end--;
        }
        
        if (bestSubword == null) {
          // If we can't find even a single character subword, use UNK for the whole word
          ids.add(_unkTokenId);
          break; 
        } else {
          ids.add(_vocab[bestSubword]!);
          start = end;
        }
        
        if (ids.length >= _maxLen - 1) break;
      }
      
      if (ids.length >= _maxLen - 1) break;
    }
    
    // 3. Finalize sequence
    ids.add(_sepTokenId);
    while (ids.length < _maxLen) {
      ids.add(_padTokenId);
    }
    return ids;
  }

  Future<List<List<double>>> embedBatch(List<String> texts) async {
    List<List<double>> results = [];
    for (var text in texts) {
      results.add(await embed(text));
    }
    return results;
  }
}

