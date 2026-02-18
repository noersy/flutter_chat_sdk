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

  const Message({
    required this.id,
    required this.roomId,
    required this.userId,
    required this.username,
    required this.content,
    required this.type,
    this.status = 'sent',
    required this.createdAt,
  });

  /// Creates a copy with updated status
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
    );
  }

  @override
  List<Object?> get props => [id, roomId, userId, username, content, type, status, createdAt];
}
