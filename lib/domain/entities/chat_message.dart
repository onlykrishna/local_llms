import 'package:hive/hive.dart';
import 'package:json_annotation/json_annotation.dart';

part 'chat_message.g.dart';

@HiveType(typeId: 0)
@JsonSerializable()
class ChatMessage {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String content;

  @HiveField(2)
  final bool isUser;

  @HiveField(3)
  final DateTime timestamp;

  @HiveField(4)
  final bool? isFromKb;

  @HiveField(5)
  final bool? isSynthesized;

  ChatMessage({
    required this.id,
    required this.content,
    required this.isUser,
    this.isFromKb = false,
    this.isSynthesized = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory ChatMessage.fromJson(Map<String, dynamic> json) => _$ChatMessageFromJson(json);
  Map<String, dynamic> toJson() => _$ChatMessageToJson(this);
}
