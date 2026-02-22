import 'package:equatable/equatable.dart';

class ReadReceipt extends Equatable {
  final String userId;
  final String username;
  final DateTime readAt;

  const ReadReceipt({
    required this.userId,
    required this.username,
    required this.readAt,
  });

  factory ReadReceipt.fromJson(Map<String, dynamic> json) {
    return ReadReceipt(
      userId:   json['user_id'] as String? ?? '',
      username: json['username'] as String? ?? 'Unknown',
      readAt:   DateTime.tryParse(json['read_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'user_id':  userId,
    'username': username,
    'read_at':  readAt.toIso8601String(),
  };

  @override
  List<Object?> get props => [userId, username, readAt];
}

class ChatMessage extends Equatable {
  final String messageId;
  final String roomId;
  final String userId;
  final String username;
  final Map<String, dynamic> payload;
  final bool isDeleted;
  final String? deletedBy;
  final DateTime? deletedAt;
  final List<ReadReceipt> readBy;
  final DateTime createdAt;

  const ChatMessage({
    required this.messageId,
    required this.roomId,
    required this.userId,
    required this.username,
    required this.payload,
    this.isDeleted = false,
    this.deletedBy,
    this.deletedAt,
    this.readBy = const [],
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawReadBy = json['read_by'] as List<dynamic>? ?? [];
    return ChatMessage(
      messageId: json['message_id'] as String? ?? json['id'] as String? ?? '',
      roomId:    json['room_id'] as String? ?? '',
      userId:    json['user_id'] as String? ?? '',
      username:  json['username'] as String? ?? 'Unknown',
      payload:   Map<String, dynamic>.from(json),
      isDeleted: json['is_deleted'] as bool? ?? json['deleted_at'] != null,
      deletedBy: json['deleted_by'] as String?,
      deletedAt: json['deleted_at'] != null
          ? DateTime.tryParse(json['deleted_at'] as String)
          : null,
      readBy: rawReadBy
          .whereType<Map>()
          .map((e) => ReadReceipt.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  ChatMessage copyWithDeleted({
    required String deletedBy,
    required DateTime deletedAt,
  }) {
    return ChatMessage(
      messageId: messageId,
      roomId:    roomId,
      userId:    userId,
      username:  username,
      payload:   payload,
      isDeleted: true,
      deletedBy: deletedBy,
      deletedAt: deletedAt,
      readBy:    readBy,
      createdAt: createdAt,
    );
  }

  ChatMessage copyWithNewReceipt(ReadReceipt receipt) {
    if (readBy.any((r) => r.userId == receipt.userId)) {
      return this;
    }
    return ChatMessage(
      messageId: messageId,
      roomId:    roomId,
      userId:    userId,
      username:  username,
      payload:   payload,
      isDeleted: isDeleted,
      deletedBy: deletedBy,
      deletedAt: deletedAt,
      readBy:    [...readBy, receipt],
      createdAt: createdAt,
    );
  }

  @override
  List<Object?> get props => [messageId, roomId, userId, isDeleted, readBy, createdAt];
}
