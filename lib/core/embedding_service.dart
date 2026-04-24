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

    // Verify critical tokens exist
    assert(_vocab.containsKey('[CLS]'), 'vocab.txt missing [CLS] token');
    assert(_vocab.containsKey('[SEP]'), 'vocab.txt missing [SEP] token');
    assert(_vocab.containsKey('[UNK]'), 'vocab.txt missing [UNK] token');
    debugPrint('[Tokenizer] Loaded ${_vocab.length} tokens. '
      'CLS=$_clsTokenId, SEP=$_sepTokenId, UNK=$_unkTokenId');

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
    // Preserve punctuation and hyphens as they carry semantic meaning for BERT/MiniLM
    text = text.toLowerCase().replaceAllMapped(RegExp(r'([.,!?()-])'), (m) => ' ${m.group(1)} ');
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

    final tokenIds = <int>[_clsTokenId];
    
    for (var word in words) {
      if (_vocab.containsKey(word)) {
        tokenIds.add(_vocab[word]!);
        continue;
      }
      
      // WordPiece subtokenization
      bool isBad = false;
      int start = 0;
      final subTokens = <int>[];
      
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
        tokenIds.add(_unkTokenId);
      } else {
        tokenIds.addAll(subTokens);
      }
    }
    
    tokenIds.add(_sepTokenId);
    
    // Limit to max length
    if (tokenIds.length > _maxLen) {
      return tokenIds.sublist(0, _maxLen);
    }
    
    return tokenIds;
  }

  Future<List<double>> embed(String text) async {
    if (_session == null) await init();

    final tokenIds = _tokenize(text);
    final seqLen = tokenIds.length;
    
    if (text.length < 50) {
      debugPrint('[Embed] Text: "${text.substring(0, text.length > 30 ? 30 : text.length)}..."');
      debugPrint('[Embed] Tokens: ${tokenIds.take(15).toList()}');
    }

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
    if (outputValue == null) {
      throw Exception('Model output is null');
    }

    List<double> flattened;
    if (outputValue is List<List<List<double>>>) {
      // Handle 3D output [1, seqLen, 384]
      flattened = outputValue[0].expand((e) => e).toList();
    } else if (outputValue is Float32List) {
      flattened = outputValue.toList();
    } else {
      throw Exception('Unexpected model output type: ${outputValue.runtimeType}');
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
    
    // Cleanup
    inputIds.release();
    attentionMask.release();
    tokenTypeIds.release();
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

