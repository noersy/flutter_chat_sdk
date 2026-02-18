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
      title: 'Chat SDK Example',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const ChatTestPage(),
    );
  }
}

class ChatTestPage extends StatefulWidget {
  const ChatTestPage({super.key});

  @override
  State<ChatTestPage> createState() => _ChatTestPageState();
}

class _ChatTestPageState extends State<ChatTestPage> {
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _roomNameController = TextEditingController();
  final _messageController = TextEditingController();

  final ChatClient _client = ChatClient();
  bool _isLoggedIn = false;
  String _status = 'Disconnected';
  List<Room> _rooms = [];
  List<Message> _messages = [];
  List<User> _roomMembers = [];
  String? _currentRoomId;

  StreamSubscription<UserStatusEvent>? _statusSubscription;
  StreamSubscription<MessageStatusEvent>? _messageStatusSubscription;

  @override
  void initState() {
    super.initState();
    _initClient();
  }

  Future<void> _initClient() async {
    await _client.init(baseUrl: 'http://localhost:8080/api', wsUrl: 'ws://localhost:8080/ws');

    _client.userStream.listen((user) {
      if (mounted) {
        setState(() {
          _isLoggedIn = user != null;
          _status = _isLoggedIn ? 'Logged in as ${user!.username}' : 'Logged out';
        });
        if (_isLoggedIn) {
          _loadRooms();
          _listenStatusEvents();
        }
      }
    });

    _client.messageStream.listen((message) {
      if (mounted && message.roomId == _currentRoomId) {
        setState(() {
          _messages.add(message);
        });

        // If message is from someone else and we are in the room, mark as read
        if (message.userId != _client.currentUser?.id) {
          print('Client: Auto-marking message as read in room ${message.roomId}');
          _client.markAsRead(message.roomId);
        } else {
          print('Client: Message is from me, skipping auto-read');
        }
      }
    });

    // Listen for message status updates
    _messageStatusSubscription = _client.statusUpdateStream.listen((event) {
      print(
        'Client received statusUpdateStream event: type=${event.runtimeType} updates=${event.updates.length} roomId=${event.roomId}',
      );
      if (!mounted || event.roomId != _currentRoomId) {
        print(
          'Client: Ignoring status update (mounted=$mounted, currentRoom=$_currentRoomId, eventRoom=${event.roomId})',
        );
        return;
      }
      setState(() {
        for (final update in event.updates) {
          final idx = _messages.indexWhere((m) => m.id == update.messageId);
          if (idx != -1) {
            final currentStatus = _messages[idx].status;
            final newStatus = update.status;

            // Prevent regression: read > delivered > sent
            if (currentStatus == 'read') continue;
            if (currentStatus == 'delivered' && newStatus == 'sent') continue;

            print(
              'Client: Updating message ${update.messageId} status to $newStatus (from $currentStatus)',
            );
            _messages[idx] = _messages[idx].copyWithStatus(newStatus);
          } else {
            print('Client: Message ${update.messageId} not found in local list');
          }
        }
      });
    });
  }

  void _listenStatusEvents() {
    _statusSubscription?.cancel();
    _statusSubscription = _client.userStatusStream.listen((event) {
      if (!mounted) return;

      // Update room member list in real-time if we're in a room
      if (_currentRoomId != null) {
        setState(() {
          _roomMembers = _roomMembers.map((m) {
            if (m.id == event.userId) {
              return User(
                id: m.id,
                username: m.username,
                email: m.email,
                isOnline: event.isOnline,
                lastSeen: event.isOnline ? null : DateTime.now(),
                createdAt: m.createdAt,
                updatedAt: m.updatedAt,
              );
            }
            return m;
          }).toList();
        });
      }

      // Show snackbar notification
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.circle, size: 10, color: event.isOnline ? Colors.green : Colors.grey),
              const SizedBox(width: 8),
              Text('${event.username} is now ${event.isOnline ? "online" : "offline"}'),
            ],
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    });
  }

  Future<void> _loadRooms() async {
    try {
      final rooms = await _client.getMyRooms();
      setState(() {
        _rooms = rooms;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load rooms: $e')));
    }
  }

  Future<void> _loadRoomMembers(String roomId) async {
    try {
      final members = await _client.getRoomMembers(roomId);
      if (mounted) {
        setState(() {
          _roomMembers = members;
        });
      }
    } catch (e) {
      debugPrint('Failed to load room members: $e');
    }
  }

  Future<void> _login() async {
    try {
      final credential = _emailController.text.isNotEmpty
          ? _emailController.text
          : _usernameController.text;
      await _client.login(credential, _passwordController.text);
    } catch (e) {
      _showError('Login failed: $e');
    }
  }

  Future<void> _register() async {
    try {
      await _client.register(
        _usernameController.text,
        _emailController.text,
        _passwordController.text,
      );
    } catch (e) {
      _showError('Register failed: $e');
    }
  }

  Future<void> _createRoom() async {
    try {
      if (_roomNameController.text.isEmpty) return;
      await _client.createRoom(_roomNameController.text, 'group');
      if (!mounted) return;
      _roomNameController.clear();
      _loadRooms();
    } catch (e) {
      _showError('Create room failed: $e');
    }
  }

  Future<void> _joinRoom(String roomId) async {
    final usernameController = TextEditingController();
    final username = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add User to Room'),
        content: TextField(
          controller: usernameController,
          decoration: const InputDecoration(
            labelText: 'Username',
            hintText: 'Enter username to add',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, usernameController.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (username == null || username.isEmpty) return;

    try {
      await _client.addUserToRoomByUsername(roomId, username);
      _showSuccess('User "$username" added to room');
      _loadRooms();
      if (_currentRoomId == roomId) {
        _loadRoomMembers(roomId);
      }
    } catch (e) {
      _showError('Add user failed: $e');
    }
  }

  Future<void> _enterRoom(String roomId) async {
    setState(() {
      _currentRoomId = roomId;
      _messages = [];
      _roomMembers = [];
    });
    try {
      final history = await _client.getMessages(roomId);
      setState(() {
        _messages = List<Message>.from(history);
      });
      _client.joinRoomWS(roomId);
      _client.markAsRead(roomId); // Mark all messages as read
      _loadRoomMembers(roomId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Get messages failed: $e')));
    }
  }

  void _sendMessage() {
    if (_currentRoomId == null || _messageController.text.isEmpty) return;
    _client.sendMessage(_currentRoomId!, _messageController.text);
    _messageController.clear();
  }

  void _showError(String message) {
    if (!mounted) return;
    final cleanMessage = message.replaceAll('Exception: ', '');
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(cleanMessage), backgroundColor: Colors.red));
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.green));
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _messageStatusSubscription?.cancel();
    super.dispose();
  }

  // ─── Build Methods ──────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_isLoggedIn) return _buildLoginScreen();
    if (_currentRoomId != null) return _buildChatRoomScreen();
    return _buildRoomListScreen();
  }

  Widget _buildLoginScreen() {
    return Scaffold(
      appBar: AppBar(title: Text(_status)),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(labelText: 'Username (min 3 chars)'),
            ),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email (Optional)'),
            ),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(onPressed: _login, child: const Text('Login')),
                ElevatedButton(onPressed: _register, child: const Text('Register')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomListScreen() {
    return Scaffold(
      appBar: AppBar(
        title: Text(_status),
        actions: [IconButton(icon: const Icon(Icons.logout), onPressed: () => _client.logout())],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _roomNameController,
                    decoration: const InputDecoration(labelText: 'Room Name'),
                  ),
                ),
                IconButton(icon: const Icon(Icons.add), onPressed: _createRoom),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _rooms.length,
              itemBuilder: (context, index) {
                final room = _rooms[index];
                return ListTile(
                  title: Text(room.name),
                  subtitle: Text(room.type),
                  onTap: () => _enterRoom(room.id),
                  trailing: IconButton(
                    icon: const Icon(Icons.group_add),
                    onPressed: () => _joinRoom(room.id),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatRoomScreen() {
    // Find room name
    final roomName =
        _rooms.where((r) => r.id == _currentRoomId).map((r) => r.name).firstOrNull ?? 'Chat Room';

    return Scaffold(
      appBar: AppBar(
        title: Text(roomName),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            setState(() {
              _currentRoomId = null;
              _roomMembers = [];
            });
            _loadRooms();
          },
        ),
        actions: [IconButton(icon: const Icon(Icons.people), onPressed: () => _showMembersSheet())],
      ),
      body: Column(
        // Online members bar
        children: [
          if (_roomMembers.isNotEmpty)
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
              ),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _roomMembers.length,
                itemBuilder: (context, index) {
                  final member = _roomMembers[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    child: Chip(
                      avatar: Stack(
                        children: [
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: Colors.blue[200],
                            child: Text(
                              member.username[0].toUpperCase(),
                              style: const TextStyle(fontSize: 10, color: Colors.white),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: member.isOnline ? Colors.green : Colors.grey,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 1),
                              ),
                            ),
                          ),
                        ],
                      ),
                      label: Text(
                        member.username,
                        style: TextStyle(
                          fontSize: 12,
                          color: member.isOnline ? Colors.black : Colors.grey,
                        ),
                      ),
                      backgroundColor: Colors.white,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  );
                },
              ),
            ),
          // Messages
          Expanded(
            child: ListView.builder(
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isMe = msg.userId == _client.currentUser?.id;
                return ListTile(
                  title: Align(
                    alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isMe ? Colors.blue[100] : Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: isMe
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        children: [
                          Text(
                            msg.username,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
                          ),
                          Text(msg.content),
                          if (isMe)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: _buildStatusIcon(msg.status),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // Message input
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(labelText: 'Message'),
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

  void _showMembersSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            // Listen for status updates to refresh the sheet
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Text(
                        'Room Members',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      Text(
                        '${_roomMembers.where((m) => m.isOnline).length} online',
                        style: const TextStyle(color: Colors.green, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _roomMembers.length,
                    itemBuilder: (context, index) {
                      final member = _roomMembers[index];
                      final isMe = member.id == _client.currentUser?.id;
                      return ListTile(
                        leading: Stack(
                          children: [
                            CircleAvatar(
                              backgroundColor: Colors.blue[200],
                              child: Text(
                                member.username[0].toUpperCase(),
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: member.isOnline ? Colors.green : Colors.grey,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                              ),
                            ),
                          ],
                        ),
                        title: Text(
                          '${member.username}${isMe ? " (You)" : ""}',
                          style: TextStyle(fontWeight: isMe ? FontWeight.bold : FontWeight.normal),
                        ),
                        subtitle: Text(
                          member.isOnline
                              ? 'Online'
                              : member.lastSeen != null
                              ? 'Last seen ${_formatLastSeen(member.lastSeen!)}'
                              : 'Offline',
                          style: TextStyle(
                            color: member.isOnline ? Colors.green : Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.person_add),
                          onPressed: () => _joinRoom(_currentRoomId!),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildStatusIcon(String status) {
    switch (status) {
      case 'read':
        return const Row(
          mainAxisSize: MainAxisSize.min,
          children: [Icon(Icons.done_all, size: 16, color: Colors.blue)],
        );
      case 'delivered':
        return const Row(
          mainAxisSize: MainAxisSize.min,
          children: [Icon(Icons.done_all, size: 16, color: Colors.grey)],
        );
      default: // sent
        return const Row(
          mainAxisSize: MainAxisSize.min,
          children: [Icon(Icons.check, size: 16, color: Colors.grey)],
        );
    }
  }

  String _formatLastSeen(DateTime lastSeen) {
    final diff = DateTime.now().difference(lastSeen);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
