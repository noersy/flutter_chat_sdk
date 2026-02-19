import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import 'core/websocket_service.dart';
import 'domain/entities/user.dart';

export 'core/websocket_service.dart'
    show UserStatusEvent, MessageStatusEvent, StatusUpdate, RoomEvent;

class ChatClient {
  static final ChatClient _instance = ChatClient._internal();
  factory ChatClient() => _instance;
  ChatClient._internal();

  late WebSocketService _webSocketService;
  final Dio _dio = Dio();
  final _uuid = const Uuid();

  User? _currentUser;
  User? get currentUser => _currentUser;

  final _storage = const FlutterSecureStorage();
  static const _storageUserKey = 'chat_sdk_user_id';
  static const _storageUsernameKey = 'chat_sdk_username';

  // Streams
  final _userController = StreamController<User?>.broadcast();
  Stream<User?> get userStream => _userController.stream;

  final _messagesController = StreamController<dynamic>.broadcast();
  Stream<dynamic> get messageStream => _messagesController.stream;

  Stream<UserStatusEvent> get userStatusStream => _webSocketService.statusStream;

  Stream<MessageStatusEvent> get statusUpdateStream => _messageStatusController.stream;
  final _messageStatusController = StreamController<MessageStatusEvent>.broadcast();

  Stream<RoomEvent> get roomEventStream => _webSocketService.roomEventStream;

  bool _initialized = false;
  String? _wsUrl;
  String? _apiUrl;

  /// Initialize the SDK.
  /// [wsUrl]: Socket.IO server URL (e.g. "http://localhost:8080")
  /// [apiUrl]: HTTP API URL (e.g. "http://localhost:8080")
  Future<void> init({
    required String wsUrl,
    required String apiUrl,
    String? userId,
    String? username,
  }) async {
    if (_initialized) return;

    _wsUrl = wsUrl;
    _apiUrl = apiUrl;
    _webSocketService = WebSocketService();

    _webSocketService.messageStream.listen((message) {
      _messagesController.add(message);
    });

    _webSocketService.messageStatusStream.listen((status) {
      _messageStatusController.add(status);
    });

    if (userId != null && username != null) {
      await connect(userId, username);
    } else {
      await _restoreSession();
    }

    _initialized = true;
  }

  /// Connect to the Socket.IO server and authenticate.
  Future<void> connect(String userId, String username) async {
    _currentUser = User(
      id: userId,
      username: username,
      email: '',
      isOnline: true,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _userController.add(_currentUser);

    await _storage.write(key: _storageUserKey, value: userId);
    await _storage.write(key: _storageUsernameKey, value: username);

    _connectSocketIO();
  }

  void _connectSocketIO() {
    if (_currentUser == null || _wsUrl == null) return;
    debugPrint('Connecting to Socket.IO: $_wsUrl');
    // WebSocketService handles connection
    _webSocketService.connect(_wsUrl!);
  }

  /// Logout / Disconnect
  Future<void> disconnect() async {
    await _storage.delete(key: _storageUserKey);
    await _storage.delete(key: _storageUsernameKey);
    _currentUser = null;
    _userController.add(null);
    _webSocketService.dispose();
    _initialized = false;
  }

  /// Join a room
  void joinRoom(String roomId) {
    _requireAuth();
    _webSocketService.emit('join', {'room_id': roomId});
  }

  /// Leave a room
  void leaveRoom(String roomId) {
    _requireAuth();
    _webSocketService.emit('leave', {'room_id': roomId});
  }

  /// Send a message via HTTP POST.
  /// Only requires [content] and [roomId] (or [topic]).
  /// Other fields can be passed via the optional [extraData] Map.
  Future<void> sendMessage(Map<String, dynamic> messageData) async {
    _requireAuth();
    if (_apiUrl == null) throw Exception('API URL not set');

    // Prepare payload matching backend expectations
    // Backend expects: { messages: [ { topic, event, payload } ] }
    // But for 'message' event, the payload itself is the message data.

    // Important: we need to construct the FULL message object client-side now
    // because the backend just broadcasts what we send.

    final roomId = (messageData['room_id'] ?? messageData['topic']) as String?;
    if (roomId == null) throw Exception('room_id is required');

    final messageId = _uuid.v4();
    final timestamp = DateTime.now().toIso8601String();

    final fullPayload = {
      ...messageData,
      'id': messageId,
      'user_id': _currentUser!.id,
      'username': _currentUser!.username,
      'created_at': timestamp,
      'topic': roomId,
      'room_id': roomId,
    };

    final body = {
      'messages': [
        {
          'topic': roomId,
          'event': 'message', // Standard chat event
          'payload': fullPayload,
        },
      ],
    };

    try {
      await _dio.post('$_apiUrl/messages', data: body);
    } catch (e) {
      debugPrint('Failed to send message: $e');
      rethrow;
    }
  }

  /// Subscribe to another user's online/offline status
  void subscribeStatus(String targetUserId) {
    _requireAuth();
    _webSocketService.emit('subscribe_status', {'target_user_id': targetUserId});
  }

  /// Unsubscribe from another user's status
  void unsubscribeStatus(String targetUserId) {
    _requireAuth();
    _webSocketService.emit('unsubscribe_status', {'target_user_id': targetUserId});
  }

  /// Listen to a custom event.
  /// [event] is the name of the event to listen to.
  /// [handler] is the function to call when the event is received.
  void on(String event, Function(dynamic) handler) {
    // We don't strictly require auth for listening, but socket must be initialized.
    if (!_initialized) {
      throw Exception('SDK not initialized');
    }
    _webSocketService.on(event, handler);
  }

  /// Remove a custom event listener.
  void off(String event) {
    if (!_initialized) return;
    _webSocketService.off(event);
  }

  Future<void> _restoreSession() async {
    final userId = await _storage.read(key: _storageUserKey);
    final username = await _storage.read(key: _storageUsernameKey);
    if (userId != null && username != null) {
      await connect(userId, username);
    }
  }

  void _requireAuth() {
    if (_currentUser == null) {
      throw Exception('User not connected');
    }
  }

  void dispose() {
    _webSocketService.dispose();
    _userController.close();
    _messagesController.close();
    _messageStatusController.close();
  }
}
