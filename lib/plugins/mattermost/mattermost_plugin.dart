import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../models/account.dart';
import '../../models/notification_item.dart';
import '../plugin_interface.dart';

class MattermostPlugin implements NotibarPlugin {
  @override
  ServiceType get serviceType => ServiceType.mattermost;

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

    final baseUrl = account.config['baseUrl']?.trim()?.replaceAll(RegExp(r'/$'), '');
    if (baseUrl == null || baseUrl.isEmpty) {
      return NotificationSummary.withError(
        PluginError(type: PluginErrorType.unknown, message: 'Mattermost Base URL is required'),
      );
    }

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/v4/users/me/teams/unread'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 401 || response.statusCode == 403) {
        return NotificationSummary.withError(
          PluginError(type: PluginErrorType.authentication, message: 'Mattermost authentication failed'),
        );
      }

      if (response.statusCode != 200) {
        return NotificationSummary.withError(
          PluginError(type: PluginErrorType.network, message: 'Failed to fetch Mattermost unreads: ${response.statusCode}'),
        );
      }

      final data = json.decode(response.body);
      return parseSummary({'teams': data}, baseUrl: baseUrl);
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

        items.add(NotificationItem(
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
        ));
      }
    }

    return NotificationSummary(
      unreadCount: unreadCount ?? totalUnread,
      mentionCount: mentionCount ?? totalMentions,
      items: items,
    );
  }
}
