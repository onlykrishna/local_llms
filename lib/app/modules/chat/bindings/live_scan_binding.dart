import 'package:get/get.dart';
import '../../../core/services/live_scan_service.dart';
import '../controllers/live_scan_controller.dart';

class LiveScanBinding extends Bindings {
  @override
  void dependencies() {
    // LiveScanService must already be registered as a singleton in the app
    // bootstrap (main.dart or InitialBinding). We only do a safety find here.
    // If not found, put it now so the screen can always run standalone.
    if (!Get.isRegistered<LiveScanService>()) {
      Get.put<LiveScanService>(LiveScanService(), permanent: true);
    }

    // fenix: false — we do NOT want GetX to silently recreate a disposed
    // controller that still holds an open camera handle.
    Get.lazyPut<LiveScanController>(
      () => LiveScanController(),
      fenix: false,
    );
  }
}
