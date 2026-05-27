import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:offline_ai_flutter_demo/core/services/log_service.dart';
import 'inference_backend.dart';

// --- FFI Type Definitions ---

typedef LlamaModelPtr = Pointer<Void>;
typedef LlamaContextPtr = Pointer<Void>;
typedef LlamaVocabPtr = Pointer<Void>;
typedef LlamaToken = Int32;

// Opaque handles
final class LlamaModel extends Opaque {}
final class LlamaContext extends Opaque {}
final class LlamaVocab extends Opaque {}
final class LlamaSampler extends Opaque {}

// Structs for parameters
final class LlamaModelParams extends Struct {
  external Pointer<Void> devices;
  external Pointer<Void> tensor_buft_overrides;
  @Int32()
  external int n_gpu_layers;
  @Uint32()
  external int split_mode;
  @Int32()
  external int main_gpu;
  external Pointer<Float> tensor_split;
  external Pointer<Void> progress_callback;
  external Pointer<Void> progress_callback_user_data;
  external Pointer<Void> kv_overrides;
  @Bool()
  external bool vocab_only;
  @Bool()
  external bool use_mmap;
  @Bool()
  external bool use_direct_io;
  @Bool()
  external bool use_mlock;
  @Bool()
  external bool check_tensors;
  @Bool()
  external bool use_extra_bufts;
  @Bool()
  external bool no_host;
  @Bool()
  external bool no_alloc;
}

final class LlamaContextParams extends Struct {
  @Uint32()
  external int n_ctx;
  @Uint32()
  external int n_batch;
  @Uint32()
  external int n_ubatch;
  @Uint32()
  external int n_seq_max;
  @Int32()
  external int n_threads;
  @Int32()
  external int n_threads_batch;
  @Int32()
  external int rope_scaling_type;
  @Int32()
  external int pooling_type;
  @Int32()
  external int attention_type;
  @Int32()
  external int flash_attn_type;
  @Float()
  external double rope_freq_base;
  @Float()
  external double rope_freq_scale;
  @Float()
  external double yarn_ext_factor;
  @Float()
  external double yarn_attn_factor;
  @Float()
  external double yarn_beta_fast;
  @Float()
  external double yarn_beta_slow;
  @Uint32()
  external int yarn_orig_ctx;
  @Float()
  external double defrag_thold;
  external Pointer<Void> cb_eval;
  external Pointer<Void> cb_eval_user_data;
  @Uint32()
  external int type_k;
  @Uint32()
  external int type_v;
  external Pointer<Void> abort_callback;
  external Pointer<Void> abort_callback_data;
  @Bool()
  external bool embeddings;
  @Bool()
  external bool offload_kqv;
  @Bool()
  external bool no_perf;
  @Bool()
  external bool op_offload;
  @Bool()
  external bool swa_full;
  @Bool()
  external bool kv_unified;
  external Pointer<Void> samplers;
  @Size()
  external int n_samplers;
}

final class LlamaBatch extends Struct {
  @Int32()
  external int n_tokens;
  external Pointer<LlamaToken> token;
  external Pointer<Float> embd;
  external Pointer<Int32> pos;
  external Pointer<Int32> n_seq_id;
  external Pointer<Pointer<Int32>> seq_id;
  external Pointer<Int8> logits;
}

// C Function Typedefs
typedef llama_backend_init_native = Void Function();
typedef LlamaBackendInit = void Function();

typedef llama_model_default_params_native = LlamaModelParams Function();
typedef LlamaModelDefaultParams = LlamaModelParams Function();

typedef llama_context_default_params_native = LlamaContextParams Function();
typedef LlamaContextDefaultParams = LlamaContextParams Function();

typedef llama_load_model_from_file_native = Pointer<LlamaModel> Function(Pointer<Utf8>, LlamaModelParams);
typedef LlamaLoadModelFromFile = Pointer<LlamaModel> Function(Pointer<Utf8>, LlamaModelParams);

typedef llama_new_context_with_model_native = Pointer<LlamaContext> Function(Pointer<LlamaModel>, LlamaContextParams);
typedef LlamaNewContextWithModel = Pointer<LlamaContext> Function(Pointer<LlamaModel>, LlamaContextParams);

typedef llama_model_get_vocab_native = Pointer<LlamaVocab> Function(Pointer<LlamaModel>);
typedef LlamaModelGetVocab = Pointer<LlamaVocab> Function(Pointer<LlamaModel>);

typedef llama_tokenize_native = Int32 Function(Pointer<LlamaVocab>, Pointer<Char>, Int32, Pointer<LlamaToken>, Int32, Bool, Bool);
typedef LlamaTokenize = int Function(Pointer<LlamaVocab>, Pointer<Char>, int, Pointer<LlamaToken>, int, bool, bool);

typedef llama_batch_get_one_native = LlamaBatch Function(Pointer<LlamaToken>, Int32);
typedef LlamaBatchGetOne = LlamaBatch Function(Pointer<LlamaToken>, int);

typedef llama_decode_native = Int32 Function(Pointer<LlamaContext>, LlamaBatch);
typedef LlamaDecode = int Function(Pointer<LlamaContext>, LlamaBatch);

typedef llama_sampler_init_greedy_native = Pointer<LlamaSampler> Function();
typedef LlamaSamplerInitGreedy = Pointer<LlamaSampler> Function();

typedef llama_sampler_init_temp_native = Pointer<LlamaSampler> Function(Float);
typedef LlamaSamplerInitTemp = Pointer<LlamaSampler> Function(double);

typedef llama_sampler_sample_native = Int32 Function(Pointer<LlamaSampler>, Pointer<LlamaContext>, Int32);
typedef LlamaSamplerSample = int Function(Pointer<LlamaSampler>, Pointer<LlamaContext>, int);

typedef llama_token_to_piece_native = Int32 Function(Pointer<LlamaVocab>, Int32, Pointer<Char>, Int32, Int32, Bool);
typedef LlamaTokenToPiece = int Function(Pointer<LlamaVocab>, int, Pointer<Char>, int, int, bool);

typedef llama_free_native = Void Function(Pointer<LlamaContext>);
typedef LlamaFree = void Function(Pointer<LlamaContext>);

typedef llama_model_free_native = Void Function(Pointer<LlamaModel>);
typedef LlamaModelFree = void Function(Pointer<LlamaModel>);

typedef llama_sampler_free_native = Void Function(Pointer<LlamaSampler>);
typedef LlamaSamplerFree = void Function(Pointer<LlamaSampler>);

/// A high-performance [InferenceBackend] using a direct dart:ffi bridge to llama.cpp.
class NativeLlamaCppBackend implements InferenceBackend {
  late final DynamicLibrary _lib;
  
  // Lookups
  late final LlamaBackendInit _llamaBackendInit;
  late final LlamaModelDefaultParams _llamaModelDefaultParams;
  late final LlamaContextDefaultParams _llamaContextDefaultParams;
  late final LlamaLoadModelFromFile _llamaLoadModelFromFile;
  late final LlamaNewContextWithModel _llamaNewContextWithModel;
  late final LlamaModelGetVocab _llamaModelGetVocab;
  late final LlamaTokenize _llamaTokenize;
  late final LlamaBatchGetOne _llamaBatchGetOne;
  late final LlamaDecode _llamaDecode;
  late final LlamaSamplerSample _llamaSamplerSample;
  late final LlamaTokenToPiece _llamaTokenToPiece;
  late final LlamaFree _llamaFree;
  late final LlamaModelFree _llamaModelFree;
  late final LlamaSamplerInitGreedy _llamaSamplerInitGreedy;
  late final LlamaSamplerFree _llamaSamplerFree;

  Pointer<LlamaModel>? _model;
  Pointer<LlamaContext>? _context;
  Pointer<LlamaVocab>? _vocab;
  bool _isReady = false;
  bool _cancelled = false;

  NativeLlamaCppBackend() {
    _lib = Platform.isAndroid
        ? DynamicLibrary.open('libllama.so')
        : DynamicLibrary.process();

    _llamaBackendInit = _lib.lookupFunction<llama_backend_init_native, LlamaBackendInit>('llama_backend_init');
    _llamaModelDefaultParams = _lib.lookupFunction<llama_model_default_params_native, LlamaModelDefaultParams>('llama_model_default_params');
    _llamaContextDefaultParams = _lib.lookupFunction<llama_context_default_params_native, LlamaContextDefaultParams>('llama_context_default_params');
    _llamaLoadModelFromFile = _lib.lookupFunction<llama_load_model_from_file_native, LlamaLoadModelFromFile>('llama_load_model_from_file');
    _llamaNewContextWithModel = _lib.lookupFunction<llama_new_context_with_model_native, LlamaNewContextWithModel>('llama_new_context_with_model');
    _llamaModelGetVocab = _lib.lookupFunction<llama_model_get_vocab_native, LlamaModelGetVocab>('llama_model_get_vocab');
    _llamaTokenize = _lib.lookupFunction<llama_tokenize_native, LlamaTokenize>('llama_tokenize');
    _llamaBatchGetOne = _lib.lookupFunction<llama_batch_get_one_native, LlamaBatchGetOne>('llama_batch_get_one');
    _llamaDecode = _lib.lookupFunction<llama_decode_native, LlamaDecode>('llama_decode');
    _llamaSamplerSample = _lib.lookupFunction<llama_sampler_sample_native, LlamaSamplerSample>('llama_sampler_sample');
    _llamaTokenToPiece = _lib.lookupFunction<llama_token_to_piece_native, LlamaTokenToPiece>('llama_token_to_piece');
    _llamaFree = _lib.lookupFunction<llama_free_native, LlamaFree>('llama_free');
    _llamaModelFree = _lib.lookupFunction<llama_model_free_native, LlamaModelFree>('llama_model_free');
    _llamaSamplerInitGreedy = _lib.lookupFunction<llama_sampler_init_greedy_native, LlamaSamplerInitGreedy>('llama_sampler_init_greedy');
    _llamaSamplerFree = _lib.lookupFunction<llama_sampler_free_native, LlamaSamplerFree>('llama_sampler_free');
  }

  @override
  bool get isReady => _isReady;

  @override
  Future<void> loadModel(String modelPath, InferenceConfig config, {String? dbPath}) async {
    await dispose(); // Clean up existing if any

    LogService.to.log('[NativeInference] Initializing backend...');
    _llamaBackendInit();

    final modelParams = _llamaModelDefaultParams();
    
    LogService.to.log('[NativeInference] Default Model Params:');
    LogService.to.log('  - n_gpu_layers: ${modelParams.n_gpu_layers}');
    LogService.to.log('  - vocab_only: ${modelParams.vocab_only}');
    LogService.to.log('  - use_mmap: ${modelParams.use_mmap}');
    LogService.to.log('  - use_mlock: ${modelParams.use_mlock}');
    LogService.to.log('  - split_mode: ${modelParams.split_mode}');
    LogService.to.log('  - main_gpu: ${modelParams.main_gpu}');

    // Use what was requested, but log it
    modelParams.n_gpu_layers = config.gpuLayers;
    modelParams.use_mmap = true;
    
    // ─── Pre-flight checks ───────────────────────────────────────────
    final modelFile = File(modelPath);

    // 1. Existence check
    if (!await modelFile.exists()) {
      throw Exception(
        '[NativeInference] FATAL: Model file not found at $modelPath\n'
        'Check that the file was copied to app_flutter/models/ correctly.\n'
        'Run: adb shell ls -la /data/user/0/com.example.offline_ai_flutter_demo/app_flutter/models/'
      );
    }

    // 2. Size check — IQ4_XS quantized Llama 3.2 1B should be ~800MB-1.1GB
    final fileSize = await modelFile.length();
    final fileSizeMb = fileSize / (1024 * 1024);
    LogService.to.log('[NativeInference] Model file found: ${fileSizeMb.toStringAsFixed(1)}MB');

    if (fileSizeMb < 100) {
      throw Exception(
        '[NativeInference] FATAL: Model file is only ${fileSizeMb.toStringAsFixed(1)}MB — '
        'likely a failed/partial download. Expected ~800MB-1.1GB for IQ4_XS 1B model.'
      );
    }

    // 3. GGUF magic number check — first 4 bytes must be 0x47475546 ("GGUF")
    final raf = await modelFile.open();
    final header = await raf.read(4);
    await raf.close();
    final magic = String.fromCharCodes(header);
    LogService.to.log('[NativeInference] File header magic: $magic (expected: GGUF)');
    if (magic != 'GGUF') {
      throw Exception(
        '[NativeInference] FATAL: File at $modelPath is not a valid GGUF file. '
        'Magic bytes: ${header.map((b) => b.toRadixString(16).padLeft(2, "0")).join(" ")}'
      );
    }

    // 4. Available memory check
    final memInfo = ProcessInfo.currentRss;
    LogService.to.log('[NativeInference] Current RSS: ${(memInfo / 1024 / 1024).toStringAsFixed(0)}MB');
    // ─────────────────────────────────────────────────────────────────

    final pathPtr = modelPath.toNativeUtf8();
    try {
      _model = _llamaLoadModelFromFile(pathPtr, modelParams);
      
      if (_model == null || _model!.address == 0) {
        LogService.to.log('[NativeInference] Model load failed (null pointer). Retrying with 0 GPU layers...');
        modelParams.n_gpu_layers = 0;
        _model = _llamaLoadModelFromFile(pathPtr, modelParams);
      }

      if (_model == null || _model!.address == 0) {
        LogService.to.log('[NativeInference] ERROR: Model load returned NULL after all retries');
        throw Exception(
          'Failed to load model from $modelPath\n'
          'Run these ADB commands to diagnose:\n'
          '  adb shell ls -la /data/user/0/com.example.offline_ai_flutter_demo/app_flutter/models/\n'
          '  adb shell cat /proc/\${pid}/status | grep VmRSS\n'
          'If file is missing, check your model copy logic in StartupController.'
        );
      }

      LogService.to.log('[NativeInference] Model loaded successfully at ${_model!.address}. Creating context...');
      
      _vocab = _llamaModelGetVocab(_model!);

      final cParams = _llamaContextDefaultParams();
      cParams.n_ctx = config.contextSize;
      cParams.n_threads = config.numberOfThreads;
      cParams.n_batch = config.batchSize;
      // Ensure ubatch is at least 1 and not more than batch
      cParams.n_ubatch = config.batchSize; 

      _context = _llamaNewContextWithModel(_model!, cParams);
      if (_context == null || _context!.address == 0) {
        throw Exception('Failed to create context');
      }

      LogService.to.log('[NativeInference] Context created successfully (n_ctx: ${cParams.n_ctx})');
      _isReady = true;
    } catch (e) {
      LogService.to.log('[NativeInference] Critical Error during load: $e');
      rethrow;
    } finally {
      malloc.free(pathPtr);
    }
  }

  @override
  Stream<String> generate(String prompt, {Map<String, dynamic>? data}) {
    if (!_isReady || _model == null || _context == null) {
      throw Exception('Backend not ready');
    }

    final controller = StreamController<String>();
    _cancelled = false;

    // Run the decode loop in a separate isolate to prevent blocking the UI
    _runDecodeLoop(prompt, controller, data);

    return controller.stream;
  }

  Future<void> _runDecodeLoop(String prompt, StreamController<String> controller, Map<String, dynamic>? data) async {
    final receivePort = ReceivePort();
    
    // Pass pointers as addresses
    final args = {
      'libPath': Platform.isAndroid ? 'libllama.so' : null,
      'modelAddr': _model!.address,
      'contextAddr': _context!.address,
      'vocabAddr': _vocab!.address,
      'prompt': prompt,
      'replyPort': receivePort.sendPort,
    };

    final isolate = await Isolate.spawn(_decodeIsolateEntry, args);

    receivePort.listen((message) {
      if (message is String) {
        controller.add(message);
      } else if (message == 'DONE') {
        controller.close();
        receivePort.close();
        isolate.kill();
      } else if (message is Map && message['error'] != null) {
        controller.addError(message['error']);
        controller.close();
        receivePort.close();
        isolate.kill();
      }
    });

    // Listen for cancellation
    controller.onCancel = () {
      _cancelled = true;
      isolate.kill();
      controller.close();
      receivePort.close();
    };
  }

  static void _decodeIsolateEntry(Map<String, dynamic> args) {
    final libPath = args['libPath'] as String?;
    final modelAddr = args['modelAddr'] as int;
    final contextAddr = args['contextAddr'] as int;
    final vocabAddr = args['vocabAddr'] as int;
    final prompt = args['prompt'] as String;
    final replyPort = args['replyPort'] as SendPort;

    final lib = libPath != null ? DynamicLibrary.open(libPath) : DynamicLibrary.process();

    // Lookups in Isolate
    final llamaBackendInit = lib.lookupFunction<llama_backend_init_native, LlamaBackendInit>('llama_backend_init');
    final llamaTokenize = lib.lookupFunction<llama_tokenize_native, LlamaTokenize>('llama_tokenize');
    final llamaBatchGetOne = lib.lookupFunction<llama_batch_get_one_native, LlamaBatchGetOne>('llama_batch_get_one');
    final llamaDecode = lib.lookupFunction<llama_decode_native, LlamaDecode>('llama_decode');
    final llamaSamplerInitGreedy = lib.lookupFunction<llama_sampler_init_greedy_native, LlamaSamplerInitGreedy>('llama_sampler_init_greedy');
    final llamaSamplerSample = lib.lookupFunction<llama_sampler_sample_native, LlamaSamplerSample>('llama_sampler_sample');
    final llamaTokenToPiece = lib.lookupFunction<llama_token_to_piece_native, LlamaTokenToPiece>('llama_token_to_piece');
    final llamaSamplerFree = lib.lookupFunction<llama_sampler_free_native, LlamaSamplerFree>('llama_sampler_free');

    final model = Pointer<LlamaModel>.fromAddress(modelAddr);
    final context = Pointer<LlamaContext>.fromAddress(contextAddr);
    final vocab = Pointer<LlamaVocab>.fromAddress(vocabAddr);

    try {
      llamaBackendInit();

      const maxTokens = 2048;
      final tokens = malloc<LlamaToken>(maxTokens);
      final promptPtr = prompt.toNativeUtf8();
      
      try {
        final nTokens = llamaTokenize(vocab, promptPtr.cast<Char>(), prompt.length, tokens, maxTokens, true, true);
        if (nTokens < 0) {
          replyPort.send({'error': 'Tokenization failed'});
          return;
        }

        final sampler = llamaSamplerInitGreedy();
        try {
          // 1. Initial decode of prompt tokens
          for (var i = 0; i < nTokens; i++) {
            final batch = llamaBatchGetOne(tokens + i, 1);
            llamaDecode(context, batch);
          }

          // 2. Generation loop
          int tokensGenerated = 0;
          final pieceBuf = malloc<Char>(256);
          
          while (tokensGenerated < 512) {
            final id = llamaSamplerSample(sampler, context, -1);
            
            if (id == 2) break; // Common EOS

            final nPiece = llamaTokenToPiece(vocab, id, pieceBuf, 256, 0, false);
            if (nPiece > 0) {
              final piece = pieceBuf.cast<Utf8>().toDartString(length: nPiece);
              replyPort.send(piece);
            }

            final nextTokenPtr = malloc<LlamaToken>(1)..value = id;
            final nextBatch = llamaBatchGetOne(nextTokenPtr, 1);
            if (llamaDecode(context, nextBatch) != 0) {
              malloc.free(nextTokenPtr);
              break;
            }
            malloc.free(nextTokenPtr);
            tokensGenerated++;
          }
          
          replyPort.send('DONE');
          malloc.free(pieceBuf);
        } finally {
          llamaSamplerFree(sampler);
        }
      } finally {
        malloc.free(tokens);
        malloc.free(promptPtr);
      }
    } catch (e) {
      replyPort.send({'error': e.toString()});
    }
  }



  @override
  Future<void> cancel() async {
    _cancelled = true;
  }

  @override
  Future<void> dispose() async {
    _isReady = false;
    if (_context != null && _context!.address != 0) {
      _llamaFree(_context!);
      _context = null;
    }
    if (_model != null && _model!.address != 0) {
      _llamaModelFree(_model!);
      _model = null;
    }
  }
}
