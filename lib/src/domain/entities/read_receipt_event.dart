import 'package:equatable/equatable.dart';
import 'message.dart';

class ReadReceiptEvent extends Equatable {
  final String messageId;
  final String roomId;
  final ReadReceipt readBy;

  const ReadReceiptEvent({
    required this.messageId,
    required this.roomId,
    required this.readBy,
  });

  factory ReadReceiptEvent.fromJson(Map<String, dynamic> json) {
    final rbJson = json['read_by'] as Map<String, dynamic>? ?? {};
    return ReadReceiptEvent(
      messageId: json['message_id'] as String? ?? '',
      roomId:    json['room_id']    as String? ?? '',
      readBy:    ReadReceipt.fromJson(rbJson),
    );
  }

  @override
  List<Object?> get props => [messageId, roomId, readBy];
}
