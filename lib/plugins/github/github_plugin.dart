import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../models/account.dart';
import '../../models/notification_item.dart';
import '../../services/multi_status_item_channel.dart';
import '../plugin_interface.dart';

class GithubPlugin extends NotibarPlugin {
  @override
  ServiceType get serviceType => ServiceType.github;

  @override
  String get serviceLabel => 'GitHub';

  @override
  IconData get serviceIcon => Icons.code;

  @override
  Map<String, String> get configFields => {
    'owner': 'Repository Owner',
    'repo': 'Repository Name',
  };

  @override
  List<MetricDefinition> get supportedMetrics => [
    MetricDefinition(
      id: 'assignedIssues',
      label: 'Assigned Issues',
      sfSymbol: 'ticket',
      materialIcon: Icons.assignment_ind_outlined,
      filter: (s, _) =>
          s.items.where((i) => i.metadata['type'] == 'Issue').toList(),
    ),
    MetricDefinition(
      id: 'assignedPRs',
      label: 'Assigned PRs',
      sfSymbol: 'arrow.trianglehead.pull',
      materialIcon: Icons.merge_type,
      filter: (s, _) => s.items
          .where(
            (i) =>
                i.metadata['type'] == 'PullRequest' &&
                i.metadata['reason'] != 'review_requested',
          )
          .toList(),
    ),
    MetricDefinition(
      id: 'reviewRequests',
      label: 'Review Requests',
      sfSymbol: 'eye',
      materialIcon: Icons.rate_review_outlined,
      filter: (s, _) {
        final assignedPRKeys = s.items
            .where(
              (i) =>
                  i.metadata['type'] == 'PullRequest' &&
                  i.metadata['reason'] != 'review_requested',
            )
            .map((i) => '${i.metadata['repository']}#${i.metadata['number']}')
            .toSet();
        return s.items
            .where(
              (i) =>
                  i.metadata['type'] == 'PullRequest' &&
                  i.metadata['reason'] == 'review_requested' &&
                  !assignedPRKeys.contains(
                    '${i.metadata['repository']}#${i.metadata['number']}',
                  ),
            )
            .toList();
      },
    ),
  ];

  @override
  String? webUrl(Account account, String metricId, Map<String, String> config) {
    final owner = account.config['owner']?.trim();
    final repo = account.config['repo']?.trim();
    final hasRepo =
        owner != null && owner.isNotEmpty && repo != null && repo.isNotEmpty;

    switch (metricId) {
      case 'assignedIssues':
        return hasRepo
            ? 'https://github.com/$owner/$repo/issues?q=is%3Aopen+is%3Aissue+assignee%3A%40me'
            : 'https://github.com/issues?q=is%3Aopen+is%3Aissue+assignee%3A%40me';
      case 'assignedPRs':
        return hasRepo
            ? 'https://github.com/$owner/$repo/pulls?q=is%3Aopen+is%3Apr+assignee%3A%40me'
            : 'https://github.com/pulls?q=is%3Aopen+is%3Apr+assignee%3A%40me';
      case 'reviewRequests':
        return hasRepo
            ? 'https://github.com/$owner/$repo/pulls?q=is%3Aopen+is%3Apr+review-requested%3A%40me'
            : 'https://github.com/pulls?q=is%3Aopen+is%3Apr+review-requested%3A%40me';
      default:
        return null;
    }
  }

  @override
  StatusMenuItem formatMenuEntry(NotificationItem item) {
    final number = item.metadata['number'];
    var title = item.title;
    if (title.length > 60) title = '${title.substring(0, 57)}...';
    final line1 = number != null ? '#$number $title' : title;

    final repo = item.subtitle ?? '';
    final labels =
        (item.metadata['labels'] as List<dynamic>?)?.cast<String>() ?? [];
    final labelStr = labels.map((l) => '[$l]').join(' ');
    final line2 = [repo, if (labelStr.isNotEmpty) labelStr].join('  ');

    return StatusMenuItem(
      label: line1,
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
          message: 'GitHub Personal Access Token is missing',
        ),
      );
    }

    final owner = account.config['owner']?.trim();
    final repo = account.config['repo']?.trim();
    final headers = {
      'Authorization': 'Bearer $token',
      'Accept': 'application/vnd.github.v3+json',
    };

    try {
      // Fetch authenticated user's login for search queries
      final userResponse = await http
          .get(Uri.parse('https://api.github.com/user'), headers: headers)
          .timeout(const Duration(seconds: 15));

      if (userResponse.statusCode == 401 || userResponse.statusCode == 403) {
        return NotificationSummary.withError(
          PluginError(
            type: PluginErrorType.authentication,
            message: 'GitHub authentication failed',
          ),
        );
      }

      final username = json.decode(userResponse.body)['login'] as String?;
      if (username == null || username.isEmpty) {
        return NotificationSummary.withError(
          PluginError(
            type: PluginErrorType.unknown,
            message: 'Could not determine GitHub username',
          ),
        );
      }

      // Build search query scope
      final repoScope =
          (owner != null && owner.isNotEmpty && repo != null && repo.isNotEmpty)
          ? 'repo:$owner/$repo+'
          : '';
      final encodedUser = Uri.encodeComponent(username);
      final searchBase =
          'https://api.github.com/search/issues?per_page=100&q=${repoScope}is:open+';

      // Fetch all three search queries in parallel
      final results = await Future.wait([
        http.get(
          Uri.parse('${searchBase}is:issue+assignee:$encodedUser'),
          headers: headers,
        ),
        http.get(
          Uri.parse('${searchBase}is:pr+assignee:$encodedUser'),
          headers: headers,
        ),
        http.get(
          Uri.parse(
            '${searchBase}is:pr+review-requested:$encodedUser+-reviewed-by:$encodedUser',
          ),
          headers: headers,
        ),
      ]).timeout(const Duration(seconds: 15));

      final issueResults = _parseSearch(results[0], 'Issue', 'assign');
      final prResults = _parseSearch(results[1], 'PullRequest', 'assign');
      final reviewResults = _parseSearch(
        results[2],
        'PullRequest',
        'review_requested',
      );

      return NotificationSummary(
        assignedIssuesCount: issueResults.count,
        assignedPRsCount: prResults.count,
        reviewRequestsCount: reviewResults.count,
        items: [
          ...issueResults.items,
          ...prResults.items,
          ...reviewResults.items,
        ],
      );
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

  ({int count, List<NotificationItem> items}) _parseSearch(
    http.Response response,
    String type,
    String reason,
  ) {
    if (response.statusCode != 200) {
      return (count: 0, items: <NotificationItem>[]);
    }
    final body = json.decode(response.body);
    final total = (body['total_count'] as num?)?.toInt() ?? 0;
    final List<dynamic> searchItems = body['items'] ?? [];
    final parsed = searchItems.map((item) {
      final repoFullName =
          (item['repository_url'] as String?)?.replaceFirst(
            'https://api.github.com/repos/',
            '',
          ) ??
          '';

      DateTime? timestamp;
      try {
        timestamp = DateTime.parse(item['updated_at'] ?? item['created_at']);
      } catch (_) {}

      final labels =
          (item['labels'] as List<dynamic>?)
              ?.map((l) => l['name'] as String? ?? '')
              .where((l) => l.isNotEmpty)
              .toList() ??
          [];

      return NotificationItem(
        id: '${item['id']}',
        title: item['title'] ?? '(No Title)',
        subtitle: repoFullName,
        timestamp: timestamp ?? DateTime.now(),
        actionUrl: item['html_url'] ?? '',
        isUnread: true,
        isFlagged: false,
        metadata: {
          'reason': reason,
          'type': type,
          'repository': repoFullName,
          'number': item['number'],
          'state': item['state'],
          'labels': labels,
        },
      );
    }).toList();
    return (count: total, items: parsed);
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
    // Parse search API response directly
    final total = (json['total_count'] as num?)?.toInt() ?? 0;
    final List<dynamic> data = json['items'] ?? [];
    final type = json['_type'] as String? ?? 'Issue';
    final reason = json['_reason'] as String? ?? 'assign';

    final items = data.map((item) {
      final repoFullName =
          (item['repository_url'] as String?)?.replaceFirst(
            'https://api.github.com/repos/',
            '',
          ) ??
          '';

      DateTime? timestamp;
      try {
        timestamp = DateTime.parse(item['updated_at'] ?? item['created_at']);
      } catch (_) {}

      final labels =
          (item['labels'] as List<dynamic>?)
              ?.map((l) => l['name'] as String? ?? '')
              .where((l) => l.isNotEmpty)
              .toList() ??
          [];

      return NotificationItem(
        id: '${item['id']}',
        title: item['title'] ?? '(No Title)',
        subtitle: repoFullName,
        timestamp: timestamp ?? DateTime.now(),
        actionUrl: item['html_url'] ?? '',
        isUnread: true,
        isFlagged: false,
        metadata: {
          'reason': reason,
          'type': type,
          'repository': repoFullName,
          'number': item['number'],
          'state': item['state'],
          'labels': labels,
        },
      );
    }).toList();

    return NotificationSummary(
      assignedIssuesCount: type == 'Issue' ? (assignedIssuesCount ?? total) : 0,
      assignedPRsCount: type == 'PullRequest' && reason != 'review_requested'
          ? (assignedPRsCount ?? total)
          : 0,
      reviewRequestsCount: reason == 'review_requested'
          ? (reviewRequestsCount ?? total)
          : 0,
      items: items,
    );
  }
}
