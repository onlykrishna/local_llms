import 'package:get/get.dart';
import '../controllers/live_vision_controller.dart';
import '../services/live_vision_service.dart';

class LiveVisionBinding extends Bindings {
  @override
  void dependencies() {
    // Service must be registered first (controller depends on it)
    Get.lazyPut<LiveVisionService>(() => LiveVisionService());
    Get.lazyPut<LiveVisionController>(() => LiveVisionController());
  }
}
