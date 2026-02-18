# Flutter Chat SDK

A comprehensive Flutter SDK for the WebSocket Chat application. This SDK handles REST API communication for user/room management and WebSocket connections for real-time messaging, status updates, and online presence.

## Features

- **Authentication**: Register and Login users.
- **Room Management**: Create, list, join, and manage chat rooms.
- **Real-time Messaging**: Send and receive messages instantly via WebSockets.
- **Message History**: Fetch paginated message history with automatic delivery status updates.
- **Read Receipts**: Real-time updates for message delivery (server received) and read status (recipient opened).
- **User Presence**: Monitor online/offline status of users.
- **Type-Safe**: Fully typed domain entities (User, Room, Message).

## Installation

Add this package to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_chat_sdk:
    path: /path/to/flutter_chat_sdk
```

## Usage

### 1. Initialization

Initialize the `ChatClient` singleton with your backend Base URL and WebSocket URL.

```dart
import 'package:flutter_chat_sdk/flutter_chat_sdk.dart';

void main() async {
  final client = ChatClient();
  
  await client.init(
    baseUrl: 'http://localhost:8080', 
    wsUrl: 'ws://localhost:8080/ws'
  );
  
  runApp(MyApp());
}
```

### 2. Authentication

Register a new user or login with existing credentials. The client automatically manages the session state.

```dart
final client = ChatClient();

// Register
try {
  final user = await client.register('username', 'email@example.com', 'password123');
  print('Registered as: ${user.username}');
} catch (e) {
  print('Registration failed: $e');
}

// Login
try {
  final user = await client.login('email@example.com', 'password123');
  print('Logged in as: ${user.id}');
} catch (e) {
  print('Login failed: $e');
}

// Logout
await client.logout();
```

### 3. Room Management

Create rooms, list your rooms, and manage members.

```dart
// Create a room
final room = await client.createRoom('My Cool Group', 'group');

// List my joined rooms
final rooms = await client.getMyRooms();

// Get room members (includes online status)
final members = await client.getRoomMembers(room.id);

// Add a user to a room by username
await client.addUserToRoomByUsername(room.id, 'friend_username');
```

### 4. Real-time Messaging

To send and receive messages, you must first "join" the room via WebSocket.

```dart
// 1. Join the room via WebSocket to subscribe to events
client.joinRoomWS(roomId);

// 2. Listen for incoming messages
client.messageStream.listen((message) {
  print('[${message.senderId}] ${message.content}');
});

// 3. Send a message
client.sendMessage(roomId, 'Hello everyone!');
```

### 5. Message History & Status

Fetch past messages and handle read receipts.

```dart
// Get message history (paginated)
// Validates 'sent' messages from others and auto-sends 'delivered' receipts
final history = await client.getMessages(roomId, limit: 50, offset: 0);

// Mark a room as read (sends 'read' receipts to senders)
client.markAsRead(roomId);
```

### 6. Event Listeners

Listen to real-time status changes.

```dart
// Listen for User Online/Offline events
client.userStatusStream.listen((event) {
  print('User ${event.userId} is now ${event.isOnline ? 'Online' : 'Offline'}');
});

// Listen for Message Status updates (delivered/read)
client.statusUpdateStream.listen((event) {
  print('Message ${event.messageId} was ${event.status} by ${event.userId}');
});
```

## Architecture

The SDK follows Clean Architecture principles:

- **Presentation**: `ChatClient` (Facade pattern)
- **Domain**: Entities (`User`, `Room`, `Message`) and fail-safe logic.
- **Data**: Repositories handling API and WebSocket data sources.
- **Core**: Networking and WebSocket management.

## Error Handling

All methods throw exceptions on failure. It is recommended to wrap calls in `try-catch` blocks.

```dart
try {
  await client.login('user', 'pass');
} catch (e) {
  // Handle login error (e.g. invalid credentials)
}
```
