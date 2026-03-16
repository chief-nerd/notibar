import '../models/account.dart';
import '../models/notification_item.dart';

abstract class NotibarPlugin {
  ServiceType get serviceType;
  Future<NotificationSummary> fetchNotifications(Account account);

  /// Decodes raw JSON from the service into a NotificationSummary.
  /// Useful for testing and decoupled parsing.
  NotificationSummary parseSummary(
    Map<String, dynamic> json, {
    int? unreadCount,
    int? flaggedCount,
    int? mentionCount,
    int? assignedIssuesCount,
    int? assignedPRsCount,
    int? reviewRequestsCount,
  });
}

class NotificationSummary {
  final int unreadCount;
  final int flaggedCount;
  final int mentionCount;
  final int assignedIssuesCount;
  final int assignedPRsCount;
  final int reviewRequestsCount;
  final List<NotificationItem> items;
  final PluginError? error;

  /// If the plugin refreshed the auth token, this contains the updated account
  /// that should be persisted.
  final Account? refreshedAccount;

  const NotificationSummary({
    this.unreadCount = 0,
    this.flaggedCount = 0,
    this.mentionCount = 0,
    this.assignedIssuesCount = 0,
    this.assignedPRsCount = 0,
    this.reviewRequestsCount = 0,
    required this.items,
    this.error,
    this.refreshedAccount,
  });

  factory NotificationSummary.withError(PluginError error) =>
      NotificationSummary(items: const [], error: error);
}

enum PluginErrorType { authentication, network, unknown }

class PluginError {
  final PluginErrorType type;
  final String message;

  PluginError({required this.type, required this.message});

  @override
  String toString() => '[$type] $message';
}
