import 'dart:async';

/// Configuration for LLM inference engines.
class InferenceConfig {
  final int gpuLayers;
  final int contextSize;
  final int numberOfThreads;
  final int batchSize;
  final double temperature;
  final int maxTokens;

  const InferenceConfig({
    this.gpuLayers = 99,
    this.contextSize = 2048,
    this.numberOfThreads = 4,
    this.batchSize = 512,
    this.temperature = 0.7,
    this.maxTokens = 512,
  });
}

/// Abstract interface for LLM inference backends.
/// Allows swapping between llamadart, native bridges, or cloud APIs.
abstract class InferenceBackend {
  /// Load model from [modelPath]. Must be called before generate().
  /// [dbPath] is optional and used for local DB attachment in the inference isolate.
  Future<void> loadModel(String modelPath, InferenceConfig config, {String? dbPath});

  /// Generate a response stream for [prompt].
  /// [data] can be used for implementation-specific optimizations (e.g. RAG IDs).
  /// Yields tokens as they are produced.
  Stream<String> generate(String prompt, {Map<String, dynamic>? data});

  /// Cancel any in-progress generation. Safe to call if idle.
  Future<void> cancel();

  /// Release all native resources. After this, loadModel() must be called again.
  Future<void> dispose();

  /// True if a model is loaded and ready to accept generate() calls.
  bool get isReady;
}
