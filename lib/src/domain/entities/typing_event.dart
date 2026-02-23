import 'package:equatable/equatable.dart';

class TypingEvent extends Equatable {
  final String userId;
  final String username;
  final String roomId;

  /// true = user started typing, false = user stopped typing.
  final bool isTyping;

  const TypingEvent({
    required this.userId,
    required this.username,
    required this.roomId,
    required this.isTyping,
  });

  factory TypingEvent.fromJson(Map<String, dynamic> json, {required bool isTyping}) {
    return TypingEvent(
      userId: json['user_id']?.toString() ?? '',
      username: json['username'] as String? ?? '',
      roomId: json['room_id'] as String? ?? '',
      isTyping: isTyping,
    );
  }

  @override
  List<Object?> get props => [userId, roomId, isTyping];
}
