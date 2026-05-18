import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:get/get.dart';
import '../../../../app/core/services/pdf_chat_service.dart';
import '../../../../app/core/services/storage_service.dart';
import '../../../../app/routes/app_pages.dart';

class AuthController extends GetxController {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final StorageService _storage = Get.find<StorageService>();

  @override
  void onInit() {
    super.onInit();
    if (kDebugMode) {
      debugPrint("🛠️ AuthController: kDebugMode is true. Configuring Firebase Auth to disable app verification for testing to bypass browser reCAPTCHA popup.");
      _auth.setSettings(appVerificationDisabledForTesting: true);
    }
  }

  // Reactive state
  final RxBool isLoading = false.obs;
  final RxString verificationId = ''.obs;
  final RxString phoneNumber = ''.obs;
  final RxString errorMessage = ''.obs;
  final RxInt resendToken = 0.obs;

  // Step 1: Send OTP
  Future<void> sendOtp(String fullPhoneNumber) async {
    isLoading.value = true;
    errorMessage.value = '';

    await _auth.verifyPhoneNumber(
      phoneNumber: fullPhoneNumber,
      verificationCompleted: (PhoneAuthCredential credential) async {
        await _signIn(credential);
      },
      verificationFailed: (FirebaseAuthException e) {
        isLoading.value = false;
        errorMessage.value = _parseError(e.code);
        Get.snackbar(
          'Error',
          errorMessage.value,
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Get.theme.colorScheme.error,
          colorText: Get.theme.colorScheme.onError,
        );
      },
      codeSent: (String vId, int? resendTokenVal) {
        isLoading.value = false;
        verificationId.value = vId;
        resendToken.value = resendTokenVal ?? 0;
        phoneNumber.value = fullPhoneNumber;
        Get.toNamed(AppRoutes.OTP);
      },
      codeAutoRetrievalTimeout: (String vId) {
        verificationId.value = vId;
      },
      forceResendingToken: resendToken.value == 0 ? null : resendToken.value,
      timeout: const Duration(seconds: 60),
    );
  }

  // Step 2: Verify OTP
  Future<void> verifyOtp(String otp) async {
    if (verificationId.value.isEmpty) return;
    isLoading.value = true;
    errorMessage.value = '';

    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId.value,
      smsCode: otp,
    );

    await _signIn(credential);
  }

  // Resend OTP
  Future<void> resendOtp() async {
    await sendOtp(phoneNumber.value);
  }

  // Internal sign-in
  Future<void> _signIn(PhoneAuthCredential credential) async {
    try {
      final result = await _auth.signInWithCredential(credential);
      final uid = result.user?.uid;

      if (uid != null) {
        await _storage.saveUid(uid);

        // Crashlytics user identifier
        await FirebaseCrashlytics.instance.setUserIdentifier(uid);

        isLoading.value = false;

        // Skip setup screen if already set up
        final setupComplete = _storage.getBool('setupComplete') ?? false;
        if (setupComplete) {
          Get.offAllNamed(AppRoutes.CHAT);
        } else {
          try {
            final docs = await Get.find<PdfChatService>().loadDocuments();
            if (docs.isNotEmpty) {
              await _storage.setBool('setupComplete', true);
              Get.offAllNamed(AppRoutes.CHAT);
              return;
            }
          } catch (e) {
            debugPrint("⚠️ Error checking setup documents on sign-in: $e");
          }
          Get.offAllNamed(AppRoutes.SETUP);
        }
      }
    } on FirebaseAuthException catch (e) {
      isLoading.value = false;
      errorMessage.value = _parseError(e.code);
      Get.snackbar(
        'Verification Failed',
        errorMessage.value,
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  // Friendly error messages
  String _parseError(String code) {
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
}
