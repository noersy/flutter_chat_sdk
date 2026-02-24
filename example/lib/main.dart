import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_chat_sdk/flutter_chat_sdk.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:cached_network_image/cached_network_image.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stateless Chat Example',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const ConnectionPage(),
    );
  }
}

class ConnectionPage extends StatefulWidget {
  const ConnectionPage({super.key});

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  final _userIdController = TextEditingController(
    text: 'user-${DateTime.now().millisecondsSinceEpoch}',
  );
  final _usernameController = TextEditingController(text: 'User');
  final _wsUrlController = TextEditingController(text: 'http://localhost:3000');
  final _apiUrlController = TextEditingController(text: 'http://localhost:3000');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connect to Chat')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _wsUrlController,
              decoration: const InputDecoration(labelText: 'WebSocket URL'),
            ),
            TextField(
              controller: _apiUrlController,
              decoration: const InputDecoration(labelText: 'API URL (HTTP)'),
            ),
            TextField(
              controller: _userIdController,
              decoration: const InputDecoration(labelText: 'User ID'),
            ),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(labelText: 'Username'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ChatPage(
                      wsUrl: _wsUrlController.text,
                      apiUrl: _apiUrlController.text,
                      userId: _userIdController.text.trim(),
                      username: _usernameController.text.trim(),
                    ),
                  ),
                );
              },
              child: const Text('Connect'),
            ),
          ],
        ),
      ),
    );
  }
}

class ChatPage extends StatefulWidget {
  final String wsUrl;
  final String apiUrl;
  final String userId;
  final String username;

  const ChatPage({
    super.key,
    required this.wsUrl,
    required this.apiUrl,
    required this.userId,
    required this.username,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final ChatClient _client = ChatClient();
  final _roomController = TextEditingController(text: 'general');
  final _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();

  String _currentRoomId = 'general';
  final List<Map<String, dynamic>> _messages = [];
  bool _isLoadingHistory = false;
  final ScrollController _scrollController = ScrollController();

  // Connection state
  bool _isConnected = false;

  // Track online users manually from presence events
  final Map<String, Map<String, dynamic>> _onlineUsers = {};

  // Track users currently typing
  final Set<String> _typingUsers = {};

  // Stream subscriptions for cleanup
  StreamSubscription? _messageSubscription;
  StreamSubscription? _presenceSubscription;
  StreamSubscription? _typingSubscription;
  StreamSubscription? _unsendSubscription;
  StreamSubscription? _readReceiptSubscription;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _userSubscription;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Generate a token for testing
    final jwt = JWT({'sub': widget.userId, 'username': widget.username, 'status': 'active'});
    // Matches JWT_SECRET in backend .env
    final token = jwt.sign(SecretKey('fof3jXLFKHGSJX57gK3CymlmVYiKiUSkrauz9qlWI3w='));

    await _client.init(
      wsUrl: widget.wsUrl,
      apiUrl: widget.apiUrl,
      userId: widget.userId,
      username: widget.username,
      token: token,
    );

    // Listen to connection state
    _connectionSubscription = _client.connectionStream.listen((connected) {
      if (!mounted) return;
      setState(() {
        _isConnected = connected;
      });
    });

    // Listen to user session changes
    _userSubscription = _client.userStream.listen((user) {
      if (!mounted) return;
      if (user == null) {
        debugPrint('[Example App] Session ended via userStream.');
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });

    // Setup listeners BEFORE joining room to avoid race condition
    _messageSubscription = _client.messageStream.listen((message) {
      if (!mounted) return;
      if (message is Map<String, dynamic> && message['room_id'] == _currentRoomId) {
        setState(() {
          // Avoid duplicate messages if it was already loaded from history
          final msgId = message['id'];
          if (msgId != null && _messages.any((m) => m['id'] == msgId)) {
            return;
          }
          _messages.add(message);
        });
        _scrollToBottom();

        // Notify server that we've read this incoming message if it's not from us
        if (message['user_id']?.toString() != widget.userId && message['user_id'] != 'system') {
          final msgId = message['id'] as String?;
          if (msgId != null) {
            _client.markMessageRead(messageId: msgId, roomId: _currentRoomId);
          }
        }
      }
    });

    // Listen to presence events
    _presenceSubscription = _client.presenceStream.listen((event) {
      if (!mounted) return;
      setState(() {
        if (event.type == 'sync') {
          _onlineUsers.clear();
          for (var member in event.members) {
            if (member is Map<String, dynamic>) {
              final uid = member['user_id']?.toString() ?? 'unknown';
              _onlineUsers[uid] = member;
            }
          }
        } else if (event.type == 'join') {
          final member = event.member;
          if (member != null) {
            final uid = member['user_id']?.toString() ?? 'unknown';
            _onlineUsers[uid] = member;

            if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('${member['username'] ?? uid} joined')));
            }
          }
        } else if (event.type == 'leave') {
          final member = event.member;
          if (member != null) {
            final uid = member['user_id']?.toString() ?? 'unknown';
            _onlineUsers.remove(uid);

            if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('${member['username'] ?? uid} left')));
            }
          }
        }
      });
    });

    // Listen to typing events
    _typingSubscription = _client.typingStream.listen((event) {
      if (!mounted) return;
      // Only process events for the current room and ignore self-typing events
      if (event.roomId == _currentRoomId && event.userId != widget.userId) {
        setState(() {
          if (event.isTyping) {
            _typingUsers.add(event.username);
          } else {
            _typingUsers.remove(event.username);
          }
        });
      }
    });

    // Listen to unsend events
    _unsendSubscription = _client.unsendStream.listen((event) {
      if (!mounted) return;
      if (event.roomId == _currentRoomId) {
        setState(() {
          _messages.removeWhere((msg) => msg['id'] == event.messageId);
        });
      }
    });

    // Listen to read receipt events
    _readReceiptSubscription = _client.readReceiptStream.listen((event) {
      if (!mounted) return;
      if (event.roomId == _currentRoomId) {
        setState(() {
          // Find the message and update its read_by list
          final index = _messages.indexWhere((msg) => msg['id'] == event.messageId);
          if (index != -1) {
            final msg = _messages[index];
            final rawReadBy = msg['read_by'];
            List<dynamic> readByList = [];

            if (rawReadBy is List) {
              readByList = List.from(rawReadBy);
            }

            // Check if already read by this user
            final alreadyRead = readByList.any(
              (r) => r is Map && r['user_id'] == event.readBy.userId,
            );
            if (!alreadyRead) {
              readByList.add({
                'user_id': event.readBy.userId,
                'username': event.readBy.username,
                'read_at': event.readBy.readAt.toIso8601String(),
              });

              // Only update if it actually changed to trigger rebuild
              // We create a new map to ensure the reference changes and UI rebuilds correctly
              _messages[index] = Map<String, dynamic>.from(msg)..['read_by'] = readByList;
            }
          }
        });
      }
    });

    // Now join room after listeners are ready
    debugPrint('✅ Initialized, joining room...');
    _joinRoom(_currentRoomId);

    // Listen to custom 'system_announcement' event
    _client.on('system_announcement', (data) {
      debugPrint('📢 Received system announcement: $data');
      if (data is Map) {
        final message = data['message'] ?? 'No message content';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('📢 System Announcement: $message'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    });
  }

  void _joinRoom(String roomId) {
    if (_currentRoomId != roomId) {
      _client.leaveRoom(_currentRoomId);
      // Leave old presence
      _client.leavePresence(_currentRoomId, {
        'user_id': widget.userId,
        'username': widget.username,
      });

      setState(() {
        _messages.clear();
        _onlineUsers.clear(); // Clear members when switching rooms
        _typingUsers.clear(); // Clear typing status
        _currentRoomId = roomId;
      });
    }

    _client.joinRoom(roomId);

    // Join new presence
    _client.joinPresence(roomId, {
      'user_id': widget.userId,
      'username': widget.username,
      'entered_at': DateTime.now().toIso8601String(),
    });

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Joined room: $roomId')));

    // Fetch History
    _fetchRoomHistory(roomId);
  }

  Future<void> _fetchRoomHistory(String roomId) async {
    setState(() {
      _isLoadingHistory = true;
    });

    try {
      final history = await _client.getRoomHistory(roomId: roomId, limit: 50);

      if (mounted && _currentRoomId == roomId) {
        setState(() {
          _messages.clear();

          List<Map<String, dynamic>> formattedHistory = [];
          for (var msg in history) {
            formattedHistory.add(Map<String, dynamic>.from(msg));
          }
          // The backend already returns messages in chronological order (oldest first).
          _messages.addAll(formattedHistory);
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load history: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingHistory = false;
        });
      }
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.isEmpty) return;

    try {
      await _client.sendMessage({
        'room_id': _currentRoomId,
        'content': _messageController.text,
        'type': 'text',
      });
      _messageController.clear();
      _client.stopTyping(_currentRoomId);
      _messageFocusNode.requestFocus();
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send message: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _scrollToBottom() {
    // Postpone the scroll until the layout is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _presenceSubscription?.cancel();
    _typingSubscription?.cancel();
    _unsendSubscription?.cancel();
    _readReceiptSubscription?.cancel();
    _connectionSubscription?.cancel();
    _userSubscription?.cancel();
    _client.disconnect();
    _messageFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Chat: $_currentRoomId'),
            if (_onlineUsers.isNotEmpty)
              Text('${_onlineUsers.length} Online', style: const TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isConnected ? Colors.green : Colors.red,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _isConnected ? 'Connected' : 'Disconnected',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),

          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.people),
              onPressed: () => Scaffold.of(context).openEndDrawer(),
              tooltip: 'Room Members',
            ),
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: () => _client.disconnect()),
        ],
      ),
      endDrawer: Drawer(
        child: Column(
          children: [
            const DrawerHeader(child: Center(child: Text("Room Members"))),
            Expanded(
              child: ListView.builder(
                itemCount: _onlineUsers.length,
                itemBuilder: (context, index) {
                  final user = _onlineUsers.values.elementAt(index);
                  final isMe = user['user_id']?.toString().trim() == widget.userId.trim();
                  final username = user['username'] ?? 'Unknown';

                  return ListTile(
                    leading: const CircleAvatar(backgroundColor: Colors.green, radius: 5),
                    title: Text(isMe ? '$username (You)' : username),
                    subtitle: const Text(
                      'Online',
                      style: TextStyle(fontSize: 12, color: Colors.green),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Disconnected Banner
          if (!_isConnected)
            Container(
              width: double.infinity,
              color: Colors.red.shade100,
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: const Text(
                'You are currently offline. Messages will be queued.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),

          // Room Switcher
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _roomController,
                    decoration: const InputDecoration(
                      labelText: 'Room ID',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _joinRoom(_roomController.text),
                  child: const Text('Join'),
                ),
              ],
            ),
          ),

          Expanded(
            child: _isLoadingHistory
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final userId = msg['user_id']?.toString() ?? 'unknown';
                      final username = msg['username'] as String? ?? 'Unknown';
                      final content = msg['content'] as String? ?? '';
                      final createdAtStr = msg['created_at'] as String?;
                      final createdAt = createdAtStr != null
                          ? DateTime.tryParse(createdAtStr)
                          : null;
                      final rawReadBy = msg['read_by'] as List<dynamic>? ?? [];

                      final isMe = userId.trim() == widget.userId.trim();
                      final isSystem = userId.trim() == 'system';

                      return ListTile(
                        title: Align(
                          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                          child: GestureDetector(
                            onLongPress: isMe
                                ? () {
                                    final messageId = msg['id'] as String?;
                                    if (messageId != null) {
                                      showDialog(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: const Text('Unsend Message'),
                                          content: const Text(
                                            'Are you sure you want to delete this message?',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(ctx),
                                              child: const Text('Cancel'),
                                            ),
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.red,
                                              ),
                                              onPressed: () {
                                                Navigator.pop(ctx);
                                                _client.unsendMessage(
                                                  messageId: messageId,
                                                  roomId: _currentRoomId,
                                                );
                                              },
                                              child: const Text(
                                                'Delete',
                                                style: TextStyle(color: Colors.white),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                  }
                                : null,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isSystem
                                    ? Colors.orange[50]
                                    : (isMe ? Colors.blue[100] : Colors.grey[200]),
                                borderRadius: BorderRadius.circular(8),
                                border: isSystem ? Border.all(color: Colors.orange[200]!) : null,
                              ),
                              child: Column(
                                crossAxisAlignment: isMe
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (!isMe)
                                        Text(
                                          username,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 10,
                                          ),
                                        ),
                                    ],
                                  ),
                                  if (msg['attachment'] != null && msg['attachment'] is Map)
                                    Builder(
                                      builder: (context) {
                                        final attachment = msg['attachment'] as Map;
                                        final attachType = attachment['type'] as String? ?? '';
                                        final url = attachment['url'] as String?;

                                        if (url != null && attachType.startsWith('image/')) {
                                          return Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(8.0),
                                              child: CachedNetworkImage(
                                                imageUrl: url,
                                                width: 200,
                                                fit: BoxFit.cover,
                                                placeholder: (context, url) => const SizedBox(
                                                  width: 200,
                                                  height: 150,
                                                  child: Center(child: CircularProgressIndicator()),
                                                ),
                                                errorWidget: (context, url, error) =>
                                                    const SizedBox(
                                                      width: 200,
                                                      height: 150,
                                                      child: Center(child: Icon(Icons.error)),
                                                    ),
                                              ),
                                            ),
                                          );
                                        } else if (url != null) {
                                          return Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.insert_drive_file, size: 16),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    attachment['name'] ?? 'File',
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }
                                        return const SizedBox.shrink();
                                      },
                                    ),
                                  if (content.isNotEmpty) Text(content),
                                  if (createdAt != null)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          _formatTime(createdAt),
                                          style: const TextStyle(
                                            fontSize: 8,
                                            color: Colors.black54,
                                          ),
                                        ),
                                        if (isMe) ...[
                                          const SizedBox(width: 4),
                                          Builder(
                                            builder: (ctx) {
                                              // We need at least 1 other person to establish "all read"
                                              // Number of other users in room = total online users - 1 (us)
                                              int totalOtherUsers = _onlineUsers.length > 1
                                                  ? _onlineUsers.length - 1
                                                  : 1;
                                              bool isAllRead =
                                                  rawReadBy.length >= totalOtherUsers &&
                                                  rawReadBy.isNotEmpty;

                                              String readByNames = rawReadBy
                                                  .map(
                                                    (r) => r is Map
                                                        ? (r['username'] ?? 'Unknown')
                                                        : 'Unknown',
                                                  )
                                                  .join(', ');
                                              if (readByNames.isEmpty) readByNames = 'Delivered';

                                              return Tooltip(
                                                message: 'Read by: $readByNames',
                                                child: Icon(
                                                  isAllRead ? Icons.done_all : Icons.check,
                                                  size: 12,
                                                  color: isAllRead ? Colors.blue : Colors.grey,
                                                ),
                                              );
                                            },
                                          ),
                                        ],
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Typing Indicator
          if (_typingUsers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _typingUsers.length == 1
                      ? '${_typingUsers.first} is typing...'
                      : '${_typingUsers.join(', ')} are typing...',
                  style: const TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey,
                  ),
                ),
              ),
            ),

          // Upload Progress Bar
          if (_isUploading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Column(
                children: [
                  const Text('Uploading Attachment...'),
                  LinearProgressIndicator(value: _uploadProgress),
                ],
              ),
            ),

          // Message Input
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file),
                  onPressed: _isUploading ? null : _pickAndUploadImage,
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    focusNode: _messageFocusNode,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Message'),
                    onChanged: (text) {
                      if (text.isNotEmpty) {
                        _client.startTyping(_currentRoomId);
                      } else {
                        _client.stopTyping(_currentRoomId);
                      }
                    },
                    onSubmitted: (_) {
                      _sendMessage();
                      _client.stopTyping(_currentRoomId);
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _isUploading ? null : _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _isUploading = false;
  double _uploadProgress = 0.0;

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
    });

    try {
      final name = image.name;
      final fileLength = await image.length();
      final mime = lookupMimeType(image.name) ?? 'application/octet-stream';
      final bytes = await image.readAsBytes();

      final textContent = _messageController.text;

      await _client.sendFileMessage(
        roomId: _currentRoomId,
        fileBytes: bytes,
        fileName: name,
        mimeType: mime,
        fileSize: fileLength,
        content: textContent.isNotEmpty ? textContent : null,
        onProgress: (count, total) {
          if (mounted && total > 0) {
            setState(() {
              _uploadProgress = count / total;
            });
          }
        },
      );

      // Clear text context if sending attach with a message
      _messageController.clear();
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to upload: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
