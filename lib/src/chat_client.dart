import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'core/api_client.dart';
import 'core/websocket_service.dart';
import 'data/repositories/auth_repository_impl.dart';
import 'data/repositories/chat_repository_impl.dart';
import 'domain/entities/message.dart';
import 'domain/entities/room.dart';
import 'domain/entities/user.dart';

export 'core/websocket_service.dart' show UserStatusEvent, MessageStatusEvent, StatusUpdate;

class ChatClient {
  static final ChatClient _instance = ChatClient._internal();
  factory ChatClient() => _instance;
  ChatClient._internal();

  late ApiClient _apiClient;
  late WebSocketService _webSocketService;
  late AuthRepositoryImpl _authRepository;
  late ChatRepositoryImpl _chatRepository;

  User? _currentUser;
  User? get currentUser => _currentUser;

  // Storage for persisting session (simple user ID storage for now)
  final _storage = const FlutterSecureStorage();
  static const _storageUserKey = 'chat_sdk_user';

  // Streams
  final _userController = StreamController<User?>.broadcast();
  Stream<User?> get userStream => _userController.stream;

  final _messagesController = StreamController<Message>.broadcast();
  Stream<Message> get messageStream => _messagesController.stream;

  /// Stream of user online/offline status changes
  Stream<UserStatusEvent> get userStatusStream => _webSocketService.statusStream;

  /// Stream of message status updates (delivered/read)
  Stream<MessageStatusEvent> get statusUpdateStream => _webSocketService.messageStatusStream;

  bool _initialized = false;
  String? _wsUrl;

  /// Initialize the SDK with base variables
  Future<void> init({required String baseUrl, required String wsUrl}) async {
    if (_initialized) return;

    _wsUrl = wsUrl;
    _apiClient = ApiClient(baseUrl: baseUrl);
    _webSocketService = WebSocketService();

    _authRepository = AuthRepositoryImpl(apiClient: _apiClient);
    _chatRepository = ChatRepositoryImpl(
      apiClient: _apiClient,
      webSocketService: _webSocketService,
    );

    // Listen to WS messages and forward
    _webSocketService.messageStream.listen((message) {
      _messagesController.add(message);
    });

    // Try to restore session
    await _restoreSession();

    // Connect WS if user is logged in
    if (_currentUser != null) {
      _connectWebSocket();
    }

    _initialized = true;
  }

  void _connectWebSocket() {
    if (_currentUser == null || _wsUrl == null) return;
    // Append query params for backend auth
    final url =
        '$_wsUrl?user_id=${_currentUser!.id}&username=${Uri.encodeComponent(_currentUser!.username)}';
    print('Connecting to WS: $url');
    _webSocketService.connect(url);
  }

  /// Register a new user
  Future<User?> register(String username, String email, String password) async {
    final result = await _authRepository.register(username, email, password);
    return result.fold((failure) => throw Exception(failure.message), (user) {
      _updateUser(user);
      return user;
    });
  }

  /// Login existing user
  Future<User?> login(String emailOrUsername, String password) async {
    final result = await _authRepository.login(emailOrUsername, password);
    return result.fold((failure) => throw Exception(failure.message), (user) {
      _updateUser(user);
      return user;
    });
  }

  /// Logout
  Future<void> logout() async {
    await _storage.delete(key: _storageUserKey);
    _currentUser = null;
    _userController.add(null);
    _webSocketService.dispose();
  }

  /// Create a room
  Future<Room> createRoom(String name, String type) async {
    _requireAuth();
    final result = await _chatRepository.createRoomWithCreator(name, type, _currentUser!.id);
    return result.fold((failure) => throw Exception(failure.message), (room) => room);
  }

  /// Get rooms for current user
  Future<List<Room>> getMyRooms() async {
    _requireAuth();
    final result = await _chatRepository.getUserRooms(_currentUser!.id);
    return result.fold((failure) => throw Exception(failure.message), (rooms) => rooms);
  }

  /// Get messages for a room.
  /// Also auto-sends message_delivered for undelivered messages from other users.
  Future<List<Message>> getMessages(String roomId, {int limit = 50, int offset = 0}) async {
    _requireAuth();
    final result = await _chatRepository.getMessages(
      roomId,
      limit: limit,
      offset: offset,
      userId: _currentUser!.id,
    );
    final messages = result.fold(
      (failure) => throw Exception(failure.message),
      (messages) => messages,
    );

    // Auto-send message_delivered for messages from other users that are still 'sent'
    final undeliveredIds = messages
        .where((m) => m.userId != _currentUser!.id && m.status == 'sent')
        .map((m) => m.id)
        .toList();
    if (undeliveredIds.isNotEmpty) {
      _webSocketService.sendDeliveredForMessages(undeliveredIds, roomId);
    }

    return messages;
  }

  /// Join a room (Add member) via REST
  Future<void> joinRoom(String roomId) async {
    _requireAuth();
    final result = await _chatRepository.addMember(roomId, _currentUser!.id);
    result.fold((failure) => throw Exception(failure.message), (_) => null);
  }

  /// Add a specific user to a room
  Future<void> addUserToRoom(String roomId, String userId) async {
    _requireAuth();
    final result = await _chatRepository.addMember(roomId, userId);
    result.fold((failure) => throw Exception(failure.message), (_) => null);
  }

  /// Add a user to a room by username (looks up user first)
  Future<void> addUserToRoomByUsername(String roomId, String username) async {
    _requireAuth();
    // First, get user by username
    final userResult = await _authRepository.getUserByUsername(username);
    final user = userResult.fold((failure) => throw Exception(failure.message), (user) => user);
    // Then add user to room
    final result = await _chatRepository.addMember(roomId, user.id);
    result.fold((failure) => throw Exception(failure.message), (_) => null);
  }

  /// Get members of a room (includes online status)
  Future<List<User>> getRoomMembers(String roomId) async {
    _requireAuth();
    final result = await _chatRepository.getRoomMembers(roomId);
    return result.fold((failure) => throw Exception(failure.message), (members) => members);
  }

  /// Join a room via WebSocket (Required for sending messages)
  void joinRoomWS(String roomId) {
    _requireAuth();
    final msg = {'type': 'join', 'room_id': roomId};
    print('Sending WS Join message: $msg');
    _webSocketService.sendMessage(msg);
  }

  /// Send a message (via WS)
  void sendMessage(String roomId, String content, {String type = 'text'}) {
    _requireAuth();
    final msg = {
      'type': 'message',
      'room_id': roomId,
      'payload': {'content': content, 'type': type},
    };
    print('Sending WS message: $msg'); // Debug log
    _webSocketService.sendMessage(msg);
  }

  /// Mark all messages in a room as read (via WS)
  void markAsRead(String roomId) {
    _requireAuth();
    print('Sending message_read for room $roomId');
    _webSocketService.sendMessage({'type': 'message_read', 'room_id': roomId});
  }

  void _updateUser(User user) {
    print('Updating user: ${user.username}');
    _currentUser = user;
    _userController.add(user);
    _connectWebSocket();
  }

  Future<void> _restoreSession() async {
    // Logic to restore session (e.g. read stored token/user)
    // Since backend has no token verification endpoint, we skip for now.
  }

  void _requireAuth() {
    if (_currentUser == null) {
      throw Exception("User not authenticated");
    }
  }

  void dispose() {
    _webSocketService.dispose();
    _userController.close();
    _messagesController.close();
  }
}
