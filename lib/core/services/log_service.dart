import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

class LogService extends GetxService {
  final _logController = StreamController<String>.broadcast();
  Stream<String> get logStream => _logController.stream;

  static LogService get to => Get.find<LogService>();

  void log(String message) {
    debugPrint(message);
    _logController.add(message);
  }

  @override
  void onClose() {
    _logController.close();
    super.onClose();
  }
}
