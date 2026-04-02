import 'dart:io';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';

class HardwareInferenceService extends GetxService {
  InferenceModel? _model;
  bool _isInitialized = false;

  bool get isReady => _isInitialized;

  Future<HardwareInferenceService> init() async {
    await checkInitialStatus();
    return this;
  }

  Future<void> checkInitialStatus() async {
    try {
      final Directory docDir = await getApplicationDocumentsDirectory();
      final String modelPath = '${docDir.path}/gemma-2b.bin';
      
      if (await File(modelPath).exists()) {
        await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
            .fromFile(modelPath)
            .install();
            
        _model = await FlutterGemma.getActiveModel(maxTokens: 1024);
        _isInitialized = true;
      }
    } catch (e) {
      print('⚠️ Hardware LLM Setup: $e');
    }
  }

  /// Downloads the Gemma 2B model using a direct HTTP request for maximum stability
  Future<void> installRealAIBrain({required Function(int) onProgress}) async {
    try {
      final Directory docDir = await getApplicationDocumentsDirectory();
      final String modelPath = '${docDir.path}/gemma-2b.bin';
      
      // Using a PUBLIC Google-hosted mirror (Non-Gated) for maximum compatibility
      const String modelUrl = 'https://storage.googleapis.com/tf_model_garden/models/gemma/gemma-2b-it-gpu-int4.bin';
      
      print('📥 Starting Public Download: $modelUrl');
      
      final dio = Dio();
      // Increase timeout for large 1.2GB file
      dio.options.receiveTimeout = const Duration(minutes: 60); 
      dio.options.sendTimeout = const Duration(minutes: 60);
      
      await dio.download(
        modelUrl,
        modelPath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            onProgress((received / total * 100).toInt());
          }
        },
      );
      
      print('✅ Download Complete. Activating engine...');
          
      // Register with internal engine
      await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
          .fromFile(modelPath)
          .install();
          
      // Reload the engine
      await checkInitialStatus();
    } catch (e) {
      print('❌ Direct Download Error: $e');
      throw 'Download Failed: Please ensure you have stable internet and 1.5GB of free space.';
    }
  }

  /// Streams response from real AI inference (Math / Logic / Freeform)
  Stream<String> getHardwareStream(String prompt) async* {
    if (!_isInitialized || _model == null) {
      yield 'Hardware model not ready.';
      return;
    }
    
    // Create an InferenceChat session to leverage structured tokening.
    final chat = await _model!.createChat(temperature: 0.5, topK: 1);
    
    // Strictly wrap the prompt with Gemma's IT format.
    // Since the .bin might lack native template mapping metadata on this device,
    // we forcefully declare the user and model turns to prevent "auto-complete" hallucination.
    final String formattedPrompt = '<start_of_turn>user\n$prompt<end_of_turn>\n<start_of_turn>model\n';
    await chat.addQuery(Message.text(text: formattedPrompt, isUser: true));

    await for (final response in chat.generateChatResponseAsync()) {
      if (response is TextResponse) {
        yield response.token;
      }
    }
  }
}
