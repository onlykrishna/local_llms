enum MessageRole { user, assistant, system }

class ChatMessage {
  final String id;
  final MessageRole role;
  final String content;
  final DateTime timestamp;
  final bool isError;
  final String? imageBase64;
  final String? imageMimeType; // 'image/jpeg' or 'image/png'
  final String? attachedFileName; // PDF filename for display in bubble, if any

  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.isError = false,
    this.imageBase64,
    this.imageMimeType,
    this.attachedFileName,
  });

  Map<String, dynamic> toApiMap({bool useGeminiFormat = false}) {
    if (imageBase64 != null && imageBase64!.isNotEmpty && role == MessageRole.user) {
      if (useGeminiFormat) {
        // Gemini format — used in GeminiApiService
        return {
          'role': 'user',
          'parts': [
            {
              'inlineData': {
                'mimeType': imageMimeType ?? 'image/jpeg',
                'data': imageBase64!,
              }
            },
            {'text': content.isNotEmpty ? content : 'What is in this image?'},
          ],
        };
      } else {
        // OpenAI / Groq format
        return {
          'role': 'user',
          'content': [
            {
              'type': 'image_url',
              'image_url': {
                'url': 'data:${imageMimeType ?? 'image/jpeg'};base64,$imageBase64',
                'detail': 'auto',
              },
            },
            {
              'type': 'text',
              'text': content.isNotEmpty ? content : 'What is in this image?',
            },
          ],
        };
      }
    }
    // Text-only
    if (useGeminiFormat) {
      return {
        'role': role == MessageRole.assistant ? 'model' : role.name,
        'parts': [{'text': content}],
      };
    }
    return {'role': role.name, 'content': content};
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'role': role.name,
      'content': content,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'isError': isError,
      // Only store small images; skip large ones to avoid Firestore size limits
      'imageBase64': (imageBase64 != null && imageBase64!.length < 500000)
          ? imageBase64
          : null,
      'imageMimeType': imageMimeType,
      'attachedFileName': attachedFileName,
    };
  }

  factory ChatMessage.fromFirestore(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'] as String,
      role: MessageRole.values.firstWhere((e) => e.name == map['role']),
      content: map['content'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      isError: map['isError'] as bool? ?? false,
      imageBase64: map['imageBase64'] as String?,
      imageMimeType: map['imageMimeType'] as String?,
      attachedFileName: map['attachedFileName'] as String?,
    );
  }

  ChatMessage copyWith({
    String? content,
    bool? isError,
    String? imageBase64,
    String? imageMimeType,
    String? attachedFileName,
  }) {
    return ChatMessage(
      id: id,
      role: role,
      content: content ?? this.content,
      timestamp: timestamp,
      isError: isError ?? this.isError,
      imageBase64: imageBase64 ?? this.imageBase64,
      imageMimeType: imageMimeType ?? this.imageMimeType,
      attachedFileName: attachedFileName ?? this.attachedFileName,
    );
  }
}
