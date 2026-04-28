import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';

/// Request sent to the embedding isolate
class EmbeddingRequest {
  final String action;
  final dynamic data;
  final SendPort replyTo;

  EmbeddingRequest(this.action, this.data, this.replyTo);
}

/// Response sent from the embedding isolate
class EmbeddingResponse {
  final dynamic data;
  final bool isError;

  EmbeddingResponse(this.data, {this.isError = false});
}

class EmbeddingIsolate {
  static Future<void> spawn(SendPort mainSendPort) async {
    final childReceivePort = ReceivePort();
    mainSendPort.send(childReceivePort.sendPort);

    OrtSession? session;
    Map<String, int> vocab = {};
    int unkTokenId = 100;
    int clsTokenId = 101;
    int sepTokenId = 102;
    int padTokenId = 0;
    const int maxLen = 256;

    await for (final message in childReceivePort) {
      if (message is EmbeddingRequest) {
        try {
          switch (message.action) {
            case 'init':
              final vocabData = message.data['vocab'] as String;
              final modelPath = message.data['modelPath'] as String;
              
              OrtEnv.instance.init();
              final lines = const LineSplitter().convert(vocabData);
              for (int i = 0; i < lines.length; i++) {
                vocab[lines[i]] = i;
              }
              unkTokenId = vocab['[UNK]'] ?? 100;
              clsTokenId = vocab['[CLS]'] ?? 101;
              sepTokenId = vocab['[SEP]'] ?? 102;
              padTokenId = vocab['[PAD]'] ?? 0;

              final sessionOptions = OrtSessionOptions();
              session = OrtSession.fromFile(File(modelPath), sessionOptions);
              message.replyTo.send(EmbeddingResponse('ready'));
              break;

            case 'embed':
              if (session == null) throw Exception('Embedding session not initialized');
              final text = message.data as String;
              final vector = _internalEmbed(
                text, session, vocab, clsTokenId, sepTokenId, unkTokenId, padTokenId, maxLen
              );
              message.replyTo.send(EmbeddingResponse(vector));
              break;
            
            case 'embedBatch':
              if (session == null) throw Exception('Embedding session not initialized');
              final texts = message.data as List<String>;
              final vectors = texts.map((t) => _internalEmbed(
                t, session!, vocab, clsTokenId, sepTokenId, unkTokenId, padTokenId, maxLen
              )).toList();
              message.replyTo.send(EmbeddingResponse(vectors));
              break;
          }
        } catch (e) {
          message.replyTo.send(EmbeddingResponse(e.toString(), isError: true));
        }
      }
    }
  }

  static List<double> _internalEmbed(
    String text, 
    OrtSession session, 
    Map<String, int> vocab,
    int clsTokenId,
    int sepTokenId,
    int unkTokenId,
    int padTokenId,
    int maxLen
  ) {
    final tokenIds = _internalTokenize(text, vocab, clsTokenId, sepTokenId, unkTokenId, padTokenId, maxLen);
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
    final outputs = session.run(runOptions, inputs);
    
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
    
    return pooled;
  }

  static List<int> _internalTokenize(
    String text, 
    Map<String, int> vocab,
    int clsTokenId,
    int sepTokenId,
    int unkTokenId,
    int padTokenId,
    int maxLen
  ) {
    final cleanText = text.toLowerCase().replaceAll(RegExp(r'[?.,!()]'), ' ');
    final words = cleanText.split(RegExp(r'\s+'));
    List<int> ids = [clsTokenId];
    
    for (var word in words) {
      if (word.isEmpty) continue;
      int start = 0;
      while (start < word.length) {
        int end = word.length;
        String? bestSubword;
        while (start < end) {
          String sub = word.substring(start, end);
          final vocabKey = (start == 0) ? sub : '##$sub';
          if (vocab.containsKey(vocabKey)) {
            bestSubword = vocabKey;
            break;
          }
          end--;
        }
        if (bestSubword == null) {
          ids.add(unkTokenId);
          break; 
        } else {
          ids.add(vocab[bestSubword]!);
          start = end;
        }
        if (ids.length >= maxLen - 1) break;
      }
      if (ids.length >= maxLen - 1) break;
    }
    ids.add(sepTokenId);
    while (ids.length < maxLen) {
      ids.add(padTokenId);
    }
    return ids;
  }
}
