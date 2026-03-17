// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'account.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

/// Handles backward compatibility: 'outlook' → ServiceType.microsoft.
ServiceType _decodeServiceType(String value) {
  if (value == 'outlook') return ServiceType.microsoft;
  return $enumDecode(_$ServiceTypeEnumMap, value);
}

Account _$AccountFromJson(Map<String, dynamic> json) => Account(
  id: json['id'] as String,
  name: json['name'] as String,
  serviceType: _decodeServiceType(json['serviceType'] as String),
  endpoint: json['endpoint'] as String?,
  apiKey: json['apiKey'] as String?,
  config:
      (json['config'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, e as String),
      ) ??
      const {},
  lastRefreshTime:
      json['lastRefreshTime'] == null
          ? null
          : DateTime.parse(json['lastRefreshTime'] as String),
  pollingInterval:
      json['pollingInterval'] == null
          ? const Duration(minutes: 5)
          : const DurationConverter().fromJson(
            (json['pollingInterval'] as num).toInt(),
          ),
);

Map<String, dynamic> _$AccountToJson(Account instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'serviceType': _$ServiceTypeEnumMap[instance.serviceType]!,
  'endpoint': instance.endpoint,
  'apiKey': instance.apiKey,
  'config': instance.config,
  'lastRefreshTime': instance.lastRefreshTime?.toIso8601String(),
  'pollingInterval': const DurationConverter().toJson(instance.pollingInterval),
};

const _$ServiceTypeEnumMap = {
  ServiceType.microsoft: 'microsoft',
  ServiceType.github: 'github',
  ServiceType.jira: 'jira',
  ServiceType.slack: 'slack',
  ServiceType.teams: 'teams',
  ServiceType.frappe: 'frappe',
  ServiceType.mattermost: 'mattermost',
  ServiceType.custom: 'custom',
};
