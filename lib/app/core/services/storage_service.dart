import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

class StorageService extends GetxService {
  final _box = GetStorage();

  // ── UID helpers ──
  String? getUid() => _box.read<String>('uid');
  Future<void> saveUid(String uid) => _box.write('uid', uid);
  Future<void> clearUid() => _box.remove('uid');

  // ── String helpers (ThemeController, etc.) ──
  String? getString(String key) => _box.read<String>(key);
  Future<void> setString(String key, String value) => _box.write(key, value);

  // ── Bool helpers (OnboardingScreen, etc.) ──
  bool? getBool(String key) => _box.read<bool>(key);
  Future<void> setBool(String key, bool value) => _box.write(key, value);
}
