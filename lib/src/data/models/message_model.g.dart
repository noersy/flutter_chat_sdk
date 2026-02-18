// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'message_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MessageModel _$MessageModelFromJson(Map<String, dynamic> json) => MessageModel(
  id: json['id'] as String,
  roomId: json['room_id'] as String,
  userId: json['user_id'] as String,
  username: json['username'] as String,
  content: json['content'] as String,
  type: json['type'] as String,
  status: json['status'] as String? ?? 'sent',
  createdAt: DateTime.parse(json['created_at'] as String),
);

Map<String, dynamic> _$MessageModelToJson(MessageModel instance) =>
    <String, dynamic>{
      'id': instance.id,
      'room_id': instance.roomId,
      'user_id': instance.userId,
      'username': instance.username,
      'content': instance.content,
      'type': instance.type,
      'status': instance.status,
      'created_at': instance.createdAt.toIso8601String(),
    };
