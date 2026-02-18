# Flutter Chat SDK

A comprehensive Flutter package for integrating real-time chat capabilities into your application using Socket.IO.

## Features

- **Real-time Messaging**: Send and receive messages instantly.
- **Room Management**: Join and leave chat rooms for group or private conversations.
- **User Status**: Track online/offline status of users.
- **Message Status**: Support for message delivery status (sent, delivered, read).
- **Event Handling**: Listen to various events like room changes and user status updates.
- **Secure Storage**: Automatically manages user session persistence.

## Installation

Add the following to your `pubspec.yaml` file:

```yaml
dependencies:
  flutter_chat_sdk:
    path: ./flutter_chat_sdk  # Adjust path as necessary relative to your project
```

## Usage

### 1. Initialization

Initialize the SDK with your WebSocket server URL. This should be done early in your application lifecycle (e.g., in `main.dart`).

```dart
import 'package:flutter_chat_sdk/flutter_chat_sdk.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await ChatClient().init(
    wsUrl: 'http://localhost:3000', // Replace with your Socket.IO server URL
  );
  
  runApp(MyApp());
}
```

### 2. Authentication

Connect to the chat server with a user's identity. If a session was previously saved, the SDK can attempt to restore it automatically during initialization.

```dart
// Connect with user details
await ChatClient().connect('user_id_123', 'John Doe');

// Disconnect
await ChatClient().disconnect();
```

### 3. Room Management

Join or leave specific rooms to listen for messages.

```dart
// Join a room
ChatClient().joinRoom('room_abc_123');

// Leave a room
ChatClient().leaveRoom('room_abc_123');
```

### 4. Sending Messages

Send text messages or messages with attachments/payloads.

```dart
ChatClient().sendMessage(
  'room_abc_123',
  'Hello, world!',
  type: 'text', // Optional, default is 'text'
  title: 'Greeting', // Optional
  payload: {'custom': 'data'}, // Optional
  attachmentUrls: ['https://example.com/image.png'], // Optional
);
```

### 5. Listening to Events

The SDK exposes several streams to handle real-time updates.

#### Incoming Messages

```dart
ChatClient().messageStream.listen((Message message) {
  print('New message in ${message.roomId}: ${message.content}');
});
```

#### User Status Updates

Subscribe to a user's status to receive updates.

```dart
// Subscribe to track a user
ChatClient().subscribeStatus('target_user_id');

// Listen for status changes
ChatClient().userStatusStream.listen((UserStatusEvent event) {
  print('${event.username} is now ${event.isOnline ? 'Online' : 'Offline'}');
});
```

#### Room Events

Track when users join or leave a room.

```dart
ChatClient().roomEventStream.listen((RoomEvent event) {
  if (event.type == 'user_joined') {
    print('${event.username} joined room ${event.roomId}');
  } else if (event.type == 'user_left') {
    print('${event.username} left room ${event.roomId}');
  }
});
```

#### Message Status Updates

Track the lifecycle of a message (e.g., when it is read).

```dart
ChatClient().statusUpdateStream.listen((MessageStatusEvent event) {
  for (var update in event.updates) {
    print('Message ${update.messageId} status: ${update.status}');
  }
});
```

## Domain Entities

- **User**: Represents a chat user with properties like `id`, `username`, `email`, `isOnline`, etc.
- **Message**: Represents a chat message with `id`, `roomId`, `content`, `type`, `status`, `createdAt`, etc.
- **Room**: Represents a chat room.

## Contributing

Contributions are welcome! Please submit a pull request or open an issue for any bugs or feature requests.
