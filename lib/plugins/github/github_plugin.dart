import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../models/account.dart';
import '../../models/notification_item.dart';
import '../plugin_interface.dart';

class GithubPlugin implements NotibarPlugin {
  @override
  ServiceType get serviceType => ServiceType.github;

  @override
  Future<NotificationSummary> fetchNotifications(Account account) async {
    final token = account.apiKey;
    if (token == null || token.isEmpty) {
      return NotificationSummary.withError(
        PluginError(type: PluginErrorType.authentication, message: 'GitHub Personal Access Token is missing'),
      );
    }

    final owner = account.config['owner']?.trim();
    final repo = account.config['repo']?.trim();
    
    String url = 'https://api.github.com/notifications';
    if (owner != null && owner.isNotEmpty && repo != null && repo.isNotEmpty) {
      url = 'https://api.github.com/repos/$owner/$repo/notifications';
    }

    try {
      final response = await http.get(
        Uri.parse('$url?all=false&per_page=20'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/vnd.github.v3+json',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 401 || response.statusCode == 403) {
        return NotificationSummary.withError(
          PluginError(type: PluginErrorType.authentication, message: 'GitHub authentication failed'),
        );
      }

      if (response.statusCode != 200) {
        return NotificationSummary.withError(
          PluginError(type: PluginErrorType.network, message: 'Failed to fetch GitHub notifications: ${response.statusCode}'),
        );
      }

      final data = json.decode(response.body);
      return parseSummary({'value': data});
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
  }) {
    final List<dynamic> data = json['value'] ?? [];
    int calculatedUnread = 0;
    int calculatedMentions = 0;
    int calculatedAssignedIssues = 0;
    int calculatedAssignedPRs = 0;
    int calculatedReviewRequests = 0;

    final items = data.map((n) {
      final isUnread = n['unread'] == true;
      if (isUnread) calculatedUnread++;

      final reason = n['reason'] as String? ?? '';
      final subject = n['subject'] ?? {};
      final subjectType = subject['type'] as String? ?? '';

      if (reason == 'mention' || reason == 'team_mention') {
        calculatedMentions++;
      } else if (reason == 'assign') {
        if (subjectType == 'Issue') {
          calculatedAssignedIssues++;
        } else if (subjectType == 'PullRequest') {
          calculatedAssignedPRs++;
        }
      } else if (reason == 'review_requested') {
        calculatedReviewRequests++;
      }

      final repoData = n['repository'] ?? {};
      
      String actionUrl = '';
      if (subject['url'] != null) {
        actionUrl = (subject['url'] as String)
            .replaceFirst('api.github.com/repos', 'github.com')
            .replaceFirst('/pulls/', '/pull/');
      } else {
        actionUrl = repoData['html_url'] ?? '';
      }

      DateTime? timestamp;
      try {
        if (n['updated_at'] != null) {
          timestamp = DateTime.parse(n['updated_at']);
        }
      } catch (_) {}

      return NotificationItem(
        id: n['id'] ?? '',
        title: subject['title'] ?? '(No Title)',
        subtitle: repoData['full_name'] ?? 'GitHub',
        timestamp: timestamp ?? DateTime.now(),
        actionUrl: actionUrl,
        isUnread: isUnread,
        isFlagged: reason == 'mention' || reason == 'assign' || reason == 'review_requested',
        metadata: {
          'reason': reason,
          'type': subjectType,
          'repository': repoData['full_name'],
        },
      );
    }).toList();

    return NotificationSummary(
      unreadCount: unreadCount ?? calculatedUnread,
      flaggedCount: flaggedCount ?? 0,
      mentionCount: mentionCount ?? calculatedMentions,
      assignedIssuesCount: assignedIssuesCount ?? calculatedAssignedIssues,
      assignedPRsCount: assignedPRsCount ?? calculatedAssignedPRs,
      reviewRequestsCount: reviewRequestsCount ?? calculatedReviewRequests,
      items: items,
    );
  }
}
