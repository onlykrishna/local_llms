import 'package:get/get.dart';
import '../controllers/model_manager_controller.dart';

class ModelManagerBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ModelManagerController>(() => ModelManagerController());
  }
}
