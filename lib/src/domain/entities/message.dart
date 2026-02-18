import 'package:equatable/equatable.dart';

class Message extends Equatable {
  final String id;
  final String roomId;
  final String userId;
  final String username;
  final String content;
  final String type;
  final String status; // sent, delivered, read
  final DateTime createdAt;
  final String? title;
  final Map<String, dynamic>? payload;
  final List<String>? attachmentUrls;

  const Message({
    required this.id,
    required this.roomId,
    required this.userId,
    required this.username,
    required this.content,
    required this.type,
    this.status = 'sent',
    required this.createdAt,
    this.title,
    this.payload,
    this.attachmentUrls,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String? ?? '',
      roomId: json['room_id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      username: json['username'] as String? ?? 'Unknown',
      content: json['content'] as String? ?? '',
      type: json['type'] as String? ?? 'text',
      status: json['status'] as String? ?? 'sent',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      title: json['title'] as String?,
      payload: json['payload'] as Map<String, dynamic>?,
      attachmentUrls: (json['attachment_urls'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'room_id': roomId,
      'user_id': userId,
      'username': username,
      'content': content,
      'type': type,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'title': title,
      'payload': payload,
      'attachment_urls': attachmentUrls,
    };
  }

  Message copyWithStatus(String newStatus) {
    return Message(
      id: id,
      roomId: roomId,
      userId: userId,
      username: username,
      content: content,
      type: type,
      status: newStatus,
      createdAt: createdAt,
      title: title,
      payload: payload,
      attachmentUrls: attachmentUrls,
    );
  }

  @override
  List<Object?> get props => [
    id,
    roomId,
    userId,
    username,
    content,
    type,
    status,
    createdAt,
    title,
    payload,
    attachmentUrls,
  ];
}
