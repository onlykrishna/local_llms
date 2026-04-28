import 'package:get/get.dart';
import '../../core/models/model_registry.dart';
import '../../domain/services/model_download_service.dart';
import '../../core/services/settings_service.dart';
import '../../domain/models/model_download_progress.dart';

class ModelManagerController extends GetxController {
  final ModelDownloadService _downloadService = Get.find<ModelDownloadService>();
  final SettingsService _settings = Get.find<SettingsService>();

  final RxString selectedCategory = 'All'.obs;
  final RxList<ModelDefinition> filteredModels = <ModelDefinition>[].obs;
  
  final List<String> categories = ['All', 'Gemma', 'LLaMA', 'Phi', 'Other'];

  @override
  void onInit() {
    super.onInit();
    filterModels('All');
  }

  void filterModels(String category) {
    selectedCategory.value = category;
    if (category == 'All') {
      filteredModels.value = ModelRegistry.models;
    } else {
      filteredModels.value = ModelRegistry.models
          .where((m) => m.displayName.toLowerCase().contains(category.toLowerCase()) || 
                       m.tags.any((t) => t.toLowerCase() == category.toLowerCase()))
          .toList();
    }
  }

  Stream<ModelDownloadProgress> getDownloadProgress(String modelId) {
    return _downloadService.progressStream(modelId);
  }

  Future<void> startDownload(String modelId) async {
    await _downloadService.startDownload(modelId);
  }

  Future<void> pauseDownload(String modelId) async {
    await _downloadService.pauseDownload(modelId);
  }

  Future<void> resumeDownload(String modelId) async {
    await _downloadService.resumeDownload(modelId);
  }

  Future<void> cancelDownload(String modelId) async {
    await _downloadService.cancelDownload(modelId);
  }

  Future<void> setActiveModel(String modelId) async {
    _settings.updateModel(modelId);
    Get.snackbar('Success', 'Active model changed to ${_settings.modelLabel}');
  }

  Future<void> deleteModel(String modelId) async {
    if (_settings.selectedModelId.value == modelId) {
       _settings.updateModel('');
    }
    await _downloadService.deleteModel(modelId);
    Get.snackbar('Deleted', 'Model file removed from storage.');
  }

  bool isDownloaded(String modelId) {
    // This is a bit inefficient to check Every time, but for mobile it's okay for now
    // We can also use a reactive list from DownloadService
    return false; // Will implement properly in UI using StreamBuilder
  }
}
