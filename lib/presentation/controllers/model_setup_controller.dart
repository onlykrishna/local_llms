import 'dart:io';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/services/settings_service.dart';

class ModelSetupController extends GetxController {
  static const String _modelUrl =
      'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/'
      'resolve/main/Llama-3.2-1B-Instruct-IQ4_XS.gguf';
  static const String _modelFileName = 'llama-3.2-1b-iq4_xs.gguf';
  static const String _legacyModelFileName = 'llama-3.2-1b-q4.gguf';

  final SettingsService _settings = Get.find<SettingsService>();
  final downloadProgress = 0.0.obs;
  final downloadedMB = 0.0.obs;
  final totalMB = 0.0.obs;
  final isDownloading = false.obs;
  final isModelReady = false.obs;
  final modelPath = ''.obs;

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
      _settings.updateModel(path); // Update global settings
    }
  }

  Future<String?> _resolveModelPath() async {
    final dir = await getApplicationDocumentsDirectory();
    final modelDir = Directory('${dir.path}/models');
    if (!modelDir.existsSync()) return null;

    // Check for Q2 (new default) or Q4 (legacy)
    for (var name in [_modelFileName, _legacyModelFileName]) {
      final path = '${modelDir.path}/$name';
      final file = File(path);
      if (file.existsSync()) {
        final err = await _validateDownloadedFile(path);
        if (err == null) return path;
      }
    }

    // Check external (adb push fallback)
    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        for (var name in [_modelFileName, _legacyModelFileName]) {
          final extPath = '${ext.path}/$name';
          if (File(extPath).existsSync()) {
            final dest = '${modelDir.path}/$name';
            await _migrateToInternal(extPath, dest);
            return dest;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _migrateToInternal(String src, String dest) async {
    final destFile = File(dest);
    await destFile.parent.create(recursive: true);
    await File(src).copy(dest);
  }

  /// Option A: Auto-download from HuggingFace (no login required).
  Future<void> downloadModel() async {
    if (isDownloading.value) return;
    isDownloading.value = true;
    _cancelToken = CancelToken();

    try {
      final dir = await getApplicationDocumentsDirectory();
      final destPath = '${dir.path}/models/$_modelFileName';
      await Directory('${dir.path}/models').create(recursive: true);

      final partialFile = File('$destPath.part');
      int startByte = 0;

      // Resume support
      if (await partialFile.exists()) {
        startByte = await partialFile.length();
      }

      await _dio.download(
        _modelUrl,
        '$destPath.part',
        cancelToken: _cancelToken,
        deleteOnError: false,
        options: Options(
          headers: startByte > 0 ? {'Range': 'bytes=$startByte-'} : null,
          receiveTimeout: const Duration(hours: 2),
        ),
        onReceiveProgress: (received, total) {
          final totalSize = (total + startByte).toDouble();
          final downloadedSize = (received + startByte).toDouble();
          downloadedMB.value = downloadedSize / (1024 * 1024);
          totalMB.value = totalSize / (1024 * 1024);
          downloadProgress.value =
              totalSize > 0 ? downloadedSize / totalSize : 0;
        },
      );

      // Rename .part → final
      await partialFile.rename(destPath);
      
      // Post-download integrity check
      final valErr = await _validateDownloadedFile(destPath);
      if (valErr != null) {
        await File(destPath).delete();
        Get.snackbar('❌ Download Corrupt', valErr);
        isDownloading.value = false;
        return;
      }

      modelPath.value = destPath;
      isModelReady.value = true;
      _settings.updateModel(destPath); // Update global settings
      Get.snackbar('✅ Model Ready', 'Llama 3.2 1B (IQ4_XS) installed successfully!');
    } on DioException catch (e) {
      if (e.type != DioExceptionType.cancel) {
        Get.snackbar('Download Error', e.message ?? 'Unknown error');
      }
    } finally {
      isDownloading.value = false;
      _cancelToken = null;
    }
  }

  Future<String?> _validateDownloadedFile(String path) async {
    final file = File(path);
    if (!file.existsSync()) return 'File not found';
    final size = await file.length();
    if (size < 100 * 1024 * 1024) return 'File too small';
    
    // Check GGUF magic bytes: 0x47475546
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
  }

  /// Option B: Manual file picker.
  Future<void> pickLocalModel() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result == null || result.files.single.path == null) return;

    final src = result.files.single.path!;
    final srcFile = File(src);
    
    // Validate before copying
    final valErr = await _validateDownloadedFile(src);
    if (valErr != null) {
      Get.snackbar('Invalid File', valErr);
      return;
    }

    isDownloading.value = true;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final dest = '${dir.path}/models/$_modelFileName';
      await Directory('${dir.path}/models').create(recursive: true);
      await srcFile.copy(dest);
      modelPath.value = dest;
      isModelReady.value = true;
      _settings.updateModel(dest); // Update global settings
      Get.snackbar('✅ Model Registered', 'Model successfully copied to app storage.');
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
    } catch (e) {
      Get.snackbar('Error', 'Could not delete model: $e');
    }
  }
}
