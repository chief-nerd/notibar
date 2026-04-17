import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../models/account.dart';
import '../../models/notification_item.dart';
import '../../services/multi_status_item_channel.dart';
import '../plugin_interface.dart';

class TeamsPlugin extends NotibarPlugin {
  @override
  ServiceType get serviceType => ServiceType.teams;

  @override
  String get serviceLabel => 'Microsoft Teams';

  @override
  IconData get serviceIcon => Icons.group;

  @override
  Map<String, String> get configFields => {
    'clientId': 'Azure App Client ID',
    'tenantId': 'Tenant ID (or "common")',
  };

  @override
  List<MetricDefinition> get supportedMetrics => [
    MetricDefinition(
      id: 'unread',
      label: 'Unread',
      sfSymbol: 'envelope.badge',
      materialIcon: Icons.mark_email_unread_outlined,
      filter: (s, _) => s.items.where((i) => i.isUnread).toList(),
    ),
    MetricDefinition(
      id: 'mentions',
      label: 'Mentions',
      sfSymbol: 'tag',
      materialIcon: Icons.alternate_email,
      filter: (s, _) => s.items.where((i) => i.isFlagged).toList(),
    ),
  ];

  @override
  String? webUrl(Account account, String metricId, Map<String, String> config) {
    return 'https://teams.microsoft.com/';
  }

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
    final token = account.apiKey;
    if (token == null || token.isEmpty) {
      return NotificationSummary.withError(
        PluginError(
          type: PluginErrorType.authentication,
          message: 'Microsoft Teams token is missing',
        ),
      );
    }

    try {
      final chatResponse = await http
          .get(
            Uri.parse(
              "https://graph.microsoft.com/v1.0/me/chats?\$filter=viewType eq 'unread'",
            ),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (chatResponse.statusCode == 401) {
        return NotificationSummary.withError(
          PluginError(
            type: PluginErrorType.authentication,
            message: 'Teams authentication failed',
          ),
        );
      }

      final List<NotificationItem> items = [];
      int unreadCount = 0;

      if (chatResponse.statusCode == 200) {
        final data = json.decode(chatResponse.body);
        final summary = parseSummary(data);
        unreadCount = summary.unreadCount;
        items.addAll(summary.items);
      }

      final activityResponse = await http
          .get(
            Uri.parse('https://graph.microsoft.com/v1.0/me/notifications'),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));

      int mentionCount = 0;
      if (activityResponse.statusCode == 200) {
        final activityData = json.decode(activityResponse.body);
        final List<dynamic> notifications = activityData['value'] ?? [];
        mentionCount = notifications.length;

        for (var n in notifications) {
          final title = n['displayText'] ?? 'Teams Notification';
          DateTime? timestamp;
          try {
            if (n['createdAt'] != null) {
              timestamp = DateTime.parse(n['createdAt']);
            }
          } catch (_) {}

          items.add(
            NotificationItem(
              id: n['id'] ?? '',
              title: title,
              subtitle: 'Teams Activity',
              timestamp: timestamp ?? DateTime.now(),
              actionUrl: 'https://teams.microsoft.com/',
              isUnread: true,
              isFlagged: true,
              metadata: {'source': 'activity', 'id': n['id']},
            ),
          );
        }
      }

      return NotificationSummary(
        unreadCount: unreadCount,
        mentionCount: mentionCount,
        items: items,
      );
    } on SocketException {
      return NotificationSummary.withError(
        PluginError(
          type: PluginErrorType.network,
          message: 'No internet connection',
        ),
      );
    } catch (e) {
      if (e.toString().contains('403')) {
        return NotificationSummary.withError(
          PluginError(
            type: PluginErrorType.authentication,
            message: 'Insufficient permissions for Teams API',
          ),
        );
      }
      return NotificationSummary.withError(
        PluginError(type: PluginErrorType.unknown, message: e.toString()),
      );
    }
  }

  @override
  NotificationSummary parseSummary(
    Map<String, dynamic> json, {
    int? unreadCount,
    int? flaggedCount,
    int? mentionCount,
    int? assignedIssuesCount,
    int? assignedPRsCount,
    int? reviewRequestsCount,
  }) {
    final List<dynamic> chats = json['value'] ?? [];
    final List<NotificationItem> items = [];

    for (var chat in chats) {
      final topic = chat['topic'] ?? 'Direct Chat';
      final lastMessagePreview =
          chat['lastMessagePreview']?['body']?['content'] ?? 'No preview';
      DateTime? timestamp;
      try {
        if (chat['lastUpdatedDateTime'] != null) {
          timestamp = DateTime.parse(chat['lastUpdatedDateTime']);
        }
      } catch (_) {}

      items.add(
        NotificationItem(
          id: chat['id'] ?? '',
          title: topic,
          subtitle: lastMessagePreview,
          timestamp: timestamp ?? DateTime.now(),
          actionUrl:
              'https://teams.microsoft.com/_#/l/chat/${chat['id']}/0?anon=true',
          isUnread: true,
          isFlagged: false,
          metadata: {'source': 'chat', 'chatId': chat['id']},
        ),
      );
    }

    return NotificationSummary(
      unreadCount: unreadCount ?? items.length,
      mentionCount: mentionCount ?? 0,
      items: items,
    );
  }
}
