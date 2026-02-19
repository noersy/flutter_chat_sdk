import 'dart:async';
import 'package:flutter/foundation.dart';
// ignore: library_prefixes
import 'package:socket_io_client/socket_io_client.dart' as IO;

/// Represents a user's online status change event
class UserStatusEvent {
  final String userId;
  final String username;
  final bool isOnline;
  final DateTime? lastSeen;

  const UserStatusEvent({
    required this.userId,
    required this.username,
    required this.isOnline,
    this.lastSeen,
  });

  factory UserStatusEvent.fromJson(Map<String, dynamic> json) {
    return UserStatusEvent(
      userId: json['user_id'] as String,
      username: json['username'] as String? ?? 'Unknown',
      isOnline: json['is_online'] ?? (json['type'] == 'user_online'),
      lastSeen: json['last_seen'] != null ? DateTime.tryParse(json['last_seen']) : null,
    );
  }
}

/// Represents a batch of message status updates
class MessageStatusEvent {
  final String roomId;
  final List<StatusUpdate> updates;

  const MessageStatusEvent({required this.roomId, required this.updates});

  factory MessageStatusEvent.fromJson(Map<String, dynamic> json) {
    final updatesJson = json['updates'] as List<dynamic>? ?? [];
    return MessageStatusEvent(
      roomId: json['room_id'] as String? ?? '',
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

/// Event for room membership changes
class RoomEvent {
  final String type; // user_joined, user_left, room_users
  final String roomId;
  final String? userId;
  final String? username;
  final List<String> memberIds;

  const RoomEvent({
    required this.type,
    required this.roomId,
    this.userId,
    this.username,
    this.memberIds = const [],
  });

  factory RoomEvent.fromJson(Map<String, dynamic> json) {
    return RoomEvent(
      type: json['type'] as String? ?? '',
      roomId: json['room_id'] as String? ?? '',
      userId: json['user_id'] as String?,
      username: json['username'] as String?,
      memberIds: (json['users'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    );
  }
}

class WebSocketService {
  IO.Socket? _socket;

  final StreamController<dynamic> _messageController = StreamController<dynamic>.broadcast();
  final StreamController<UserStatusEvent> _statusController =
      StreamController<UserStatusEvent>.broadcast();
  final StreamController<MessageStatusEvent> _messageStatusController =
      StreamController<MessageStatusEvent>.broadcast();
  final StreamController<RoomEvent> _roomEventController = StreamController<RoomEvent>.broadcast();

  Stream<dynamic> get messageStream => _messageController.stream;
  Stream<UserStatusEvent> get statusStream => _statusController.stream;
  Stream<MessageStatusEvent> get messageStatusStream => _messageStatusController.stream;
  Stream<RoomEvent> get roomEventStream => _roomEventController.stream;

  /// Connect using Socket.IO protocol.
  /// [url] should be http(s)://host:port (e.g. "http://localhost:8080")
  void connect(String url) {
    _disconnect();

    debugPrint('Connecting to Socket.IO at: $url/socket.io/');
    _socket = IO.io(
      url,
      IO.OptionBuilder()
          .setPath('/socket.io/')
          .setTransports(['polling', 'websocket'])
          .enableForceNewConnection()
          .build(),
    );

    _socket!.onConnect((_) {
      debugPrint('Socket.IO connected');
    });

    _socket!.on('message', (data) {
      try {
        if (data is List) {
          for (var item in data) {
            final json = _toMap(item);
            if (json != null) {
              _messageController.add(json);
            }
          }
        } else {
          final json = _toMap(data);
          if (json != null) {
            _messageController.add(json);
          }
        }
      } catch (e) {
        debugPrint('WS: Could not parse message: $e');
      }
    });

    _socket!.on('user_online', (data) {
      final json = _toMap(data);
      if (json != null) {
        json['type'] = 'user_online';
        _statusController.add(UserStatusEvent.fromJson(json));
      }
    });

    _socket!.on('user_offline', (data) {
      final json = _toMap(data);
      if (json != null) {
        json['type'] = 'user_offline';
        _statusController.add(UserStatusEvent.fromJson(json));
      }
    });

    _socket!.on('room_users', (data) {
      final json = _toMap(data);
      if (json != null) {
        json['type'] = 'room_users';
        _roomEventController.add(RoomEvent.fromJson(json));
      }
    });

    _socket!.on('user_joined', (data) {
      final json = _toMap(data);
      if (json != null) {
        json['type'] = 'user_joined';
        _roomEventController.add(RoomEvent.fromJson(json));
      }
    });

    _socket!.on('user_left', (data) {
      final json = _toMap(data);
      if (json != null) {
        json['type'] = 'user_left';
        _roomEventController.add(RoomEvent.fromJson(json));
      }
    });

    _socket!.on('error', (data) {
      debugPrint('Socket.IO error: $data');
    });

    _socket!.onDisconnect((_) {
      debugPrint('Socket.IO disconnected');
    });

    _socket!.onConnectError((err) {
      debugPrint('❌ Socket.IO connect error: $err');
    });

    _socket!.onError((data) {
      debugPrint('❌ Socket.IO error event: $data');
    });

    // Add connection timeout logging
    Future.delayed(Duration(seconds: 5), () {
      if (_socket != null && !_socket!.connected) {
        debugPrint('⏱️ Socket.IO connection timeout after 5 seconds');
      }
    });

    // _socket!.connect(); // Auto-connect is enabled by default
  }

  /// Emit a socket.io event with a data payload.
  void emit(String event, Map<String, dynamic> data) {
    _socket?.emit(event, data);
  }

  /// Listen to a custom event.
  void on(String event, Function(dynamic) handler) {
    _socket?.on(event, handler);
  }

  /// Remove a custom event listener.
  void off(String event) {
    _socket?.off(event);
  }

  void _disconnect() {
    if (_socket != null) {
      _socket!.dispose();
      _socket = null;
    }
  }

  void dispose() {
    _disconnect();
    _messageController.close();
    _statusController.close();
    _messageStatusController.close();
    _roomEventController.close();
    _roomEventController.close();
  }

  /// Safely converts socket.io event data to `Map<String, dynamic>`.
  /// The socket_io_client may deliver data as a Map or as a List with one Map.
  Map<String, dynamic>? _toMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is List && data.isNotEmpty) return _toMap(data.first);
    return null;
  }
}
