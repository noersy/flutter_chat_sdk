import 'package:dartz/dartz.dart';
import '../../core/api_client.dart';
import '../../core/errors/failures.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../models/user_model.dart';

class AuthRepositoryImpl implements AuthRepository {
  final ApiClient apiClient;

  AuthRepositoryImpl({required this.apiClient});

  @override
  Future<Either<Failure, User>> login(String emailOrUsername, String password) async {
    try {
      final response = await apiClient.post(
        '/auth/login',
        body: {'email_or_username': emailOrUsername, 'password': password},
      );
      return Right(UserModel.fromJson(response));
    } catch (e) {
      if (e is Failure) return Left(e);
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, User>> register(String username, String email, String password) async {
    try {
      final response = await apiClient.post(
        '/users',
        body: {'username': username, 'email': email, 'password': password},
      );
      return Right(UserModel.fromJson(response));
    } catch (e) {
      if (e is Failure) return Left(e);
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, User>> getUserByUsername(String username) async {
    try {
      final response = await apiClient.get('/lookup/username/$username');
      return Right(UserModel.fromJson(response));
    } catch (e) {
      if (e is Failure) return Left(e);
      return Left(ServerFailure(e.toString()));
    }
  }
}
