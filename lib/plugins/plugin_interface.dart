import '../models/account.dart';
import '../models/notification_item.dart';

abstract class NotibarPlugin {
  ServiceType get serviceType;
  Future<NotificationSummary> fetchNotifications(Account account);
}

class NotificationSummary {
  final int unreadCount;
  final int flaggedCount;
  final List<NotificationItem> items;
  final PluginError? error;

  NotificationSummary({
    required this.unreadCount,
    required this.flaggedCount,
    required this.items,
    this.error,
  });

  factory NotificationSummary.withError(PluginError error) {
    return NotificationSummary(
      unreadCount: 0,
      flaggedCount: 0,
      items: [],
      error: error,
    );
  }
}

enum PluginErrorType {
  authentication,
  network,
  unknown,
}

class PluginError {
  final PluginErrorType type;
  final String message;

  PluginError({required this.type, required this.message});

  @override
  String toString() => '[$type] $message';
}
