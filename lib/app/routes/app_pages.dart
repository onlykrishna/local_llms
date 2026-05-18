import 'package:get/get.dart';
import '../core/middleware/auth_middleware.dart';
import '../modules/auth/bindings/auth_binding.dart';
import '../modules/auth/views/otp_screen.dart';
import '../modules/auth/views/phone_input_screen.dart';
import '../modules/home/views/home_screen.dart';
import '../modules/chat/views/chat_screen.dart';
import '../modules/chat/bindings/chat_binding.dart';
import '../modules/pdf_chat/views/pdf_chat_screen.dart';
import '../modules/pdf_chat/bindings/pdf_chat_binding.dart';
import '../modules/onboarding/views/onboarding_screen.dart';
import '../modules/settings/views/settings_screen.dart';

part 'app_routes.dart';

class AppPages {
  static final routes = [
    GetPage(
      name: AppRoutes.ONBOARDING,
      page: () => const OnboardingScreen(),
      transition: Transition.fade,
    ),
    GetPage(
      name: AppRoutes.PHONE_INPUT,
      page: () => const PhoneInputScreen(),
      binding: AuthBinding(),
      middlewares: [AuthMiddleware()],
    ),
    GetPage(
      name: AppRoutes.OTP,
      page: () => const OtpScreen(),
      binding: AuthBinding(),
    ),
    GetPage(
      name: AppRoutes.HOME,
      page: () => const HomeScreen(),
    ),
    GetPage(
      name: AppRoutes.CHAT,
      page: () => ChatScreen(),
      binding: ChatBinding(),
    ),
    GetPage(
      name: AppRoutes.PDF_CHAT,
      page: () => const PdfChatScreen(),
      binding: PdfChatBinding(),
      transition: Transition.cupertino,
    ),
    GetPage(
      name: AppRoutes.SETTINGS,
      page: () => const SettingsScreen(),
      transition: Transition.cupertino,
    ),
  ];
}
