import 'dart:io';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/services/settings_service.dart';

class ModelInfo {
  final String id;
  final String name;
  final String description;
  final String url;
  final String fileName;
  final String sizeLabel;

  ModelInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.url,
    required this.fileName,
    required this.sizeLabel,
  });
}

class ModelSetupController extends GetxController {
  final List<ModelInfo> availableModels = [
    ModelInfo(
      id: 'llama_lite',
      name: 'Llama 3.2 1B (Lite)',
      description: 'Ultra-fast (~1.2s latent), optimized for budget devices. Good for simple tasks.',
      url: 'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-IQ4_XS.gguf?download=true',
      fileName: 'llama-3.2-1b-iq4_xs.gguf',
      sizeLabel: '~742 MB',
    ),
    ModelInfo(
      id: 'phi3_power',
      name: 'Phi-3 Mini 3.8B (Powerhouse)',
      description: 'The Smartest Edge Model. Design for high factual integrity and complex reasoning.',
      // Fixed 404 URL using bartowski's reliable GGUF repository
      url: 'https://huggingface.co/bartowski/Phi-3-mini-4k-instruct-GGUF/resolve/main/Phi-3-mini-4k-instruct-Q4_K_M.gguf?download=true',
      fileName: 'phi-3-mini-4k-q4_k_m.gguf',
      sizeLabel: '~2.39 GB',
    ),
  ];

  final SettingsService _settings = Get.find<SettingsService>();
  final downloadProgress = 0.0.obs;
  final downloadedMB = 0.0.obs;
  final totalMB = 0.0.obs;
  final isDownloading = false.obs;
  final isModelReady = false.obs;
  final modelPath = ''.obs;
  final downloadingModelId = ''.obs;

  final _dio = Dio();
  CancelToken? _cancelToken;

  @override
  void onInit() {
    super.onInit();
    _checkExistingModel();
  }

  Future<void> _checkExistingModel() async {
    final path = await _resolveModelPath();
    if (path != null) {
      modelPath.value = path;
      isModelReady.value = true;
      _settings.updateModel(path); 
    }
  }

  Future<String?> _resolveModelPath() async {
    final dir = await getApplicationDocumentsDirectory();
    final modelDir = Directory('${dir.path}/models');
    if (!modelDir.existsSync()) return null;

    for (var m in availableModels) {
      final path = '${modelDir.path}/${m.fileName}';
      if (File(path).existsSync()) {
        final err = await _validateDownloadedFile(path);
        if (err == null) return path;
      }
    }
    return null;
  }

  Future<void> downloadModel(ModelInfo model) async {
    if (isDownloading.value) return;
    isDownloading.value = true;
    downloadingModelId.value = model.id;
    _cancelToken = CancelToken();

    try {
      final dir = await getApplicationDocumentsDirectory();
      final destPath = '${dir.path}/models/${model.fileName}';
      await Directory('${dir.path}/models').create(recursive: true);

      final partialFile = File('$destPath.part');
      int startByte = 0;

      if (await partialFile.exists()) {
        startByte = await partialFile.length();
      }

      await _dio.download(
        model.url,
        '$destPath.part',
        cancelToken: _cancelToken,
        deleteOnError: false,
        options: Options(
          headers: startByte > 0 ? {'Range': 'bytes=$startByte-'} : null,
          receiveTimeout: const Duration(hours: 4),
          // Ensure we allow redirects for HuggingFace CDN
          followRedirects: true,
          validateStatus: (status) => status != null && status < 500,
        ),
        onReceiveProgress: (received, total) {
          if (total == -1) return; // Unknown size
          final totalSize = (total + startByte).toDouble();
          final downloadedSize = (received + startByte).toDouble();
          downloadedMB.value = downloadedSize / (1024 * 1024);
          totalMB.value = totalSize / (1024 * 1024);
          downloadProgress.value = totalSize > 0 ? downloadedSize / totalSize : 0;
        },
      );

      // Handle 404 effectively if redirected to an error page
      final finalPart = File('$destPath.part');
      if (await finalPart.length() < 1000) { // Tiny file is usually a text error page
         throw DioException(requestOptions: RequestOptions(path: model.url), message: "Resource returned 404 (Not Found)");
      }

      await finalPart.rename(destPath);
      
      final valErr = await _validateDownloadedFile(destPath);
      if (valErr != null) {
        await File(destPath).delete();
        Get.snackbar('❌ Download Corrupt', valErr);
        isDownloading.value = false;
        return;
      }

      modelPath.value = destPath;
      isModelReady.value = true;
      _settings.updateModel(destPath); 
      Get.snackbar('✅ Success', '${model.name} installed successfully!');
    } on DioException catch (e) {
      if (e.type != DioExceptionType.cancel) {
        Get.snackbar('Download Error', e.message ?? 'Unknown error');
      }
    } finally {
      isDownloading.value = false;
      downloadingModelId.value = '';
      _cancelToken = null;
    }
  }

  Future<String?> _validateDownloadedFile(String path) async {
    final file = File(path);
    if (!file.existsSync()) return 'File not found';
    final size = await file.length();
    if (size < 50 * 1024 * 1024) return 'File too small';
    
    final raf = await file.open();
    final header = await raf.read(4);
    await raf.close();
    if (header.length < 4 || 
        header[0] != 0x47 || header[1] != 0x47 || 
        header[2] != 0x55 || header[3] != 0x46) {
      return 'Valid GGUF header not found.';
    }
    return null;
  }

  void cancelDownload() {
    _cancelToken?.cancel('User cancelled');
    isDownloading.value = false;
    downloadingModelId.value = '';
  }

  Future<void> pickLocalModel() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result == null || result.files.single.path == null) return;

    final src = result.files.single.path!;
    final valErr = await _validateDownloadedFile(src);
    if (valErr != null) {
      Get.snackbar('Invalid File', valErr);
      return;
    }

    isDownloading.value = true;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final dest = '${dir.path}/models/${result.files.single.name}';
      await Directory('${dir.path}/models').create(recursive: true);
      await File(src).copy(dest);
      modelPath.value = dest;
      isModelReady.value = true;
      _settings.updateModel(dest);
      Get.snackbar('✅ Registered', 'Custom model copied to app storage.');
    } finally {
      isDownloading.value = false;
    }
  }

  Future<void> deleteModel() async {
    final path = modelPath.value;
    if (path.isEmpty) return;
    try {
      await File(path).delete();
      modelPath.value = '';
      isModelReady.value = false;
      _settings.updateModel('');
    } catch (e) {
      Get.snackbar('Error', 'Could not delete model: $e');
    }
  }
}
