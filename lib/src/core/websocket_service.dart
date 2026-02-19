import 'dart:async';
import 'package:flutter/foundation.dart';
// ignore: library_prefixes
import 'package:socket_io_client/socket_io_client.dart' as IO;

/// Represents a presence event from the backend
class PresenceEvent {
  final String type; // join, leave, sync
  final String topic;
  final List<dynamic> members; // For sync
  final Map<String, dynamic>? member; // For join/leave

  const PresenceEvent({
    required this.type,
    required this.topic,
    this.members = const [],
    this.member,
  });

  factory PresenceEvent.fromJoin(String topic, Map<String, dynamic> payload) {
    return PresenceEvent(type: 'join', topic: topic, member: payload);
  }

  factory PresenceEvent.fromLeave(String topic, Map<String, dynamic> payload) {
    return PresenceEvent(type: 'leave', topic: topic, member: payload);
  }

  factory PresenceEvent.fromSync(String topic, List<dynamic> members) {
    return PresenceEvent(type: 'sync', topic: topic, members: members);
  }
}

class WebSocketService {
  IO.Socket? _socket;

  final StreamController<dynamic> _messageController = StreamController<dynamic>.broadcast();
  final StreamController<PresenceEvent> _presenceController =
      StreamController<PresenceEvent>.broadcast();

  Stream<dynamic> get messageStream => _messageController.stream;
  Stream<PresenceEvent> get presenceStream => _presenceController.stream;

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

    // --- Presence Events ---

    _socket!.on('presence_join', (data) {
      final json = _toMap(data);
      if (json != null) {
        _presenceController.add(PresenceEvent.fromJoin('unknown', json));
      }
    });

    _socket!.on('presence_leave', (data) {
      final json = _toMap(data);
      if (json != null) {
        _presenceController.add(PresenceEvent.fromLeave('unknown', json));
      }
    });

    _socket!.on('presence_sync', (data) {
      if (data is List) {
        _presenceController.add(PresenceEvent.fromSync('unknown', data));
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
    _presenceController.close();
  }

  /// Safely converts socket.io event data to `Map<String, dynamic>`.
  Map<String, dynamic>? _toMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is List && data.isNotEmpty) return _toMap(data.first);
    return null;
  }
}
