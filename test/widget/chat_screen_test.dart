import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_ai_chat_app/app/modules/chat/views/widgets/message_input_bar.dart';
import 'package:flutter_ai_chat_app/app/modules/chat/views/widgets/typing_indicator.dart';

import 'package:flutter_ai_chat_app/app/core/services/voice_service.dart';
import 'package:flutter_ai_chat_app/app/core/services/storage_service.dart';
import 'package:flutter_ai_chat_app/app/core/services/api_provider_service.dart';
import 'package:flutter_ai_chat_app/app/core/services/analytics_service.dart';
import 'package:flutter_ai_chat_app/app/modules/chat/controllers/chat_controller.dart';

class FakeVoiceService extends GetxService implements VoiceService {
  @override
  final RxBool isListening = false.obs;
  @override
  final RxBool isSpeaking = false.obs;
  @override
  final RxBool isInitialized = false.obs;
  @override
  final RxString liveTranscript = ''.obs;
  @override
  final RxString voiceError = ''.obs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeStorageService extends GetxService implements StorageService {
  @override
  bool? getBool(String key) => false;
  
  @override
  Future<void> setBool(String key, bool value) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeApiProviderService extends GetxService implements ApiProviderService {
  @override
  bool get isReady => true;
  
  @override
  String get readinessError => '';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAnalyticsService extends GetxService implements AnalyticsService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeChatController extends GetxController implements ChatController {
  @override
  final RxBool isTyping = true.obs;

  @override
  final Rx<String?> attachedImagePath = Rx<String?>(null);

  @override
  final Rx<String?> attachedImageBase64 = Rx<String?>(null);

  @override
  final Rx<String?> attachedImageMime = Rx<String?>(null);

  @override
  final RxString attachedPdfText = ''.obs;

  @override
  final RxString attachedPdfName = ''.obs;

  @override
  final RxBool isExtractingPdf = false.obs;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  setUp(() {
    Get.reset();
    Get.put<VoiceService>(FakeVoiceService());
    Get.put<StorageService>(FakeStorageService());
    Get.put<ApiProviderService>(FakeApiProviderService());
    Get.put<AnalyticsService>(FakeAnalyticsService());
    Get.put<ChatController>(FakeChatController());
  });

  tearDown(() => Get.reset());

  Widget buildInputBar({bool isTyping = false}) {
    return GetMaterialApp(
      home: Scaffold(
        body: MessageInputBar(
          isTyping: isTyping.obs,
          onSend: (text, {attachmentPath}) {},
        ),
      ),
    );
  }

  group('Chat widget tests', () {
    testWidgets('1. MessageInputBar renders send button', (tester) async {
      await tester.pumpWidget(buildInputBar());
      await tester.pump();

      // Enter text to switch from Mic button to Send button
      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pump();

      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    });

    testWidgets('2. MessageInputBar send button disabled when isTyping true',
        (tester) async {
      await tester.pumpWidget(buildInputBar(isTyping: true));
      await tester.pump();

      // Enter text to switch from Mic button to Send button
      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pump();

      final iconButtons = tester.widgetList<IconButton>(
        find.byType(IconButton),
      ).toList();
      final sendButton = iconButtons.firstWhere(
        (b) {
          final icon = b.icon;
          return icon is Icon && icon.icon == Icons.send_rounded;
        },
        orElse: () => throw Exception('send button not found'),
      );
      expect(sendButton.onPressed, isNull);
    });

    testWidgets('3. TypingIndicator is visible when rendered', (tester) async {
      await tester.pumpWidget(
        const GetMaterialApp(
          home: Scaffold(body: TypingIndicator()),
        ),
      );
      await tester.pump();
      expect(find.byType(TypingIndicator), findsOneWidget);
    });
  });
}
