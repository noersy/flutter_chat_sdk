import 'package:equatable/equatable.dart';

class Room extends Equatable {
  final String id;
  final String name;
  final String type;
  final DateTime createdAt;

  const Room({required this.id, required this.name, required this.type, required this.createdAt});

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unnamed Room',
      type: json['type'] as String? ?? 'group',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'type': type, 'created_at': createdAt.toIso8601String()};
  }

  @override
  List<Object?> get props => [id, name, type, createdAt];
}
