import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../data/models/message_model.dart';
import '../domain/entities/message.dart';

/// Represents a user's online status change event
class UserStatusEvent {
  final String userId;
  final String username;
  final bool isOnline;

  const UserStatusEvent({required this.userId, required this.username, required this.isOnline});

  factory UserStatusEvent.fromJson(Map<String, dynamic> json) {
    return UserStatusEvent(
      userId: json['user_id'] as String,
      username: json['username'] as String,
      isOnline: json['is_online'] as bool,
    );
  }
}

/// Represents a batch of message status updates
class MessageStatusEvent {
  final String roomId;
  final String userId; // recipient whose status changed
  final List<StatusUpdate> updates;

  const MessageStatusEvent({required this.roomId, required this.userId, required this.updates});

  factory MessageStatusEvent.fromJson(Map<String, dynamic> json) {
    final updatesJson = json['updates'] as List<dynamic>? ?? [];
    return MessageStatusEvent(
      roomId: json['room_id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      updates: updatesJson
          .map(
            (u) =>
                StatusUpdate(messageId: u['message_id'] as String, status: u['status'] as String),
          )
          .toList(),
    );
  }
}

/// Single message status update item
class StatusUpdate {
  final String messageId;
  final String status; // sent, delivered, read

  const StatusUpdate({required this.messageId, required this.status});
}

class WebSocketService {
  WebSocketChannel? _channel;
  final StreamController<Message> _messageController = StreamController<Message>.broadcast();
  final StreamController<UserStatusEvent> _statusController =
      StreamController<UserStatusEvent>.broadcast();
  final StreamController<MessageStatusEvent> _messageStatusController =
      StreamController<MessageStatusEvent>.broadcast();

  Stream<Message> get messageStream => _messageController.stream;
  Stream<UserStatusEvent> get statusStream => _statusController.stream;
  Stream<MessageStatusEvent> get messageStatusStream => _messageStatusController.stream;

  void connect(String url) {
    _disconnect();
    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _channel!.stream.listen(
        (data) {
          _handleMessage(data);
        },
        onError: (error) {
          print('WebSocket error: $error');
          _disconnect();
        },
        onDone: () {
          print('WebSocket disconnected');
          _disconnect();
        },
      );
    } catch (e, stack) {
      print('WebSocket connection failed: $e');
      print(stack);
      _disconnect();
    }
  }

  void _handleMessage(dynamic data) {
    try {
      print('WS Received: $data'); // Debug: Raw payload
      final Map<String, dynamic> json = jsonDecode(data);

      // Handle different message types
      final type = json['type'];
      if (type == 'error') {
        print('WS Error: ${json['error']}');
        return;
      }
      if (type == 'message_ack') {
        print('WS Ack: ${json['message_id']}');
        return;
      }
      if (type == 'user_online' || type == 'user_offline') {
        _statusController.add(UserStatusEvent.fromJson(json));
        return;
      }
      if (type == 'status_update') {
        _messageStatusController.add(MessageStatusEvent.fromJson(json));
        return;
      }

      // Parse as message — auto-send delivery confirmation
      try {
        final message = MessageModel.fromJson(json);
        _messageController.add(message);

        // Auto-send message_delivered for received messages
        _sendDelivered([message.id], message.roomId);
      } catch (e) {
        print('WS: Could not parse as MessageModel: $e');
      }
    } catch (e) {
      print('Failed to parse message: $e');
    }
  }

  /// Send delivery confirmation for message IDs
  void _sendDelivered(List<String> messageIds, String roomId) {
    sendMessage({
      'type': 'message_delivered',
      'room_id': roomId,
      'payload': {'message_ids': messageIds},
    });
  }

  /// Send delivery confirmation for messages loaded via REST
  void sendDeliveredForMessages(List<String> messageIds, String roomId) {
    if (messageIds.isEmpty) return;
    _sendDelivered(messageIds, roomId);
  }

  void sendMessage(Map<String, dynamic> data) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode(data));
    }
  }

  void _disconnect() {
    if (_channel != null) {
      _channel!.sink.close();
      _channel = null;
    }
  }

  void dispose() {
    _disconnect();
    _messageController.close();
    _statusController.close();
    _messageStatusController.close();
  }
}
