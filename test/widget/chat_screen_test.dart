import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_ai_chat_app/app/modules/chat/views/widgets/message_input_bar.dart';
import 'package:flutter_ai_chat_app/app/modules/chat/views/widgets/typing_indicator.dart';

void main() {
  tearDown(() => Get.reset());

  Widget buildInputBar({bool isTyping = false}) {
    return GetMaterialApp(
      home: Scaffold(
        body: MessageInputBar(
          isTyping: isTyping.obs,
          onSend: (_) {},
        ),
      ),
    );
  }

  group('Chat widget tests', () {
    testWidgets('1. MessageInputBar renders send button', (tester) async {
      await tester.pumpWidget(buildInputBar());
      await tester.pump();
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    });

    testWidgets('2. MessageInputBar send button disabled when isTyping true',
        (tester) async {
      await tester.pumpWidget(buildInputBar(isTyping: true));
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
