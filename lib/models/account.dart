import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'account.g.dart';

enum ServiceType { outlook, custom }

@JsonSerializable()
class Account extends Equatable {
  final String id;
  final String name;
  final ServiceType serviceType;
  final String? endpoint;
  final String? apiKey;
  
  @DurationConverter()
  final Duration pollingInterval;

  const Account({
    required this.id,
    required this.name,
    required this.serviceType,
    this.endpoint,
    this.apiKey,
    this.pollingInterval = const Duration(minutes: 5),
  });

  factory Account.fromJson(Map<String, dynamic> json) => _$AccountFromJson(json);
  Map<String, dynamic> toJson() => _$AccountToJson(this);

  @override
  List<Object?> get props => [id, name, serviceType, endpoint, apiKey, pollingInterval];
}

class DurationConverter implements JsonConverter<Duration, int> {
  const DurationConverter();

  @override
  Duration fromJson(int json) => Duration(seconds: json);

  @override
  int toJson(Duration object) => object.inSeconds;
}
