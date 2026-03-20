import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../models/account.dart';
import '../../models/notification_item.dart';
import '../../services/multi_status_item_channel.dart';
import '../plugin_interface.dart';

class YourServicePlugin extends NotibarPlugin {
  /// Replace custom with your service type
  @override
  ServiceType get serviceType => ServiceType.custom;

  @override
  String get serviceLabel => 'Custom';

  @override
  IconData get serviceIcon => Icons.notifications;

  @override
  Map<String, String> get configFields => {'baseUrl': 'API Base URL'};

  @override
  List<MetricDefinition> get supportedMetrics => [
    MetricDefinition(
      id: 'unread',
      label: 'Unread',
      sfSymbol: 'envelope.badge',
      materialIcon: Icons.mark_email_unread_outlined,
      count: (s, _) => s.unreadCount,
      filter: (s, _) => s.items.where((i) => i.isUnread).toList(),
    ),
    MetricDefinition(
      id: 'flagged',
      label: 'Flagged',
      sfSymbol: 'flag',
      materialIcon: Icons.flag_outlined,
      count: (s, _) => s.flaggedCount,
      filter: (s, _) => s.items.where((i) => i.isFlagged).toList(),
    ),
    MetricDefinition(
      id: 'all',
      label: 'All',
      sfSymbol: 'tray.full',
      materialIcon: Icons.all_inbox,
      count: (s, _) => s.items.length,
      filter: (s, _) => s.items,
    ),
  ];

  @override
  StatusMenuItem formatMenuEntry(NotificationItem item) {
    var title = item.title;
    if (title.length > 60) title = '${title.substring(0, 57)}...';
    return StatusMenuItem(
      label: title,
      subtitle: item.subtitle,
      hasCallback: item.actionUrl.isNotEmpty,
    );
  }

  @override
  Future<NotificationSummary> fetchNotifications(Account account) async {
    // 1. Validate credentials
    final token = account.apiKey;
    if (token == null || token.isEmpty) {
      return NotificationSummary.withError(
        PluginError(
          type: PluginErrorType.authentication,
          message: 'API key is missing',
        ),
      );
    }

    // 2. Read config values (service URL, project key, etc.)
    final baseUrl = account.endpoint ?? '';

    try {
      // 3. Make HTTP request(s)
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/endpoint'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 401 || response.statusCode == 403) {
        return NotificationSummary.withError(
          PluginError(
            type: PluginErrorType.authentication,
            message: 'Authentication failed',
          ),
        );
      }

      final data = json.decode(response.body) as Map<String, dynamic>;

      // 4. Delegate to parseSummary for testable parsing
      return parseSummary(data, baseUrl: baseUrl);
    } on SocketException {
      return NotificationSummary.withError(
        PluginError(
          type: PluginErrorType.network,
          message: 'No internet connection',
        ),
      );
    } catch (e) {
      return NotificationSummary.withError(
        PluginError(type: PluginErrorType.unknown, message: e.toString()),
      );
    }
  }

  @override
  NotificationSummary parseSummary(
    Map<String, dynamic> json, {
    // Keep the interface params even if unused — required by NotibarPlugin
    int? unreadCount,
    int? flaggedCount,
    int? mentionCount,
    int? assignedIssuesCount,
    int? assignedPRsCount,
    int? reviewRequestsCount,
    // Add extra named params your plugin needs (e.g. baseUrl)
    String? baseUrl,
  }) {
    final List<dynamic> rawItems = json['data'] ?? [];
    final items = rawItems.map((item) {
      return NotificationItem(
        id: '${item['id']}',
        title: item['title'] ?? '(No Title)',
        subtitle: item['project'] ?? '',
        timestamp:
            DateTime.tryParse(item['updated_at'] ?? '') ?? DateTime.now(),
        actionUrl: '$baseUrl/item/${item['id']}',
        isUnread: item['read'] != true,
        isFlagged: item['flagged'] == true,
        metadata: {
          'key': item['key'],
          // Add service-specific metadata here
        },
      );
    }).toList();

    return NotificationSummary(
      unreadCount: unreadCount ?? items.where((i) => i.isUnread).length,
      flaggedCount: flaggedCount ?? items.where((i) => i.isFlagged).length,
      items: items,
    );
  }
}
