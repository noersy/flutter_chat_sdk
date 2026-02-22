import 'package:equatable/equatable.dart';

class UnsendEvent extends Equatable {
  final String messageId;
  final String roomId;
  final String unsentBy;
  final DateTime unsentAt;

  const UnsendEvent({
    required this.messageId,
    required this.roomId,
    required this.unsentBy,
    required this.unsentAt,
  });

  factory UnsendEvent.fromJson(Map<String, dynamic> json) {
    return UnsendEvent(
      messageId: json['message_id'] as String? ?? '',
      roomId:    json['room_id']    as String? ?? '',
      unsentBy:  json['unsent_by']  as String? ?? '',
      unsentAt:  DateTime.tryParse(json['unsent_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [messageId, roomId, unsentBy, unsentAt];
}
