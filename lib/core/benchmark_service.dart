import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

class PipelineMetrics {
  final String queryId;
  final DateTime timestamp;
  final int embeddingMs;
  final int retrievalMs;
  final int bypassCheckMs;
  final bool bypassFired;
  final int? inferenceMs;
  final int groundingMs;
  final int totalMs;
  final double topScore;
  final double adaptiveThreshold;
  final double? groundingScore;
  final int threadCount;
  final String backendType;

  PipelineMetrics({
    required this.queryId,
    required this.timestamp,
    required this.embeddingMs,
    required this.retrievalMs,
    required this.bypassCheckMs,
    required this.bypassFired,
    this.inferenceMs,
    required this.groundingMs,
    required this.totalMs,
    required this.topScore,
    required this.adaptiveThreshold,
    this.groundingScore,
    required this.threadCount,
    required this.backendType,
  });
}

class BenchmarkSummary {
  final int p50TotalMs;
  final int p90TotalMs;
  final int p50InferenceMs;
  final int avgEmbeddingMs;
  final int avgRetrievalMs;
  final double bypassRate;
  final int sampleCount;

  BenchmarkSummary({
    required this.p50TotalMs,
    required this.p90TotalMs,
    required this.p50InferenceMs,
    required this.avgEmbeddingMs,
    required this.avgRetrievalMs,
    required this.bypassRate,
    required this.sampleCount,
  });

  factory BenchmarkSummary.empty() => BenchmarkSummary(
        p50TotalMs: 0,
        p90TotalMs: 0,
        p50InferenceMs: 0,
        avgEmbeddingMs: 0,
        avgRetrievalMs: 0,
        bypassRate: 0.0,
        sampleCount: 0,
      );
}

class BenchmarkService extends GetxService {
  final _metrics = <PipelineMetrics>[].obs;
  final _enabled = false.obs;

  void toggle() => _enabled.value = !_enabled.value;
  bool get isEnabled => _enabled.value;

  void record(PipelineMetrics m) {
    if (!_enabled.value && !(kDebugMode || kProfileMode)) return;
    _metrics.add(m);
    
    if (kDebugMode) {
      debugPrint('[BENCH] ${m.queryId}: total=${m.totalMs}ms '
          'embed=${m.embeddingMs}ms '
          'retrieval=${m.retrievalMs}ms '
          'inference=${m.inferenceMs ?? 'bypass'}ms '
          'grounding=${m.groundingMs}ms '
          'bypass=${m.bypassFired} '
          'score=${m.topScore.toStringAsFixed(3)}');
    }
  }

  BenchmarkSummary summarize({int lastN = 20}) {
    final recent = _metrics.length > lastN 
        ? _metrics.sublist(_metrics.length - lastN) 
        : _metrics.toList();
    
    if (recent.isEmpty) return BenchmarkSummary.empty();

    final totalTimes = recent.map((m) => m.totalMs).toList();
    final llmQueries = recent.where((m) => !m.bypassFired).toList();
    final bypassQueries = recent.where((m) => m.bypassFired).toList();

    return BenchmarkSummary(
      p50TotalMs: _percentile(totalTimes, 0.50),
      p90TotalMs: _percentile(totalTimes, 0.90),
      p50InferenceMs: llmQueries.isEmpty
          ? 0
          : _percentile(llmQueries.map((m) => m.inferenceMs!).toList(), 0.50),
      avgEmbeddingMs: (recent.map((m) => m.embeddingMs).reduce((a, b) => a + b) / recent.length).round(),
      avgRetrievalMs: (recent.map((m) => m.retrievalMs).reduce((a, b) => a + b) / recent.length).round(),
      bypassRate: bypassQueries.length / recent.length,
      sampleCount: recent.length,
    );
  }

  int _percentile(List<int> values, double p) {
    if (values.isEmpty) return 0;
    final sorted = [...values]..sort();
    return sorted[(sorted.length * p).floor().clamp(0, sorted.length - 1)];
  }

  List<PipelineMetrics> export() => List.unmodifiable(_metrics);

  Future<void> exportToFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/benchmark_${DateTime.now().millisecondsSinceEpoch}.json');
    final data = export().map((m) => {
      'queryId': m.queryId,
      'timestamp': m.timestamp.toIso8601String(),
      'embeddingMs': m.embeddingMs,
      'retrievalMs': m.retrievalMs,
      'bypassCheckMs': m.bypassCheckMs,
      'bypassFired': m.bypassFired,
      'inferenceMs': m.inferenceMs,
      'groundingMs': m.groundingMs,
      'totalMs': m.totalMs,
      'topScore': m.topScore,
      'adaptiveThreshold': m.adaptiveThreshold,
      'groundingScore': m.groundingScore,
      'threadCount': m.threadCount,
      'backendType': m.backendType,
    }).toList();
    await file.writeAsString(jsonEncode(data));
    debugPrint('[BENCH] Exported ${data.length} records to ${file.path}');
  }
}
