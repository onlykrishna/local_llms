import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../core/models/model_registry.dart';
import '../models/model_download_progress.dart';

class ModelDownloadService extends GetxService {
  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 60),
    receiveTimeout: const Duration(seconds: 60), // detect hangs faster
    sendTimeout: const Duration(seconds: 60),
  ));
  
  static const int _maxRedirects = 15;
  static const int _bufferSize = 1024 * 1024; // 1MB Buffer for faster I/O
  final RxMap<String, ModelDownloadProgress> _progress = <String, ModelDownloadProgress>{}.obs;
  final Map<String, CancelToken> _cancelTokens = {};
  
  // Single active download queue
  String? _activeModelId;

  Stream<ModelDownloadProgress> progressStream(String modelId) async* {
    yield _progress[modelId] ?? ModelDownloadProgress.initial(modelId);
    yield* _progress.stream.map((map) => map[modelId] ?? ModelDownloadProgress.initial(modelId));
  }

  Future<ModelDownloadService> init() async {
    // Check existing files on startup
    await _syncDownloadedModels();
    return this;
  }

  Future<void> _syncDownloadedModels() async {
    final dir = await getApplicationDocumentsDirectory();
    final modelDir = Directory('${dir.path}/models');
    if (!modelDir.existsSync()) return;

    final files = await modelDir.list().toList();
    
    // Parallelize file stats gathering for faster launch
    await Future.wait(files.map((f) async {
      if (f is File && f.path.endsWith('.gguf')) {
        final fileName = f.path.split('/').last;
        final model = ModelRegistry.models.firstWhereOrNull((m) => m.fileName == fileName);
        if (model != null) {
          final length = await f.length();
          _progress[model.id] = ModelDownloadProgress(
            modelId: model.id,
            bytesReceived: length,
            totalBytes: model.sizeBytes,
            percent: 1.0,
            status: DownloadStatus.completed,
          );
        }
      }
    }));
  }

  Future<void> startDownload(String modelId) async {
    if (_activeModelId != null && _activeModelId != modelId) {
      Get.snackbar('Queue', 'A download is already in progress. Please wait.');
      return;
    }

    final model = ModelRegistry.models.firstWhereOrNull((m) => m.id == modelId);
    if (model == null) return;

    _activeModelId = modelId;
    _progress[modelId] = _progress[modelId]?.copyWith(status: DownloadStatus.downloading) 
        ?? ModelDownloadProgress.initial(modelId).copyWith(status: DownloadStatus.downloading);

    final cancelToken = CancelToken();
    _cancelTokens[modelId] = cancelToken;

    int attempts = 0;
    bool success = false;
    
    while (attempts < 3 && !success) {
      try {
        final dir = await getApplicationDocumentsDirectory();
        final modelFilePath = '${dir.path}/models/${model.fileName}';
        final partialFilePath = '$modelFilePath.part';
        
        final partialFile = File(partialFilePath);
        int startByte = 0;
        if (await partialFile.exists()) {
          startByte = await partialFile.length();
        }

        await Directory('${dir.path}/models').create(recursive: true);

        DateTime lastUpdate = DateTime.now();

        await _dio.download(
          model.downloadUrl,
          partialFilePath,
          cancelToken: cancelToken,
          deleteOnError: false,
          options: Options(
            headers: startByte > 0 ? {'Range': 'bytes=$startByte-'} : null,
            followRedirects: true,
            maxRedirects: _maxRedirects,
            validateStatus: (status) => status != null && (status < 400 || status == 416),
          ),
          onReceiveProgress: (received, total) {
            final now = DateTime.now();
            if (now.difference(lastUpdate).inMilliseconds < 500 && received != total) {
              return;
            }
            lastUpdate = now;

            final totalDownloaded = received + startByte;
            final knownTotal = (total != -1) ? total : (model.sizeBytes - startByte);
            final fullSize = knownTotal + startByte;

            _progress[modelId] = ModelDownloadProgress(
              modelId: modelId,
              bytesReceived: totalDownloaded,
              totalBytes: fullSize,
              percent: fullSize > 0
                  ? (totalDownloaded / fullSize).clamp(0.0, 1.0)
                  : 0.0,
              status: DownloadStatus.downloading,
            );
          },
        );

        // Verify header
        _progress[modelId] = _progress[modelId]!.copyWith(status: DownloadStatus.verifying);
        final validationErr = await _validateGGUFHeader(partialFilePath);
        if (validationErr != null) {
          // If validation fails, delete the partial file so we don't keep retrying on corruption
          if (await File(partialFilePath).exists()) {
            await File(partialFilePath).delete();
          }
          throw Exception('Validation failed: $validationErr');
        }

        // Rename from .part to .gguf
        await File(partialFilePath).rename(modelFilePath);
        _progress[modelId] = _progress[modelId]!.copyWith(
          status: DownloadStatus.completed,
          percent: 1.0,
        );
        _activeModelId = null;
        success = true;

      } catch (e) {
        if (e is DioException && e.type == DioExceptionType.cancel) {
          _progress[modelId] = _progress[modelId]!.copyWith(status: DownloadStatus.paused);
          _activeModelId = null;
          return; // User cancelled, don't retry
        }
        
        attempts++;
        if (attempts >= 3) {
          String errMsg = e.toString();
          if (e is DioException) {
             errMsg = 'Network Error: ${e.type.name}';
             if (e.type == DioExceptionType.connectionTimeout) errMsg = 'Connection Timeout. HF is slow.';
          }
          
          _progress[modelId] = _progress[modelId]!.copyWith(
            status: DownloadStatus.failed,
            error: errMsg,
          );
          Get.snackbar('Download Failed', errMsg, 
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.red.withOpacity(0.8),
            colorText: Colors.white);
          _activeModelId = null;
          rethrow;
        }
        
        // Wait before retry
        await Future.delayed(Duration(seconds: 2 * attempts));
      }
    }
    _cancelTokens.remove(modelId);
  }

  Future<void> pauseDownload(String modelId) async {
    _cancelTokens[modelId]?.cancel('Paused by user');
  }

  Future<void> resumeDownload(String modelId) async {
    await startDownload(modelId);
  }

  Future<void> cancelDownload(String modelId) async {
    _cancelTokens[modelId]?.cancel('Cancelled');
    final dir = await getApplicationDocumentsDirectory();
    final model = ModelRegistry.models.firstWhereOrNull((m) => m.id == modelId);
    if (model == null) return;
    
    final partialFile = File('${dir.path}/models/${model.fileName}.part');
    if (await partialFile.exists()) {
      await partialFile.delete();
    }
    _progress[modelId] = ModelDownloadProgress.initial(modelId);
  }

  Future<void> deleteModel(String modelId) async {
    final model = ModelRegistry.models.firstWhereOrNull((m) => m.id == modelId);
    if (model == null) return;

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/models/${model.fileName}');
    if (await file.exists()) {
      await file.delete();
    }
    _progress.remove(modelId);
  }

  Future<List<String>> getDownloadedModelIds() async {
    return _progress.values
        .where((p) => p.status == DownloadStatus.completed)
        .map((p) => p.modelId)
        .toList();
  }

  Future<String?> _validateGGUFHeader(String path) async {
    final file = File(path);
    if (!file.existsSync()) return 'File not found';
    try {
      final raf = await file.open();
      final header = await raf.read(4);
      await raf.close();
      if (header.length < 4 || 
          header[0] != 0x47 || header[1] != 0x47 || 
          header[2] != 0x55 || header[3] != 0x46) {
        return 'Invalid GGUF header';
      }
      return null;
    } catch (e) {
      return e.toString();
    }
  }
}
