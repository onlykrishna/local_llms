import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:llamadart/llamadart.dart';
import 'inference_backend.dart';
import 'inference_isolate.dart';

/// An implementation of [InferenceBackend] that uses the `llamadart` package.
/// This class manages the isolate where the actual llama.cpp engine runs.
class LlamaDartBackend implements InferenceBackend {
  Isolate? _isolate;
  SendPort? _isolateSendPort;
  ReceivePort? _mainReceivePort;
  bool _isReady = false;
  
  final Completer<void> _isolateReady = Completer<void>();

  @override
  bool get isReady => _isReady;

  @override
  Future<void> loadModel(String modelPath, InferenceConfig config, {String? dbPath}) async {
    if (_isolate == null) {
      if (dbPath == null) throw Exception('dbPath is required for inference isolate initialization');
      await _startIsolate(modelPath, config, dbPath);
    }
    _isReady = true;
  }

  @override
  Stream<String> generate(String prompt, {Map<String, dynamic>? data}) async* {
    if (!_isReady || _isolateSendPort == null) {
      throw Exception('Model not loaded');
    }

    final responsePort = ReceivePort();
    _isolateSendPort!.send(IsolateRequest('generate', {
      'prompt': prompt,
      if (data != null) ...data,
    }, responsePort.sendPort));

    await for (final response in responsePort.map((r) => r as IsolateResponse)) {
      if (response.isError) {
        throw Exception(response.data);
      }
      if (response.isDone) break;
      if (response.data != null) {
        yield response.data as String;
      }
    }
    responsePort.close();
  }

  @override
  Future<void> cancel() async {
    _isolateSendPort?.send(IsolateRequest('cancel', null, ReceivePort().sendPort));
  }

  @override
  Future<void> dispose() async {
    _isReady = false;
    _isolateSendPort?.send(const ShutdownMessage());
    // Give it a moment to clean up before killing
    await Future.delayed(const Duration(milliseconds: 500));
    _isolate?.kill(priority: Isolate.immediate);
    _mainReceivePort?.close();
    _isolate = null;
    _isolateSendPort = null;
  }

  Future<void> _startIsolate(String modelPath, InferenceConfig config, String dbPath) async {
    _mainReceivePort = ReceivePort();
    
    final args = InferenceIsolateArgs(
      sendPort: _mainReceivePort!.sendPort,
      dbPath: dbPath,
      modelPath: modelPath,
      config: config,
    );

    _isolate = await Isolate.spawn(inferenceIsolateEntryPoint, args);
    
    // Ordered initialization:
    // 1. Receive the communication SendPort
    // 2. Receive IsolateReadyMessage or IsolateInitError
    
    final completer = Completer<void>();
    StreamSubscription? sub;
    
    sub = _mainReceivePort!.listen((message) {
      if (message is SendPort) {
        _isolateSendPort = message;
      } else if (message is IsolateReadyMessage) {
        sub?.cancel();
        completer.complete();
      } else if (message is IsolateInitError) {
        sub?.cancel();
        completer.completeError(Exception(message.message));
      }
    });

    try {
      await completer.future;
    } catch (e) {
      _isolate?.kill(priority: Isolate.immediate);
      _isolate = null;
      rethrow;
    }
  }
}

/// A low-level implementation of [InferenceBackend] that wraps raw `llamadart` calls.
/// This class is designed to run inside an isolate.
class LlamaDartNativeBackend implements InferenceBackend {
  LlamaBackend? _backend;
  int? _modelHandle;
  int? _contextHandle;
  bool _isReady = false;

  @override
  bool get isReady => _isReady;

  @override
  Future<void> loadModel(String modelPath, InferenceConfig config, {String? dbPath}) async {
    _backend?.dispose();
    _backend = LlamaBackend();
    
    final params = ModelParams(
      gpuLayers: config.gpuLayers,
      contextSize: config.contextSize,
      numberOfThreads: config.numberOfThreads,
      batchSize: config.batchSize,
    );
    
    _modelHandle = await _backend!.modelLoad(modelPath, params);
    _contextHandle = await _backend!.contextCreate(_modelHandle!, params);
    _isReady = true;
  }

  @override
  Stream<String> generate(String prompt, {Map<String, dynamic>? data}) async* {
    if (_backend == null || _contextHandle == null) {
      throw Exception('Not initialized');
    }

    // We don't have GenerationConfig yet in the interface, so we use some defaults
    // or we could extend InferenceConfig to include them.
    final gParams = GenerationParams(
      maxTokens: 512,
      temp: 0.7,
      stopSequences: ['###', '<|eot_id|>', '<|end_of_text|>'],
    );

    await for (final chunk in _backend!.generate(_contextHandle!, prompt, gParams)) {
      if (chunk.isNotEmpty) {
        yield utf8.decode(chunk);
      }
    }
  }

  @override
  Future<void> cancel() async {
    _backend?.cancelGeneration();
  }

  @override
  Future<void> dispose() async {
    if (_contextHandle != null) await _backend?.contextFree(_contextHandle!);
    if (_modelHandle != null) await _backend?.modelFree(_modelHandle!);
    _backend?.dispose();
    _backend = null;
    _modelHandle = null;
    _contextHandle = null;
    _isReady = false;
  }
}
