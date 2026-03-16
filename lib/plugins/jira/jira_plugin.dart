import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../models/account.dart';
import '../../models/notification_item.dart';
import '../plugin_interface.dart';

class JiraPlugin implements NotibarPlugin {
  @override
  ServiceType get serviceType => ServiceType.jira;

  @override
  Future<NotificationSummary> fetchNotifications(Account account) async {
    final token = account.apiKey;
    if (token == null || token.isEmpty) {
      return NotificationSummary.withError(
        PluginError(type: PluginErrorType.authentication, message: 'Jira token is missing'),
      );
    }

    final baseUrl = account.config['baseUrl']?.trim().replaceAll(RegExp(r'/$'), '');
    final projectKey = account.config['projectKey']?.trim();

    if (baseUrl == null || baseUrl.isEmpty) {
      return NotificationSummary.withError(
        PluginError(type: PluginErrorType.unknown, message: 'Jira Base URL is required'),
      );
    }

    try {
      String jql = 'resolution = Unresolved AND assignee = currentUser() ORDER BY updated DESC';
      if (projectKey != null && projectKey.isNotEmpty) {
        jql = 'project = "$projectKey" AND $jql';
      }

      final authHeader = token.startsWith('Basic ') || token.startsWith('Bearer ')
          ? token
          : 'Basic $token';

      final response = await http.get(
        Uri.parse('$baseUrl/rest/api/2/search?jql=${Uri.encodeComponent(jql)}&maxResults=15'),
        headers: {
          'Authorization': authHeader,
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 401 || response.statusCode == 403) {
        return NotificationSummary.withError(
          PluginError(type: PluginErrorType.authentication, message: 'Jira authentication failed'),
        );
      }

      if (response.statusCode != 200) {
        return NotificationSummary.withError(
          PluginError(type: PluginErrorType.network, message: 'Failed to fetch Jira issues: ${response.statusCode}'),
        );
      }

      final data = json.decode(response.body);
      return parseSummary(data, baseUrl: baseUrl);
    } on SocketException {
      return NotificationSummary.withError(
        PluginError(type: PluginErrorType.network, message: 'No internet connection'),
      );
    } catch (e) {
      return NotificationSummary.withError(
        PluginError(type: PluginErrorType.unknown, message: e.toString()),
      );
    }
  }

  @override
  NotificationSummary parseSummary(Map<String, dynamic> json, {
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
        metadata: {
          'key': key,
          'status': status,
          'priority': priority,
        },
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
