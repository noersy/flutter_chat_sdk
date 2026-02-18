import 'package:json_annotation/json_annotation.dart';
import '../../domain/entities/message.dart';

part 'message_model.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake)
class MessageModel extends Message {
  const MessageModel({
    required super.id,
    required super.roomId,
    required super.userId,
    required super.username,
    required super.content,
    required super.type,
    super.status = 'sent',
    required super.createdAt,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) => _$MessageModelFromJson(json);

  Map<String, dynamic> toJson() => _$MessageModelToJson(this);
}
