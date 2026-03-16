import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../models/account.dart';
import '../../models/notification_item.dart';
import '../plugin_interface.dart';

class SlackPlugin implements NotibarPlugin {
  @override
  ServiceType get serviceType => ServiceType.slack;

  @override
  Future<NotificationSummary> fetchNotifications(Account account) async {
    final token = account.apiKey;
    if (token == null || token.isEmpty) {
      return NotificationSummary.withError(
        PluginError(type: PluginErrorType.authentication, message: 'Slack User Token (xoxp-...) is missing'),
      );
    }

    try {
      final response = await http.get(
        Uri.parse('https://slack.com/api/conversations.list?types=public_channel,private_channel,im,mpim&exclude_archived=true'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return NotificationSummary.withError(
          PluginError(type: PluginErrorType.network, message: 'Slack API error: ${response.statusCode}'),
        );
      }

      final data = json.decode(response.body);
      if (data['ok'] == false) {
        final error = data['error'] ?? 'unknown_error';
        if (error == 'invalid_auth' || error == 'not_authed') {
          return NotificationSummary.withError(
            PluginError(type: PluginErrorType.authentication, message: 'Slack authentication failed: $error'),
          );
        }
        return NotificationSummary.withError(
          PluginError(type: PluginErrorType.unknown, message: 'Slack API error: $error'),
        );
      }

      return parseSummary(data);
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
    final List<dynamic> channels = json['channels'] ?? [];
    int totalUnread = 0;
    int totalMentions = 0;
    
    final List<NotificationItem> items = [];

    for (var channel in channels) {
      final unreadCountVal = channel['unread_count'] as int? ?? 0;
      final mentionCountVal = channel['unread_count_display'] as int? ?? 0;
      
      if (unreadCountVal > 0 || mentionCountVal > 0) {
        totalUnread += unreadCountVal;
        totalMentions += mentionCountVal;

        final name = channel['name'] ?? channel['id'] ?? 'Unknown Channel';
        final isIm = channel['is_im'] == true;
        
        items.add(NotificationItem(
          id: channel['id'] ?? '',
          title: isIm ? 'Direct Message' : '#$name',
          subtitle: '$unreadCountVal unread message${unreadCountVal != 1 ? 's' : ''}',
          timestamp: DateTime.now(),
          actionUrl: 'slack://channel?team=${channel['context_team_id'] ?? ''}&id=${channel['id']}',
          isUnread: unreadCountVal > 0,
          isFlagged: mentionCountVal > 0,
          metadata: {
            'channelId': channel['id'],
            'teamId': channel['context_team_id'],
            'isIm': isIm,
            'unreadCount': unreadCountVal,
            'mentions': mentionCountVal,
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
