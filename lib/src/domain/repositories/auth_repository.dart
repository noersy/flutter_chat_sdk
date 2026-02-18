import 'package:dartz/dartz.dart';
import '../entities/user.dart';
import '../../core/errors/failures.dart';

abstract class AuthRepository {
  Future<Either<Failure, User>> login(String emailOrUsername, String password);
  Future<Either<Failure, User>> register(String username, String email, String password);
  Future<Either<Failure, User>> getUserByUsername(String username);
}
