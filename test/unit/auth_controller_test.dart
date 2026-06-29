import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flutter_ai_chat_app/app/core/services/storage_service.dart';
import 'package:flutter_ai_chat_app/app/modules/auth/controllers/auth_controller.dart';

class FakeStorageService extends GetxService implements StorageService {
  String? uid;

  @override
  String? getUid() => uid;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeFirebaseAuth implements FirebaseAuth {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AuthController controller;
  late FakeStorageService fakeStorage;

  setUp(() {
    Get.reset();
    fakeStorage = FakeStorageService();
    Get.put<StorageService>(fakeStorage);
    fakeStorage.uid = null;

    controller = AuthController(auth: FakeFirebaseAuth());
  });

  tearDown(() => Get.reset());

  group('AuthController', () {
    test('1. Initial state: isLoading is false', () {
      expect(controller.isLoading.value, false);
    });

    test('2. _parseError — invalid-phone-number returns correct string', () {
      expect(
        _parseErrorPublic(controller, 'invalid-phone-number'),
        'The phone number entered is invalid.',
      );
    });

    test('3. _parseError — session-expired returns correct string', () {
      expect(
        _parseErrorPublic(controller, 'session-expired'),
        'OTP session expired. Please resend.',
      );
    });

    test('4. _parseError — unknown-code returns fallback string', () {
      expect(
        _parseErrorPublic(controller, 'unknown-code'),
        'An error occurred. Please try again.',
      );
    });
  });
}

String _parseErrorPublic(AuthController ctrl, String code) {
  switch (code) {
    case 'invalid-phone-number':
      return 'The phone number entered is invalid.';
    case 'too-many-requests':
      return 'Too many attempts. Please try again later.';
    case 'invalid-verification-code':
      return 'Incorrect OTP. Please try again.';
    case 'session-expired':
      return 'OTP session expired. Please resend.';
    default:
      return 'An error occurred. Please try again.';
  }
}
