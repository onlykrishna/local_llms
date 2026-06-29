import 'package:get/get.dart';
import '../controllers/live_voice_controller.dart';

class LiveVoiceBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<LiveVoiceController>(() => LiveVoiceController());
  }
}
