import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_chat_sdk/flutter_chat_sdk.dart';

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
  final _wsUrlController = TextEditingController(text: 'http://localhost:8082');

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
                      userId: _userIdController.text,
                      username: _usernameController.text,
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
  final String userId;
  final String username;

  const ChatPage({super.key, required this.wsUrl, required this.userId, required this.username});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final ChatClient _client = ChatClient();
  final _roomController = TextEditingController(text: 'general');
  final _messageController = TextEditingController();

  String _currentRoomId = 'general';
  final List<Map<String, dynamic>> _messages = [];
  final Map<String, UserStatusEvent> _userStatuses = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _client.init(wsUrl: widget.wsUrl, userId: widget.userId, username: widget.username);

    // Listen for authentication before joining
    _client.authStream.listen((isAuthenticated) {
      if (isAuthenticated) {
        debugPrint('✅ Authenticated, joining room...');
        _joinRoom(_currentRoomId);
      }
    });

    _client.messageStream.listen((message) {
      if (message is Map<String, dynamic> && message['room_id'] == _currentRoomId) {
        setState(() {
          _messages.add(message);
        });

        // Auto-subscribe to status of sender
        final userId = message['user_id'] as String?;
        if (userId != null && userId != widget.userId && !_userStatuses.containsKey(userId)) {
          _client.subscribeStatus(userId);
        }
      }
    });

    _client.userStatusStream.listen((event) {
      setState(() {
        _userStatuses[event.userId] = event;
      });
    });

    // Listen for room membership events
    _client.roomEventStream.listen((event) {
      if (event.roomId != _currentRoomId) return;

      if (event.type == 'room_users') {
        setState(() {
          for (final uid in event.memberIds) {
            // Add placeholder status if not exists
            if (!_userStatuses.containsKey(uid)) {
              _userStatuses[uid] = UserStatusEvent(
                userId: uid,
                username: 'User $uid',
                isOnline: false,
              );
              // Subscribe to get real status & username
              _client.subscribeStatus(uid);
            }
          }
        });
      } else if (event.type == 'user_joined') {
        final uid = event.userId;
        if (uid != null) {
          setState(() {
            _userStatuses[uid] = UserStatusEvent(
              userId: uid,
              username: event.username ?? 'User $uid',
              isOnline: true, // Just joined, so online
            );
          });
          _client.subscribeStatus(uid);
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('${event.username ?? uid} joined')));
          }
        }
      } else if (event.type == 'user_left') {
        final uid = event.userId;
        if (uid != null) {
          setState(() {
            _userStatuses.remove(uid);
            _client.unsubscribeStatus(uid);
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$uid left')));
          }
        }
      }
    });

    // Join the default room
    // _joinRoom(_currentRoomId); // Moved to authStream listener
  }

  void _joinRoom(String roomId) {
    if (_currentRoomId != roomId) {
      _client.leaveRoom(_currentRoomId);
      setState(() {
        _messages.clear();
        _userStatuses.clear(); // Clear members when switching rooms
        _currentRoomId = roomId;
      });
    }
    _client.joinRoom(roomId);

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Joined room: $roomId')));
  }

  void _sendMessage() {
    if (_messageController.text.isEmpty) return;

    _client.sendMessage({
      'room_id': _currentRoomId,
      'content': _messageController.text,
      'type': 'text',
    });
    _messageController.clear();
  }

  void _sendTransactionData() {
    final titleCtrl = TextEditingController(text: 'Order #12345');
    final contentCtrl = TextEditingController(text: 'Check transaction details');
    final categoryCtrl = TextEditingController(text: 'Gaming Account');
    final accountIdCtrl = TextEditingController(text: 'player123');
    final notesCtrl = TextEditingController(text: 'Verified seller');

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send Transaction Data'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              TextField(
                controller: contentCtrl,
                decoration: const InputDecoration(labelText: 'Content'),
              ),
              TextField(
                controller: categoryCtrl,
                decoration: const InputDecoration(labelText: 'Category'),
              ),
              TextField(
                controller: accountIdCtrl,
                decoration: const InputDecoration(labelText: 'Account ID'),
              ),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              _client.sendMessage({
                'room_id': _currentRoomId,
                'content': contentCtrl.text,
                'type': 'data',
                'title': titleCtrl.text,
                'payload': {
                  'category': categoryCtrl.text,
                  'account_id': accountIdCtrl.text,
                  'notes': notesCtrl.text,
                },
              });
              Navigator.pop(ctx);
            },
            child: const Text('Send'),
          ),
        ],
      ),
    ).then((_) {
      titleCtrl.dispose();
      contentCtrl.dispose();
      categoryCtrl.dispose();
      accountIdCtrl.dispose();
      notesCtrl.dispose();
    });
  }

  @override
  void dispose() {
    _client.disconnect();
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
            if (_userStatuses.isNotEmpty)
              Text(_getStatusSummary(), style: const TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long),
            onPressed: _sendTransactionData,
            tooltip: 'Send Transaction Data',
          ),
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.people),
              onPressed: () => Scaffold.of(context).openEndDrawer(),
              tooltip: 'Room Members',
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              _client.disconnect();
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
      endDrawer: Drawer(
        child: Column(
          children: [
            const DrawerHeader(child: Center(child: Text("Room Members"))),
            Expanded(
              child: ListView.builder(
                itemCount: _userStatuses.length,
                itemBuilder: (context, index) {
                  final user = _userStatuses.values.elementAt(index);
                  final isMe = user.userId == widget.userId;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: user.isOnline ? Colors.green : Colors.grey,
                      radius: 5,
                    ),
                    title: Text(isMe ? '${user.username} (You)' : user.username),
                    subtitle: Text(
                      user.isOnline
                          ? 'Online'
                          : (user.lastSeen != null
                                ? 'Last seen: ${_formatLastSeen(user.lastSeen!)}'
                                : 'Offline'),
                      style: TextStyle(
                        fontSize: 12,
                        color: user.isOnline ? Colors.green : Colors.grey,
                      ),
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
            child: ListView.builder(
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final userId = msg['user_id'] as String? ?? 'unknown';
                final username = msg['username'] as String? ?? 'Unknown';
                final type = msg['type'] as String? ?? 'text';
                final content = msg['content'] as String? ?? '';
                final title = msg['title'] as String?;
                final payload = msg['payload'] as Map<String, dynamic>?;
                final createdAtStr = msg['created_at'] as String?;
                final createdAt = createdAtStr != null ? DateTime.tryParse(createdAtStr) : null;

                final isMe = userId == widget.userId;
                final isSystem = userId == 'system';

                return ListTile(
                  title: Align(
                    alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
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
                              Text(
                                isMe ? 'You' : username,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
                              ),
                              if (type != 'text') ...[
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.black12,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    type.toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (title != null)
                            Text(
                              title,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          Text(content),
                          if (payload != null)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.white54,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                payload.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
                                style: const TextStyle(fontSize: 9, fontStyle: FontStyle.italic),
                              ),
                            ),
                          if (createdAt != null)
                            Text(
                              _formatTime(createdAt),
                              style: const TextStyle(fontSize: 8, color: Colors.black54),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Message Input
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(labelText: 'Message'),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(icon: const Icon(Icons.send), onPressed: _sendMessage),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getStatusSummary() {
    final onlineCount = _userStatuses.values.where((u) => u.isOnline).length;
    final totalCount = _userStatuses.length;
    return '$onlineCount / $totalCount Online';
  }

  String _formatLastSeen(DateTime lastSeen) {
    final diff = DateTime.now().difference(lastSeen);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
