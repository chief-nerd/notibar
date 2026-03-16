import 'package:equatable/equatable.dart';

/// What metric/view to show in the tray for a given account.
enum DisplayMetric { 
  unread, 
  flagged, 
  mentions, 
  assignedIssues, 
  assignedPRs, 
  reviewRequests,
  all 
}

/// A single tray menu entry: ties an account to a specific display metric.
/// Multiple options can reference the same account (e.g., "Unread" and "Flagged").
class NotificationOption extends Equatable {
  final String id;
  final String accountId;
  final String label;
  final DisplayMetric metric;
  final bool enabled;
  final int sortOrder;

  const NotificationOption({
    required this.id,
    required this.accountId,
    required this.label,
    this.metric = DisplayMetric.unread,
    this.enabled = true,
    this.sortOrder = 0,
  });

  NotificationOption copyWith({
    String? id,
    String? accountId,
    String? label,
    DisplayMetric? metric,
    bool? enabled,
    int? sortOrder,
  }) {
    return NotificationOption(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      label: label ?? this.label,
      metric: metric ?? this.metric,
      enabled: enabled ?? this.enabled,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  factory NotificationOption.fromJson(Map<String, dynamic> json) {
    return NotificationOption(
      id: json['id'] as String,
      accountId: json['accountId'] as String,
      label: json['label'] as String,
      metric: DisplayMetric.values.firstWhere(
        (e) => e.name == json['metric'],
        orElse: () => DisplayMetric.unread,
      ),
      enabled: json['enabled'] as bool? ?? true,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'accountId': accountId,
    'label': label,
    'metric': metric.name,
    'enabled': enabled,
    'sortOrder': sortOrder,
  };

  @override
  List<Object?> get props => [id, accountId, label, metric, enabled, sortOrder];
}
