import 'dart:async';
import 'dart:developer';
import 'package:dartz/dartz.dart';
import '../../core/api_client.dart';
import '../../core/websocket_service.dart';
import '../../core/errors/failures.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/room.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/chat_repository.dart';
import '../models/message_model.dart';
import '../models/room_model.dart';
import '../models/user_model.dart';

class ChatRepositoryImpl implements ChatRepository {
  final ApiClient apiClient;
  final WebSocketService webSocketService;

  ChatRepositoryImpl({required this.apiClient, required this.webSocketService});

  @override
  Future<Either<Failure, Room>> createRoom(String name, String type) async {
    try {
      // Note: creator_id will be handled by the SDK wrapper passing it or backend session
      // For now assuming the SDK wrapper injects it into query params or header if needed
      // But based on analysis, it needs to be in query param.
      // This repo method might need userID injected, or the ApiClient handles auth.
      // Let's assume the wrapper passing it.
      // Wait, repository shouldn't know about "currentUser".
      // We'll update the interface to accept creatorId or handle it in the UseCase/Presentation.
      // For now, let's keep it simple and assume standard POST.
      // Actually, backend needs `creator_id` query param.
      // We will handle this in the Presentation layer to pass it, or update this method.
      // Let's update this method signature later if needed.
      // For now, let's pass it in the body and let ApiClient intercept or just append to URL.

      final response = await apiClient.post('/rooms', body: {'name': name, 'type': type});
      return Right(RoomModel.fromJson(response));
    } catch (e) {
      if (e is Failure) return Left(e);
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<Message>>> getMessages(
    String roomId, {
    int limit = 50,
    int offset = 0,
    String? userId,
  }) async {
    try {
      var url = '/rooms/$roomId/messages?limit=$limit&offset=$offset';
      if (userId != null) {
        url += '&user_id=$userId';
      }
      final response = await apiClient.get(url);
      final List<dynamic> list = response['messages'];
      return Right(list.map((e) => MessageModel.fromJson(e)).toList());
    } catch (e) {
      if (e is Failure) return Left(e);
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<User>>> getRoomMembers(String roomId) async {
    try {
      final response = await apiClient.get('/rooms/$roomId/members');
      final List<dynamic> list = response;
      return Right(list.map((e) => UserModel.fromJson(e)).toList());
    } catch (e) {
      if (e is Failure) return Left(e);
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<Room>>> getRooms() async {
    try {
      // This endpoint requires user_id.
      // We need to pass user_id to this method.
      // For now, let's assume we fetch all rooms or handle it later.
      // Backend: GET /api/users/{id}/rooms
      // We really need the UserID here.
      // Let's refactor the interface to accept userId for `getRooms`.
      return Left(const ValidationFailure("User ID required"));
    } catch (e) {
      if (e is Failure) return Left(e);
      return Left(ServerFailure(e.toString()));
    }
  }

  // Overloaded/Alternative method to match backend
  Future<Either<Failure, List<Room>>> getUserRooms(String userId) async {
    try {
      final response = await apiClient.get('/users/$userId/rooms');
      final List<dynamic> list = response;
      return Right(list.map((e) => RoomModel.fromJson(e)).toList());
    } catch (e) {
      if (e is Failure) return Left(e);
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> joinRoom(String roomId) async {
    // Backend: POST /api/rooms/{id}/members
    // Needs user_id in body
    return Left(const ValidationFailure("User ID required"));
  }

  // Overloaded method
  Future<Either<Failure, void>> addMember(String roomId, String userId) async {
    try {
      await apiClient.post('/rooms/$roomId/members', body: {'user_id': userId});
      return Right(null);
    } catch (e) {
      if (e is Failure) return Left(e);
      return Left(ServerFailure(e.toString()));
    }
  }

  // Create Room with Creator ID
  Future<Either<Failure, Room>> createRoomWithCreator(
    String name,
    String type,
    String creatorId,
  ) async {
    try {
      // Backend hack: creator_id in query param
      final response = await apiClient.post(
        '/rooms?creator_id=$creatorId',
        body: {'name': name, 'type': type},
      );
      log('ChatRepository: received response: $response');
      try {
        return Right(RoomModel.fromJson(response));
      } catch (e, stack) {
        log('ChatRepository parsing error: $e');
        log(stack.toString());
        rethrow;
      }
    } catch (e) {
      log(e.toString());
      if (e is Failure) return Left(e);
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Stream<Message> get messageStream => webSocketService.messageStream;
}
