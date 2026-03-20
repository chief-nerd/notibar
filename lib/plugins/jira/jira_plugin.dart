import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../models/account.dart';
import '../../models/notification_item.dart';
import '../../services/multi_status_item_channel.dart';
import '../plugin_interface.dart';

class JiraPlugin extends NotibarPlugin {
  @override
  ServiceType get serviceType => ServiceType.jira;

  @override
  String get serviceLabel => 'Jira';

  @override
  IconData get serviceIcon => Icons.bug_report;

  @override
  Map<String, String> get configFields => {
    'baseUrl': 'Jira Base URL',
    'projectKey': 'Project Key',
  };

  @override
  List<MetricDefinition> get supportedMetrics => [
    MetricDefinition(
      id: 'assignedIssues',
      label: 'Assigned Issues',
      sfSymbol: 'ticket',
      materialIcon: Icons.assignment_ind_outlined,
      count: (s, _) => s.assignedIssuesCount,
      filter: (s, _) => s.items,
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
    final status = item.subtitle ?? '';
    final priority = item.metadata['priority'] as String? ?? '';
    final line2 = [status, if (priority.isNotEmpty) priority].join(' \u2022 ');

    return StatusMenuItem(
      label: title,
      subtitle: line2.isNotEmpty ? line2 : null,
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
          message: 'Jira token is missing',
        ),
      );
    }

    final baseUrl = account.config['baseUrl']?.trim().replaceAll(
      RegExp(r'/$'),
      '',
    );
    final projectKey = account.config['projectKey']?.trim();

    if (baseUrl == null || baseUrl.isEmpty) {
      return NotificationSummary.withError(
        PluginError(
          type: PluginErrorType.unknown,
          message: 'Jira Base URL is required',
        ),
      );
    }

    try {
      String jql =
          'resolution = Unresolved AND assignee = currentUser() ORDER BY updated DESC';
      if (projectKey != null && projectKey.isNotEmpty) {
        jql = 'project = "$projectKey" AND $jql';
      }

      final authHeader =
          token.startsWith('Basic ') || token.startsWith('Bearer ')
          ? token
          : 'Basic $token';

      final response = await http
          .get(
            Uri.parse(
              '$baseUrl/rest/api/2/search?jql=${Uri.encodeComponent(jql)}&maxResults=15',
            ),
            headers: {
              'Authorization': authHeader,
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 401 || response.statusCode == 403) {
        return NotificationSummary.withError(
          PluginError(
            type: PluginErrorType.authentication,
            message: 'Jira authentication failed',
          ),
        );
      }

      if (response.statusCode != 200) {
        return NotificationSummary.withError(
          PluginError(
            type: PluginErrorType.network,
            message: 'Failed to fetch Jira issues: ${response.statusCode}',
          ),
        );
      }

      final data = json.decode(response.body);
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
    int? unreadCount,
    int? flaggedCount,
    int? mentionCount,
    int? assignedIssuesCount,
    int? assignedPRsCount,
    int? reviewRequestsCount,
    String? baseUrl,
  }) {
    final List<dynamic> issues = json['issues'] ?? [];

    final items = issues.map((issue) {
      final fields = issue['fields'] ?? {};
      final key = issue['key'] ?? '';
      final summary = fields['summary'] ?? '(No Summary)';
      final status = fields['status']?['name'] ?? 'Unknown';
      final priority = fields['priority']?['name'] ?? 'Medium';

      DateTime? timestamp;
      try {
        if (fields['updated'] != null) {
          timestamp = DateTime.parse(fields['updated']);
        }
      } catch (_) {}

      return NotificationItem(
        id: issue['id'] ?? '',
        title: '[$key] $summary',
        subtitle: 'Status: $status',
        timestamp: timestamp ?? DateTime.now(),
        actionUrl: baseUrl != null ? '$baseUrl/browse/$key' : '',
        isUnread: true,
        isFlagged: priority == 'Highest' || priority == 'High',
        metadata: {'key': key, 'status': status, 'priority': priority},
      );
    }).toList();

    return NotificationSummary(
      unreadCount: unreadCount ?? 0,
      flaggedCount: flaggedCount ?? items.where((i) => i.isFlagged).length,
      assignedIssuesCount: assignedIssuesCount ?? items.length,
      items: items,
    );
  }
}
