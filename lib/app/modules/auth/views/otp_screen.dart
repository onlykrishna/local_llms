import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import '../controllers/auth_controller.dart';

const kPrimary     = Color(0xFF6C63FF);
const kPrimaryDark = Color(0xFF4B44CC);
const kBg          = Color(0xFFF8F9FE);
const kCard        = Color(0xFFFFFFFF);
const kBorder      = Color(0xFFE5E7EB);
const kText1       = Color(0xFF1A1A2E);
const kText2       = Color(0xFF6B7280);
const kText3       = Color(0xFF9CA3AF);
const kError       = Color(0xFFEF4444);
const kSuccess     = Color(0xFF10B981);

const kGradient = LinearGradient(
  colors: [Color(0xFF6C63FF), Color(0xFF4B44CC)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final AuthController controller = Get.find<AuthController>();
  final TextEditingController _pinController = TextEditingController();
  final RxString currentOtp = ''.obs;
  
  Timer? _timer;
  final RxInt _start = 60.obs;

  @override
  void initState() {
    super.initState();
    startTimer();
  }

  void startTimer() {
    _start.value = 60;
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (Timer timer) {
        if (_start.value == 0) {
          timer.cancel();
        } else {
          _start.value--;
        }
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pinController.dispose();
    super.dispose();
  }

  void _verifyOtp() {
    final code = _pinController.text.trim();
    if (code.length == 6) {
      controller.verifyOtp(code);
    }
  }

  void _resendOtp() {
    controller.resendOtp();
    startTimer();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height - 
                  MediaQuery.of(context).padding.top - 
                  MediaQuery.of(context).padding.bottom,
            ),
            child: IntrinsicHeight(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 16),
                    // Card Back Button
                    Align(
                      alignment: Alignment.topLeft,
                      child: GestureDetector(
                        onTap: () => Get.back(),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: kCard,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: kBorder),
                          ),
                          child: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 16,
                            color: kText1,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Lock Icon Container
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: kGradient,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: kPrimary.withOpacity(0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          )
                        ],
                      ),
                      child: const Icon(
                        Icons.lock_person_rounded,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),

                    const SizedBox(height: 32),
                    const Text(
                      "Verification OTP",
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: kText1,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Obx(() => Text(
                      "Enter the 6-digit code sent to\n${controller.phoneNumber.value}",
                      style: const TextStyle(fontSize: 15, color: kText2, height: 1.4),
                      textAlign: TextAlign.center,
                    )),

                    const SizedBox(height: 40),

                    // OTP Fields
                    PinCodeTextField(
                      appContext: context,
                      length: 6,
                      keyboardType: TextInputType.number,
                      textStyle: const TextStyle(
                        fontSize: 20,
                        color: kText1,
                        fontWeight: FontWeight.bold,
                      ),
                      pinTheme: PinTheme(
                        shape: PinCodeFieldShape.box,
                        borderRadius: BorderRadius.circular(12),
                        fieldHeight: 52,
                        fieldWidth: 44,
                        activeColor: kPrimary,
                        selectedColor: kPrimary,
                        inactiveColor: kBorder,
                        activeFillColor: kCard,
                        selectedFillColor: kCard,
                        inactiveFillColor: kCard,
                      ),
                      enableActiveFill: true,
                      controller: _pinController,
                      onChanged: (value) {
                        currentOtp.value = value;
                      },
                      onCompleted: (value) {
                        controller.verifyOtp(value);
                      },
                    ),

                    const SizedBox(height: 32),

                    // Verify OTP Button
                    Obx(() => GestureDetector(
                      onTap: (controller.isLoading.value || currentOtp.value.length < 6)
                          ? null
                          : _verifyOtp,
                      child: Container(
                        width: double.infinity,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: (controller.isLoading.value || currentOtp.value.length < 6)
                              ? null
                              : kGradient,
                          color: (controller.isLoading.value || currentOtp.value.length < 6)
                              ? kBorder
                              : null,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: (controller.isLoading.value || currentOtp.value.length < 6)
                              ? []
                              : [
                                  BoxShadow(
                                    color: kPrimary.withOpacity(0.35),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  )
                                ],
                        ),
                        child: Center(
                          child: controller.isLoading.value
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: kPrimary,
                                  ),
                                )
                              : const Text(
                                  "Verify OTP",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                        ),
                      ),
                    )),

                    const SizedBox(height: 24),

                    // Reactive cooldown timer
                    Obx(() => TextButton(
                      onPressed: _start.value == 0 ? _resendOtp : null,
                      child: Text(
                        _start.value == 0
                            ? "Resend Code"
                            : "Resend Code in ${_start.value}s",
                        style: TextStyle(
                          color: _start.value == 0 ? kPrimary : kText3,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    )),

                    const Spacer(),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
