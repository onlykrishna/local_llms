enum MessageRole { user, assistant, system }

class ChatMessage {
  final String id;
  final MessageRole role;
  final String content;
  final DateTime timestamp;
  final bool isError;

  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.isError = false,
  });

  // For sending to AI API
  Map<String, String> toApiMap() => {
    'role': role.name,
    'content': content,
  };

  // For Firestore persistence
  Map<String, dynamic> toFirestore() => {
    'id': id,
    'role': role.name,
    'content': content,
    'timestamp': timestamp.toIso8601String(),
    'isError': isError,
  };

  factory ChatMessage.fromFirestore(Map<String, dynamic> map) => ChatMessage(
    id: map['id'] as String,
    role: MessageRole.values.firstWhere((r) => r.name == map['role']),
    content: map['content'] as String,
    timestamp: DateTime.parse(map['timestamp'] as String),
    isError: map['isError'] as bool? ?? false,
  );

  ChatMessage copyWith({String? content, bool? isError}) => ChatMessage(
    id: id,
    role: role,
    content: content ?? this.content,
    timestamp: timestamp,
    isError: isError ?? this.isError,
  );
}
