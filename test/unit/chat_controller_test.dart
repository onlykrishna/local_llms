import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_ai_chat_app/app/core/models/chat_message.dart';
import 'package:flutter_ai_chat_app/app/core/services/api_provider_service.dart';
import 'package:flutter_ai_chat_app/app/core/services/chat_history_service.dart';
import 'package:flutter_ai_chat_app/app/modules/chat/controllers/chat_controller.dart';

class FakeApiProviderService extends GetxService implements ApiProviderService {
  String reply = 'Hello!';
  List<ChatMessage>? receivedMessages;

  @override
  Future<String> sendMessages(List<ChatMessage> messages, {bool voiceMode = false}) async {
    receivedMessages = messages;
    return reply;
  }

  @override
  bool get isReady => true;

  @override
  String get readinessError => '';

  @override
  void clearCache() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeChatHistoryService extends GetxService implements ChatHistoryService {
  final List<ChatMessage> savedMessages = [];
  bool deleteChatCalled = false;

  @override
  Future<List<ChatMessage>> loadMessages(String chatId, {int limit = 50}) async {
    return [];
  }

  @override
  Future<void> saveMessage(String chatId, ChatMessage message) async {
    savedMessages.add(message);
  }

  @override
  Future<void> deleteChat(String chatId) async {
    deleteChatCalled = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late ChatController controller;
  late FakeApiProviderService fakeApi;
  late FakeChatHistoryService fakeHistory;

  setUp(() {
    Get.reset();
    fakeApi = FakeApiProviderService();
    fakeHistory = FakeChatHistoryService();

    // Register fakes so Get.find works inside the controller
    Get.put<ApiProviderService>(fakeApi);
    Get.put<ChatHistoryService>(fakeHistory);

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
      fakeApi.reply = 'Hello!';

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
      fakeApi.reply = 'Reply';

      await controller.sendMessage('Hello');
      expect(controller.messages.isNotEmpty, true);

      await controller.clearConversation();
      expect(controller.messages.length, 0);
      expect(fakeHistory.deleteChatCalled, true);
    });
  });
}
