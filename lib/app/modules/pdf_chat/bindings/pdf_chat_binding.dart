import 'package:get/get.dart';
import '../controllers/pdf_chat_controller.dart';

class PdfChatBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<PdfChatController>(() => PdfChatController());
  }
}
