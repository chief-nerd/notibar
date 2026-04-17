import 'package:flutter/widgets.dart';
import '../models/account.dart';
import '../models/notification_item.dart';
import '../services/multi_status_item_channel.dart';

// ── Metric definition ─────────────────────────────────────────────

/// Describes a single display metric that a plugin supports.
/// Carries all UI metadata so the tray and settings UI need no
/// plugin-specific knowledge.
class MetricDefinition {
  /// Unique ID stored in NotificationOption.metric (e.g. 'unread').
  final String id;

  /// Human-readable label (e.g. 'Unread', 'Review Requests').
  final String label;

  /// macOS SF Symbol name for the tray status item.
  final String sfSymbol;

  /// Material icon for the Flutter settings UI.
  final IconData materialIcon;

  /// Filters items from a summary for this metric's dropdown.
  /// The tray badge count is always derived from this filter's length,
  /// ensuring count and dropdown are always in sync.
  final List<NotificationItem> Function(
    NotificationSummary summary,
    Map<String, String> config,
  )
  filter;

  const MetricDefinition({
    required this.id,
    required this.label,
    required this.sfSymbol,
    required this.materialIcon,
    required this.filter,
  });
}

// ── Plugin interface ──────────────────────────────────────────────

abstract class NotibarPlugin {
  ServiceType get serviceType;

  /// Human-readable name (e.g. 'Microsoft 365', 'GitHub').
  String get serviceLabel;

  /// Material icon for the settings UI.
  IconData get serviceIcon;

  /// Config fields needed for account setup.
  /// Keys are config map keys, values are human-readable labels.
  Map<String, String> get configFields;

  /// The display metrics this plugin supports, with all UI metadata.
  List<MetricDefinition> get supportedMetrics;

  /// Format a notification item as a native menu entry.
  StatusMenuItem formatMenuEntry(NotificationItem item);

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

  /// Returns the web URL for viewing a specific metric on the service's
  /// website, filtered appropriately. Returns null if not applicable.
  String? webUrl(
    Account account,
    String metricId,
    Map<String, String> config,
  ) => null;

  /// Look up a metric definition by its ID. Returns null if not found.
  MetricDefinition? metricById(String id) =>
      supportedMetrics.where((m) => m.id == id).firstOrNull;
}

// ── Summary & errors ──────────────────────────────────────────────

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
