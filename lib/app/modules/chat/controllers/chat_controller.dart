import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import '../../../core/models/ai_provider.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/services/api_provider_service.dart';
import '../../../core/services/chat_history_service.dart';
import '../../../core/services/analytics_service.dart';

class ChatController extends GetxController {

  final ApiProviderService _api = Get.find<ApiProviderService>();
  final ChatHistoryService _history = Get.find<ChatHistoryService>();

  // Reactive state
  final RxList<ChatMessage> messages = <ChatMessage>[].obs;
  final RxBool isTyping = false.obs;
  final RxBool isLoadingHistory = false.obs;

  // Each controller instance owns one chat session
  late String chatId;

  // System prompt — defines AI persona
  static const String _systemPrompt =
    'You are a helpful, concise, and friendly AI assistant. '
    'Format your responses in Markdown when helpful. '
    'Be direct and avoid unnecessary filler phrases.';

  @override
  void onInit() {
    super.onInit();
    chatId = const Uuid().v4();
    _loadHistory();
  }

  // ── Load history from Firestore on session start ──
  Future<void> _loadHistory() async {
    isLoadingHistory.value = true;
    try {
      final loaded = await _history.loadMessages(chatId);
      messages.assignAll(loaded);
    } catch (e) {
      // Silently fail — history is non-critical
    } finally {
      isLoadingHistory.value = false;
    }
  }

  // ── Main send message method ──
  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || isTyping.value) return;

    // 1. Append user message immediately (optimistic UI)
    final userMsg = ChatMessage(
      id: const Uuid().v4(),
      role: MessageRole.user,
      content: trimmed,
      timestamp: DateTime.now(),
    );
    messages.add(userMsg);
    _history.saveMessage(chatId, userMsg); // fire-and-forget

    // 2. Show typing indicator
    isTyping.value = true;

    // 3. Build context: system prompt + full message history
    final contextMessages = [
      ChatMessage(
        id: 'system',
        role: MessageRole.system,
        content: _systemPrompt,
        timestamp: DateTime.now(),
      ),
      ...messages,
    ];

    try {
      // 4. Call AI provider
      final reply = await _api.sendMessages(contextMessages);

      // 5. Append AI response
      final aiMsg = ChatMessage(
        id: const Uuid().v4(),
        role: MessageRole.assistant,
        content: reply,
        timestamp: DateTime.now(),
      );
      messages.add(aiMsg);
      _history.saveMessage(chatId, aiMsg); // fire-and-forget

      // 6. Analytics
      try {
        Get.find<AnalyticsService>().logMessageSent(_api.activeProvider.value.displayName);
      } catch (_) {}

    } catch (e) {
      final errorMsg = ChatMessage(
        id: const Uuid().v4(),
        role: MessageRole.assistant,
        content: e.toString().replaceFirst('Exception: ', ''),
        timestamp: DateTime.now(),
        isError: true,
      );
      messages.add(errorMsg);

      Get.snackbar(
        'Error',
        errorMsg.content,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 4),
      );
    } finally {
      isTyping.value = false;
    }
  }

  // ── Clear conversation ──
  Future<void> clearConversation() async {
    messages.clear();
    _api.clearCache();
    await _history.deleteChat(chatId);
    chatId = const Uuid().v4();
  }

  // ── Convenience getter for active provider name ──
  String get activeProviderName => _api.activeProvider.value.displayName;
  Rx<AiProvider> get activeProvider => _api.activeProvider;
}
