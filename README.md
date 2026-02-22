# Flutter Chat SDK

Flutter/Dart package for integrating real-time chat into your app using the `backend-node` server.

## Installation

```yaml
# pubspec.yaml
dependencies:
  flutter_chat_sdk:
    path: ./flutter_chat_sdk   # adjust path as needed
```

```bash
flutter pub get
```

## Setup

Initialize once at app startup (e.g. `main.dart`):

```dart
import 'package:flutter_chat_sdk/flutter_chat_sdk.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await ChatClient().init(
    wsUrl:  'http://localhost:3000',
    apiUrl: 'http://localhost:3000',
  );

  runApp(MyApp());
}
```

`init()` restores a persisted session automatically. Pass `userId`, `username`, and `token` to `init()` to connect immediately, or call `connect()` separately after obtaining a JWT.

## Authentication

```dart
// Connect with a JWT obtained from your auth service
await ChatClient().connect(
  userId:   'user_id_123',
  username: 'Alice',
  token:    '<jwt>',
);

// Disconnect and clear session
await ChatClient().disconnect();
```

The token is persisted to `flutter_secure_storage` and restored on next `init()`.

## Rooms

```dart
ChatClient().joinRoom('room_abc');
ChatClient().leaveRoom('room_abc');

// Presence (tracks who is viewing a room)
ChatClient().joinPresence('room_abc', {'user_id': 'u1', 'username': 'Alice'});
ChatClient().leavePresence('room_abc');
```

## Sending Messages

Messages are sent via `HTTP POST /messages` (not via socket), which ensures cross-instance delivery through the Redis adapter. The client auto-generates the `id` and `created_at`.

```dart
await ChatClient().sendMessage({
  'room_id': 'room_abc',
  'event':   'message',
  'content': 'Hello!',
});
```

If the network is unavailable, messages are queued automatically and flushed on reconnect. Pass `allowOfflineQueue: false` to throw immediately instead.

## Unsend & Read Receipts

```dart
// Soft-delete a message (owner only — enforced server-side via JWT)
await ChatClient().unsendMessage(messageId: '<id>', roomId: 'room_abc');

// Mark a message as read (call when message enters viewport)
ChatClient().markMessageRead(messageId: '<id>', roomId: 'room_abc');
```

## Typing Indicators

```dart
// Call on every keystroke — debounced internally (500 ms default)
ChatClient().startTyping('room_abc');

// Call when message is sent or input cleared
ChatClient().stopTyping('room_abc');
```

The server also applies an 8-second auto-stop server-side in case the client disconnects unexpectedly.

## Message History

```dart
// Fetch paginated history (newest-first cursor pagination)
final messages = await ChatClient().getRoomHistory(
  roomId: 'room_abc',
  limit:  50,
  before: '2024-01-01T00:00:00.000Z',  // optional ISO timestamp cursor
);
```

## Streams

| Stream | Type | Description |
|---|---|---|
| `messageStream` | `Stream<dynamic>` | Incoming `message` events |
| `presenceStream` | `Stream<PresenceEvent>` | Presence join/leave/sync |
| `typingStream` | `Stream<TypingEvent>` | Typing start/stop from other users |
| `unsendStream` | `Stream<UnsendEvent>` | Message unsend notifications |
| `readReceiptStream` | `Stream<ReadReceiptEvent>` | Read receipt notifications |
| `userStream` | `Stream<User?>` | Current user (null = disconnected) |
| `connectionStream` | `Stream<bool>` | Socket connected/disconnected |

```dart
ChatClient().messageStream.listen((msg) {
  print('New message: $msg');
});

ChatClient().typingStream.listen((event) {
  print('${event.username} ${event.isTyping ? "started" : "stopped"} typing in ${event.roomId}');
});

ChatClient().presenceStream.listen((event) {
  // event.type: 'join' | 'leave' | 'sync'
  print('Presence ${event.type}: ${event.members}');
});
```

## Custom Events

```dart
ChatClient().on('my_event', (data) => print(data));
ChatClient().off('my_event');
```

## Domain Entities

| Entity | Key Fields |
|---|---|
| `User` | `id`, `username`, `isOnline` |
| `PresenceEvent` | `type` (join/leave/sync), `members` |
| `TypingEvent` | `userId`, `username`, `roomId`, `isTyping` |
| `UnsendEvent` | `messageId`, `roomId`, `unsentBy`, `unsentAt` |
| `ReadReceiptEvent` | `messageId`, `roomId`, `readBy` |

## Running the Example App

```bash
cd example
flutter run
```
