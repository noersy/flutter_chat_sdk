import 'package:equatable/equatable.dart';

class Room extends Equatable {
  final String id;
  final String name;
  final String type;
  final DateTime createdAt;

  const Room({required this.id, required this.name, required this.type, required this.createdAt});

  @override
  List<Object?> get props => [id, name, type, createdAt];
}
