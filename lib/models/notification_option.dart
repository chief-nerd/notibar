import 'package:equatable/equatable.dart';

/// A single tray menu entry: ties an account to a specific display metric.
/// Multiple options can reference the same account (e.g., "Unread" and "Flagged").
class NotificationOption extends Equatable {
  final String id;
  final String accountId;
  final String label;

  /// Metric ID as defined by the plugin's MetricDefinition.id
  /// (e.g. 'unread', 'flagged', 'assignedPRs').
  final String metric;
  final bool enabled;
  final int sortOrder;
  final Map<String, String> config;

  const NotificationOption({
    required this.id,
    required this.accountId,
    required this.label,
    this.metric = 'unread',
    this.enabled = true,
    this.sortOrder = 0,
    this.config = const {},
  });

  NotificationOption copyWith({
    String? id,
    String? accountId,
    String? label,
    String? metric,
    bool? enabled,
    int? sortOrder,
    Map<String, String>? config,
  }) {
    return NotificationOption(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      label: label ?? this.label,
      metric: metric ?? this.metric,
      enabled: enabled ?? this.enabled,
      sortOrder: sortOrder ?? this.sortOrder,
      config: config ?? this.config,
    );
  }

  factory NotificationOption.fromJson(Map<String, dynamic> json) {
    return NotificationOption(
      id: json['id'] as String,
      accountId: json['accountId'] as String,
      label: json['label'] as String,
      metric: json['metric'] as String? ?? 'unread',
      enabled: json['enabled'] as bool? ?? true,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      config:
          (json['config'] as Map<String, dynamic>?)?.map(
            (k, e) => MapEntry(k, e as String),
          ) ??
          const {},
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'accountId': accountId,
    'label': label,
    'metric': metric,
    'enabled': enabled,
    'sortOrder': sortOrder,
    'config': config,
  };

  @override
  List<Object?> get props => [
    id,
    accountId,
    label,
    metric,
    enabled,
    sortOrder,
    config,
  ];
}
