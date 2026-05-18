import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:flutter_ai_chat_app/app/core/models/chat_message.dart';
import 'package:flutter_ai_chat_app/app/core/services/api_provider_service.dart';
import 'package:flutter_ai_chat_app/app/core/services/chat_history_service.dart';
import 'package:flutter_ai_chat_app/app/modules/chat/controllers/chat_controller.dart';

import 'chat_controller_test.mocks.dart';

@GenerateMocks([ApiProviderService, ChatHistoryService])
void main() {
  late ChatController controller;
  late MockApiProviderService mockApi;
  late MockChatHistoryService mockHistory;

  setUp(() {
    Get.reset();
    mockApi = MockApiProviderService();
    mockHistory = MockChatHistoryService();

    // Register mocks so Get.find works inside the controller
    Get.put<ApiProviderService>(mockApi);
    Get.put<ChatHistoryService>(mockHistory);

    // Stub loadMessages to return empty list
    when(mockHistory.loadMessages(any)).thenAnswer((_) async => []);
    // Stub saveMessage (fire-and-forget)
    when(mockHistory.saveMessage(any, any)).thenAnswer((_) async {});

    controller = ChatController();
    controller.onInit();
  });

  tearDown(() {
    Get.reset();
  });

  group('ChatController', () {
    test('1. sendMessage() with empty string does not add to messages', () async {
      await controller.sendMessage('   ');
      expect(controller.messages.length, 0);
    });

    test('2. sendMessage() appends a user message immediately (optimistic)', () async {
      when(mockApi.sendMessages(any)).thenAnswer((_) async => 'Hello!');

      // Don't await — we check optimistic append synchronously
      final future = controller.sendMessage('Test');
      expect(controller.messages.isNotEmpty, true);
      expect(controller.messages.first.role, MessageRole.user);
      await future;
    });

    test('3. sendMessage() while isTyping is true is ignored', () async {
      controller.isTyping.value = true;
      await controller.sendMessage('ignored');
      expect(controller.messages.length, 0);
    });

    test('4. clearConversation() empties the messages list', () async {
      when(mockApi.sendMessages(any)).thenAnswer((_) async => 'Reply');
      when(mockHistory.deleteChat(any)).thenAnswer((_) async {});

      await controller.sendMessage('Hello');
      expect(controller.messages.isNotEmpty, true);

      await controller.clearConversation();
      expect(controller.messages.length, 0);
    });
  });
}
