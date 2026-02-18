import 'package:dartz/dartz.dart';
import '../entities/room.dart';
import '../entities/message.dart';
import '../entities/user.dart';
import '../../core/errors/failures.dart';

abstract class ChatRepository {
  Future<Either<Failure, Room>> createRoom(String name, String type);
  Future<Either<Failure, List<Room>>> getRooms();
  Future<Either<Failure, List<Message>>> getMessages(
    String roomId, {
    int limit = 50,
    int offset = 0,
    String? userId,
  });
  Future<Either<Failure, List<User>>> getRoomMembers(String roomId);
  Future<Either<Failure, void>> joinRoom(String roomId);
  Stream<Message> get messageStream;
}
