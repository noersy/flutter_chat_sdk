import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import 'core/websocket_service.dart';
import 'domain/entities/user.dart';
import 'domain/entities/unsend_event.dart';
import 'domain/entities/read_receipt_event.dart';
import 'domain/entities/typing_event.dart';

export 'core/websocket_service.dart' show PresenceEvent;
export 'domain/entities/typing_event.dart';

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
  static const _storageTokenKey = 'chat_sdk_token';

  String? _currentToken;

  // Streams
  final _userController = StreamController<User?>.broadcast();
  Stream<User?> get userStream => _userController.stream;

  final _messagesController = StreamController<dynamic>.broadcast();
  Stream<dynamic> get messageStream => _messagesController.stream;

  // Presence Stream
  Stream<PresenceEvent> get presenceStream => _webSocketService.presenceStream;

  // Unsend and read receipt streams
  Stream<UnsendEvent> get unsendStream => _webSocketService.unsendStream;
  Stream<ReadReceiptEvent> get readReceiptStream => _webSocketService.readReceiptStream;

  // Typing indicator stream
  Stream<TypingEvent> get typingStream => _webSocketService.typingStream;

  // Connection state stream (true = connected, false = disconnected)
  Stream<bool> get connectionStream => _webSocketService.connectionStream;

  // --- Offline message queue ---
  /// Pending messages that failed to send because the socket/HTTP was unavailable.
  /// Flushed automatically when the connection is restored.
  final List<Map<String, dynamic>> _offlineQueue = [];
  StreamSubscription<bool>? _connectionSub;

  // --- Typing debounce ---
  /// Active debounce timers keyed by room_id. Prevents flooding the server with
  /// typing_stop events when the user pauses briefly between keystrokes.
  final Map<String, Timer> _typingTimers = {};

  bool _initialized = false;
  String? _wsUrl;
  String? _apiUrl;

  /// Initialize the SDK.
  /// [wsUrl]: Socket.IO server URL (e.g. "http://localhost:8080")
  /// [apiUrl]: HTTP API URL (e.g. "http://localhost:8080")
  /// [token]: optional JWT token for immediate connection
  Future<void> init({
    required String wsUrl,
    required String apiUrl,
    String? userId,
    String? username,
    String? token,
  }) async {
    if (_initialized) return;

    _wsUrl = wsUrl;
    _apiUrl = apiUrl;
    _webSocketService = WebSocketService();

    _webSocketService.messageStream.listen((message) {
      _messagesController.add(message);
    });

    // Flush offline queue whenever the socket connects or reconnects
    _connectionSub = _webSocketService.connectionStream.listen((connected) {
      if (connected && _offlineQueue.isNotEmpty) {
        _flushOfflineQueue();
      }
    });

    if (userId != null && username != null && token != null) {
      await connect(userId: userId, username: username, token: token);
    } else {
      await _restoreSession();
    }

    _initialized = true;
  }

  /// Connect to the Socket.IO server and authenticate.
  Future<void> connect({
    required String userId,
    required String username,
    required String token,
  }) async {
    _currentUser = User(
      id: userId,
      username: username,
      email: '',
      isOnline: true,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _currentToken = token;
    _userController.add(_currentUser);

    await _storage.write(key: _storageUserKey, value: userId);
    await _storage.write(key: _storageUsernameKey, value: username);
    await _storage.write(key: _storageTokenKey, value: token);

    // Set Dio Authorization interceptor
    _dio.interceptors.clear();
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.headers['Authorization'] = 'Bearer $_currentToken';
          handler.next(options);
        },
      ),
    );

    _connectSocketIO(token);
  }

  void _connectSocketIO(String token) {
    if (_currentUser == null || _wsUrl == null) return;
    debugPrint('Connecting to Socket.IO: $_wsUrl');
    // WebSocketService handles connection
    _webSocketService.connect(_wsUrl!, token);
  }

  /// Logout / Disconnect
  Future<void> disconnect() async {
    _cancelAllTypingTimers();
    _connectionSub?.cancel();
    _connectionSub = null;
    _offlineQueue.clear();

    await _storage.delete(key: _storageUserKey);
    await _storage.delete(key: _storageUsernameKey);
    await _storage.delete(key: _storageTokenKey);
    _currentUser = null;
    _currentToken = null;
    _userController.add(null);
    _webSocketService.dispose();
    _initialized = false;
  }

  /// Join a room (normal socket join)
  void joinRoom(String roomId) {
    _requireAuth();
    debugPrint('[ChatSDK] joinRoom: $roomId');
    _webSocketService.emit('join', {'room_id': roomId});
  }

  /// Leave a room (normal socket leave)
  /// Note: Support for this on backend might be missing or optional.
  void leaveRoom(String roomId) {
    _requireAuth();
    _webSocketService.emit('leave', {'room_id': roomId});
  }

  /// Join presence channel for a room/topic
  /// [payload]: additional info (e.g. user details) to share
  void joinPresence(String roomId, Map<String, dynamic> payload) {
    _requireAuth();
    debugPrint('[ChatSDK] joinPresence: room=$roomId, payload=$payload');
    _webSocketService.emit('presence_subscribe', {'room_id': roomId, 'payload': payload});
  }

  /// Leave presence channel.
  /// [payload] is optional — backend will fall back to the payload stored at
  /// subscribe time if an empty map is sent.
  void leavePresence(String roomId, [Map<String, dynamic>? payload]) {
    _requireAuth();
    _webSocketService.emit('presence_unsubscribe', {'room_id': roomId, 'payload': payload ?? {}});
  }

  /// Send a message via HTTP POST.
  ///
  /// If the connection is currently unavailable (no socket / HTTP unreachable),
  /// the message is added to an offline queue and sent automatically once the
  /// connection is restored. The caller receives no exception in that case.
  ///
  /// If [allowOfflineQueue] is false the method throws immediately when offline
  /// instead of queuing (useful for UI that wants to show an explicit error).
  Future<void> sendMessage(
    Map<String, dynamic> messageData, {
    bool allowOfflineQueue = true,
  }) async {
    _requireAuth();
    if (_apiUrl == null) throw Exception('API URL not set');

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
        {'topic': roomId, 'event': 'message', 'payload': fullPayload},
      ],
    };

    // If offline, enqueue for later delivery
    if (!_webSocketService.isConnected) {
      if (!allowOfflineQueue) {
        throw Exception('Cannot send message: not connected');
      }
      _offlineQueue.add(body);
      debugPrint('[ChatSDK] Offline — message queued (queue size: ${_offlineQueue.length})');
      return;
    }

    try {
      await _dio.post('$_apiUrl/messages', data: body);
    } catch (e) {
      if (allowOfflineQueue) {
        _offlineQueue.add(body);
        debugPrint('[ChatSDK] Send failed — message queued (queue size: ${_offlineQueue.length})');
      } else {
        debugPrint('Failed to send message: $e');
        rethrow;
      }
    }
  }

  /// Request a presigned URL from the backend to upload a file to MinIO.
  Future<Map<String, dynamic>> _getPresignedUrl(String fileName, String mimeType) async {
    if (_apiUrl == null) throw Exception('API URL not set');

    final response = await _dio.get(
      '$_apiUrl/api/upload/presigned-url',
      queryParameters: {'filename': fileName, 'mimetype': mimeType},
    );
    return response.data as Map<String, dynamic>;
  }

  /// Execute an HTTP PUT directly to the MinIO presigned URL to push the file.
  Future<void> _uploadFile(
    List<int> fileBytes,
    String presignedUrl,
    String mimeType, {
    void Function(int count, int total)? onProgress,
  }) async {
    // We send raw bytes for direct PUT binary upload, avoiding Multipart/form-data
    // Note: We MUST use a fresh Dio instance here to prevent the ChatClient's global
    // interceptor from injecting the JWT Authorization header, which crashes S3 presigned URLs.
    try {
      final uploadClient = Dio();
      await uploadClient.put(
        presignedUrl,
        data: fileBytes,
        options: Options(
          headers: {'Content-Type': mimeType, Headers.contentLengthHeader: fileBytes.length},
        ),
        onSendProgress: onProgress,
      );
    } on DioException catch (e) {
      debugPrint('[ChatSDK] MinIO Upload Failed. Status: ${e.response?.statusCode}');
      debugPrint('[ChatSDK] MinIO Upload Error Body: ${e.response?.data}');
      rethrow;
    }
  }

  /// Sends a file message (image, document, etc.) to a room.
  ///
  /// The upload happens directly from the client device to MinIO storage.
  /// Once uploaded, a standard chat message is emitted containing the file's metadata URL.
  Future<void> sendFileMessage({
    required String roomId,
    required List<int> fileBytes,
    required String fileName,
    required String mimeType,
    int? fileSize,
    String? content,
    void Function(int count, int total)? onProgress,
  }) async {
    _requireAuth();

    // 1. Get Presigned URL
    debugPrint('[ChatSDK] Requesting presigned URL for $fileName');
    final presignedData = await _getPresignedUrl(fileName, mimeType);
    final pUrl = presignedData['presignedUrl'] as String;
    final fileUrl = presignedData['fileUrl'] as String;

    // 2. Upload the file direct to MinIO
    debugPrint('[ChatSDK] Uploading file directly to storage...');
    await _uploadFile(fileBytes, pUrl, mimeType, onProgress: onProgress);

    // 3. Dispatch standard WS chat message with attachment
    debugPrint('[ChatSDK] File uploaded, dispatching WS message');

    final messageData = {
      'room_id': roomId,
      'content': content ?? '',
      'attachment': {'url': fileUrl, 'type': mimeType, 'name': fileName, 'size': fileSize},
    };

    // We don't queue file messages immediately if offline - upload would have failed first anyway.
    await sendMessage(messageData, allowOfflineQueue: false);
  }

  /// Unsend (soft-delete) a previously sent message.
  /// Only the original sender should call this.
  Future<void> unsendMessage({required String messageId, required String roomId}) async {
    _requireAuth();
    _webSocketService.emit('message_unsend', {'message_id': messageId, 'room_id': roomId});
  }

  /// Mark a message as read by the current user.
  /// Call this when the message becomes visible in the viewport.
  void markMessageRead({required String messageId, required String roomId}) {
    _requireAuth();
    _webSocketService.emit('message_read', {'message_id': messageId, 'room_id': roomId});
  }

  /// Fetch paginated message history for a room via HTTP.
  /// [before]: ISO timestamp cursor for loading older messages.
  /// Returns raw JSON list; map to ChatMessage.fromJson() as needed.
  Future<List<Map<String, dynamic>>> getRoomHistory({
    required String roomId,
    int limit = 50,
    String? before,
    bool autoMarkRead = true,
  }) async {
    _requireAuth();
    if (_apiUrl == null) throw Exception('API URL not set');

    final queryParams = <String, dynamic>{'limit': limit};
    if (before != null) queryParams['before'] = before;

    try {
      final response = await _dio.get(
        '$_apiUrl/rooms/$roomId/messages',
        queryParameters: queryParams,
      );
      final data = response.data as Map<String, dynamic>;
      final rawList = data['messages'] as List<dynamic>? ?? [];
      final messages = rawList.map((e) => Map<String, dynamic>.from(e as Map)).toList();

      if (autoMarkRead) {
        int unreadCount = 0;
        final myId = _currentUser!.id;

        for (var msg in messages) {
          if (msg['user_id']?.toString() != myId && msg['user_id'] != 'system') {
            final readBy = msg['read_by'] as List<dynamic>? ?? [];
            final alreadyRead = readBy.any((r) => r is Map && r['user_id'] == myId);
            if (!alreadyRead) {
              final msgId = msg['id'] as String?;
              if (msgId != null) {
                unreadCount++;
                Future.delayed(Duration(milliseconds: 100 * unreadCount + 500), () {
                  markMessageRead(messageId: msgId, roomId: roomId);
                });
              }
            }
          }
        }
      }

      return messages;
    } catch (e) {
      debugPrint('[ChatSDK] getRoomHistory error: $e');
      rethrow;
    }
  }

  // --- Typing indicator ---

  /// Notify the server that the current user started typing in [roomId].
  ///
  /// Repeated calls within [debounceDuration] are coalesced into a single event
  /// so the server is not flooded on every keystroke. The server also applies
  /// an 8 s auto-stop, but calling [stopTyping] explicitly is preferred.
  void startTyping(String roomId, {Duration debounceDuration = const Duration(milliseconds: 500)}) {
    _requireAuth();

    final existing = _typingTimers[roomId];
    if (existing == null) {
      // No active timer — first keystroke in this burst; emit immediately
      _webSocketService.emit('typing_start', {'room_id': roomId});
    } else {
      // Already typing — just reset the debounce timer below
      existing.cancel();
    }

    // Schedule automatic stop after user goes idle for [debounceDuration]
    _typingTimers[roomId] = Timer(debounceDuration, () {
      _webSocketService.emit('typing_stop', {'room_id': roomId});
      _typingTimers.remove(roomId);
    });
  }

  /// Notify the server that the current user stopped typing in [roomId].
  /// Call this when the message is sent or the input is cleared.
  void stopTyping(String roomId) {
    _requireAuth();
    _typingTimers.remove(roomId)?.cancel();
    _webSocketService.emit('typing_stop', {'room_id': roomId});
  }

  void _cancelAllTypingTimers() {
    for (final t in _typingTimers.values) {
      t.cancel();
    }
    _typingTimers.clear();
  }

  // --- Offline queue ---

  /// Returns a read-only snapshot of the current offline queue length.
  int get offlineQueueLength => _offlineQueue.length;

  /// Sends all queued messages in order. Called automatically on reconnect.
  Future<void> _flushOfflineQueue() async {
    if (_offlineQueue.isEmpty) return;
    debugPrint('[ChatSDK] Flushing offline queue (${_offlineQueue.length} messages)');

    // Snapshot and clear so new offline messages during flush go to a fresh queue
    final pending = List<Map<String, dynamic>>.from(_offlineQueue);
    _offlineQueue.clear();

    for (final body in pending) {
      try {
        await _dio.post('$_apiUrl/messages', data: body);
      } catch (e) {
        // Re-queue failed messages at the front for the next flush
        _offlineQueue.insert(0, body);
        debugPrint('[ChatSDK] Re-queued message after flush failure: $e');
        break; // Stop on first failure to preserve order
      }
    }
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

  /// Remove a custom event listener. Optionally provide the specific handler to remove.
  void off(String event, [Function(dynamic)? handler]) {
    if (!_initialized) return;
    _webSocketService.off(event, handler);
  }

  Future<void> _restoreSession() async {
    final userId = await _storage.read(key: _storageUserKey);
    final username = await _storage.read(key: _storageUsernameKey);
    final token = await _storage.read(key: _storageTokenKey);
    if (userId != null && username != null && token != null) {
      await connect(userId: userId, username: username, token: token);
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
  }
}
