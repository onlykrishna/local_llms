import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'storage_service.dart';
import '../models/chat_message.dart';

class ChatHistoryService extends GetxService {

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final StorageService _storage = Get.find<StorageService>();

  // Firestore path helper
  CollectionReference<Map<String, dynamic>> _messagesRef(String chatId) {
    final uid = _storage.getUid()!;
    return _db
        .collection('users')
        .doc(uid)
        .collection('chats')
        .doc(chatId)
        .collection('messages');
  }

  /// Persist a single message to Firestore
  Future<void> saveMessage(String chatId, ChatMessage message) async {
    await _messagesRef(chatId)
        .doc(message.id)
        .set(message.toFirestore());
  }

  /// Load the last [limit] messages ordered by timestamp ascending
  Future<List<ChatMessage>> loadMessages(
    String chatId, {
    int limit = 50,
  }) async {
    final snapshot = await _messagesRef(chatId)
        .orderBy('timestamp', descending: false)
        .limitToLast(limit)
        .get();

    return snapshot.docs
        .map((doc) => ChatMessage.fromFirestore(doc.data()))
        .toList();
  }

  /// Update an existing message (used to patch error state)
  Future<void> updateMessage(String chatId, ChatMessage message) async {
    await _messagesRef(chatId)
        .doc(message.id)
        .update(message.toFirestore());
  }

  /// Delete an entire chat session
  Future<void> deleteChat(String chatId) async {
    final uid = _storage.getUid()!;
    await _db
        .collection('users')
        .doc(uid)
        .collection('chats')
        .doc(chatId)
        .delete();
  }
}
