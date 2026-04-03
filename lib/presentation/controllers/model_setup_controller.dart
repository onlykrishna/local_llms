import 'dart:io';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

class ModelSetupController extends GetxController {
  static const String _modelUrl =
      'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/'
      'resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf';
  static const String _modelFileName = 'llama-3.2-1b-q4.gguf';

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
    }
  }

  Future<String?> _resolveModelPath() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/models/$_modelFileName';
    final file = File(path);

    if (await file.exists()) {
      final size = await file.length();
      if (size > 200 * 1024 * 1024) return path; // >200MB = valid
    }

    // Check external (adb push fallback)
    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        final extPath = '${ext.path}/$_modelFileName';
        if (await File(extPath).exists()) {
          await _migrateToInternal(extPath, path);
          return path;
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
      modelPath.value = destPath;
      isModelReady.value = true;
      Get.snackbar('✅ Model Ready', 'Llama 3.2 1B installed successfully!');
    } on DioException catch (e) {
      if (e.type != DioExceptionType.cancel) {
        Get.snackbar('Download Error', e.message ?? 'Unknown error');
      }
    } finally {
      isDownloading.value = false;
      _cancelToken = null;
    }
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
    final size = await srcFile.length();

    if (size < 200 * 1024 * 1024) {
      Get.snackbar('Invalid File',
          'File is too small (${(size / (1024 * 1024)).toStringAsFixed(0)} MB). Expected ~650MB+.');
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
