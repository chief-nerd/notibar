import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../models/account.dart';
import '../../models/notification_item.dart';
import '../../services/multi_status_item_channel.dart';
import '../plugin_interface.dart';

class MattermostPlugin extends NotibarPlugin {
  @override
  ServiceType get serviceType => ServiceType.mattermost;

  @override
  String get serviceLabel => 'Mattermost';

  @override
  IconData get serviceIcon => Icons.forum;

  @override
  Map<String, String> get configFields => {'baseUrl': 'Mattermost Base URL'};

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
    final baseUrl = account.config['baseUrl']?.trim().replaceAll(
      RegExp(r'/$'),
      '',
    );
    if (baseUrl == null || baseUrl.isEmpty) return null;
    return baseUrl;
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
          message: 'Mattermost Personal Access Token is missing',
        ),
      );
    }

    final baseUrl = account.config['baseUrl']?.trim().replaceAll(
      RegExp(r'/$'),
      '',
    );
    if (baseUrl == null || baseUrl.isEmpty) {
      return NotificationSummary.withError(
        PluginError(
          type: PluginErrorType.unknown,
          message: 'Mattermost Base URL is required',
        ),
      );
    }

    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/v4/users/me/teams/unread'),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 401 || response.statusCode == 403) {
        return NotificationSummary.withError(
          PluginError(
            type: PluginErrorType.authentication,
            message: 'Mattermost authentication failed',
          ),
        );
      }

      if (response.statusCode != 200) {
        return NotificationSummary.withError(
          PluginError(
            type: PluginErrorType.network,
            message:
                'Failed to fetch Mattermost unreads: ${response.statusCode}',
          ),
        );
      }

      final data = json.decode(response.body);
      return parseSummary({'teams': data}, baseUrl: baseUrl);
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
    int? unreadCount,
    int? flaggedCount,
    int? mentionCount,
    int? assignedIssuesCount,
    int? assignedPRsCount,
    int? reviewRequestsCount,
    String? baseUrl,
  }) {
    final List<dynamic> teams = json['teams'] ?? [];

    int totalUnread = 0;
    int totalMentions = 0;
    final List<NotificationItem> items = [];

    for (var team in teams) {
      final teamId = team['team_id'] ?? 'unknown';
      final msgCount = team['msg_count'] as int? ?? 0;
      final mentionCountVal = team['mention_count'] as int? ?? 0;

      if (msgCount > 0 || mentionCountVal > 0) {
        totalUnread += msgCount;
        totalMentions += mentionCountVal;

        items.add(
          NotificationItem(
            id: teamId,
            title: 'Mattermost Team',
            subtitle: '$msgCount unread, $mentionCountVal mentions',
            timestamp: DateTime.now(),
            actionUrl: baseUrl != null ? '$baseUrl/' : '',
            isUnread: msgCount > 0,
            isFlagged: mentionCountVal > 0,
            metadata: {
              'teamId': teamId,
              'unreadCount': msgCount,
              'mentionCount': mentionCountVal,
            },
          ),
        );
      }
    }

    return NotificationSummary(
      unreadCount: unreadCount ?? totalUnread,
      mentionCount: mentionCount ?? totalMentions,
      items: items,
    );
  }
}
