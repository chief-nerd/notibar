import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'account.g.dart';

enum ServiceType { microsoft, github, jira, slack, teams, frappe, mattermost, custom }

@JsonSerializable()
class Account extends Equatable {
  final String id;
  final String name;
  final ServiceType serviceType;
  final String? endpoint;
  final String? apiKey;
  final Map<String, String> config;

  final DateTime? lastRefreshTime;

  @DurationConverter()
  final Duration pollingInterval;

  const Account({
    required this.id,
    required this.name,
    required this.serviceType,
    this.endpoint,
    this.apiKey,
    this.config = const {},
    this.lastRefreshTime,
    this.pollingInterval = const Duration(minutes: 5),
  });

  factory Account.fromJson(Map<String, dynamic> json) =>
      _$AccountFromJson(json);
  Map<String, dynamic> toJson() => _$AccountToJson(this);

  Account copyWith({
    String? id,
    String? name,
    ServiceType? serviceType,
    String? endpoint,
    String? apiKey,
    Map<String, String>? config,
    DateTime? lastRefreshTime,
    Duration? pollingInterval,
  }) {
    return Account(
      id: id ?? this.id,
      name: name ?? this.name,
      serviceType: serviceType ?? this.serviceType,
      endpoint: endpoint ?? this.endpoint,
      apiKey: apiKey ?? this.apiKey,
      config: config ?? this.config,
      lastRefreshTime: lastRefreshTime ?? this.lastRefreshTime,
      pollingInterval: pollingInterval ?? this.pollingInterval,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    serviceType,
    endpoint,
    apiKey,
    config,
    lastRefreshTime,
    pollingInterval,
  ];
}

class DurationConverter implements JsonConverter<Duration, int> {
  const DurationConverter();

  @override
  Duration fromJson(int json) => Duration(seconds: json);

  @override
  int toJson(Duration object) => object.inSeconds;
}
