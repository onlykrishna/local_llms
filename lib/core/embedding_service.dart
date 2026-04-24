import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
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

  Future<void> init() async {
    OrtEnv.instance.init();
    
    // Load vocab
    final vocabStr = await rootBundle.loadString('assets/models/vocab.txt');
    final lines = const LineSplitter().convert(vocabStr);
    for (int i = 0; i < lines.length; i++) {
      _vocab[lines[i]] = i;
      if (lines[i] == '[UNK]') _unkTokenId = i;
      if (lines[i] == '[CLS]') _clsTokenId = i;
      if (lines[i] == '[SEP]') _sepTokenId = i;
      if (lines[i] == '[PAD]') _padTokenId = i;
    }

    // Load ONNX model
    final rawAssetFile = await rootBundle.load('assets/models/all-minilm-l6-v2.onnx');
    final bytes = rawAssetFile.buffer.asUint8List();
    
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/all-minilm-l6-v2.onnx');
    if (!await file.exists()) {
      await file.writeAsBytes(bytes);
    }
    
    final sessionOptions = OrtSessionOptions();
    _session = OrtSession.fromFile(file, sessionOptions);
  }

  List<int> _tokenize(String text) {
    text = text.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), ' ');
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    
    List<int> tokens = [_clsTokenId];
    
    for (var word in words) {
      if (tokens.length >= _maxLen - 1) break;
      
      int start = 0;
      bool isBad = false;
      List<int> subTokens = [];
      
      while (start < word.length) {
        int end = word.length;
        String? curSubstr;
        while (start < end) {
          String sub = word.substring(start, end);
          if (start > 0) sub = '##$sub';
          if (_vocab.containsKey(sub)) {
            curSubstr = sub;
            break;
          }
          end--;
        }
        
        if (curSubstr == null) {
          isBad = true;
          break;
        }
        subTokens.add(_vocab[curSubstr]!);
        start = end;
      }
      
      if (isBad) {
        subTokens = [_unkTokenId];
      }
      
      for (var t in subTokens) {
        if (tokens.length < _maxLen - 1) tokens.add(t);
      }
    }
    
    tokens.add(_sepTokenId);
    return tokens;
  }

  Future<List<double>> embed(String text) async {
    if (_session == null) throw Exception("EmbeddingService not initialized");
    
    final tokenIds = _tokenize(text);
    final seqLen = tokenIds.length;
    
    final inputIds = Int64List(seqLen);
    final attentionMask = Int64List(seqLen);
    final tokenTypeIds = Int64List(seqLen);
    
    for (int i = 0; i < seqLen; i++) {
      inputIds[i] = tokenIds[i];
      attentionMask[i] = 1;
      tokenTypeIds[i] = 0;
    }
    
    final inputIdsTensor = OrtValueTensor.createTensorWithDataList(inputIds, [1, seqLen]);
    final attentionMaskTensor = OrtValueTensor.createTensorWithDataList(attentionMask, [1, seqLen]);
    final tokenTypeIdsTensor = OrtValueTensor.createTensorWithDataList(tokenTypeIds, [1, seqLen]);
    
    final inputs = {
      'input_ids': inputIdsTensor,
      'attention_mask': attentionMaskTensor,
      'token_type_ids': tokenTypeIdsTensor,
    };
    
    final runOptions = OrtRunOptions();
    final outputs = _session!.run(runOptions, inputs);
    
    // Outputs[0] is usually a list/Float32List of size 1 * seqLen * 384
    final outputValue = outputs[0]?.value;
    List<double> flattened;
    if (outputValue is List) {
      // Sometimes it's a nested list depending on the wrapper version, we flatten it
      flattened = outputValue.expand((e) {
        if (e is List) {
          return e.expand((e2) => e2 is List ? e2.cast<double>() : [e2 as double]);
        }
        return [e as double];
      }).toList();
    } else {
      flattened = (outputValue as Float32List).toList();
    }

    // Mean pooling
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
      for (int j = 0; j < 384; j++) {
        pooled[j] /= norm;
      }
    }
    
    inputIdsTensor.release();
    attentionMaskTensor.release();
    tokenTypeIdsTensor.release();
    runOptions.release();
    for (var out in outputs) {
      out?.release();
    }
    
    return pooled;
  }

  Future<List<List<double>>> embedBatch(List<String> texts) async {
    List<List<double>> results = [];
    for (var text in texts) {
      results.add(await embed(text));
    }
    return results;
  }
}

