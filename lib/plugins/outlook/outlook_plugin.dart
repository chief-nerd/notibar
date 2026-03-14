import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../models/account.dart';
import '../../models/notification_item.dart';
import '../plugin_interface.dart';

class OutlookPlugin implements NotibarPlugin {
  @override
  ServiceType get serviceType => ServiceType.outlook;

  @override
  Future<NotificationSummary> fetchNotifications(Account account) async {
    final token = account.apiKey;
    if (token == null || token.isEmpty) {
      return NotificationSummary.withError(
        PluginError(type: PluginErrorType.authentication, message: 'Outlook API key (token) is missing'),
      );
    }

    try {
      // Unread count
      final unreadCount = await _fetchCount(token, 'isRead eq false');
      // Flagged count
      final flaggedCount = await _fetchCount(token, "flag/flagStatus eq 'flagged'");

      // Fetch items
      final response = await http.get(
        Uri.parse('https://graph.microsoft.com/v1.0/me/messages?\$top=15&\$select=id,subject,from,receivedDateTime,webLink,isRead,flag&\$orderby=receivedDateTime desc'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 401) {
        return NotificationSummary.withError(
          PluginError(type: PluginErrorType.authentication, message: 'Authentication failed (401)'),
        );
      }

      if (response.statusCode != 200) {
        return NotificationSummary.withError(
          PluginError(type: PluginErrorType.network, message: 'Failed to fetch messages: ${response.statusCode}'),
        );
      }

      final data = json.decode(response.body);
      final List<dynamic> messages = data['value'] ?? [];

      final items = messages.map((m) {
        final from = m['from']?['emailAddress']?['name'] ?? m['from']?['emailAddress']?['address'] ?? 'Unknown';
        DateTime? timestamp;
        try {
          if (m['receivedDateTime'] != null) {
            timestamp = DateTime.parse(m['receivedDateTime']);
          }
        } catch (_) {}

        return NotificationItem(
          id: m['id'] ?? '',
          title: m['subject'] ?? '(No Subject)',
          subtitle: from,
          timestamp: timestamp ?? DateTime.now(),
          actionUrl: m['webLink'] ?? '',
          isUnread: !(m['isRead'] ?? true),
          isFlagged: m['flag']?['flagStatus'] == 'flagged',
        );
      }).toList();

      return NotificationSummary(
        unreadCount: unreadCount,
        flaggedCount: flaggedCount,
        items: items,
      );
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

  Future<int> _fetchCount(String token, String filter) async {
    try {
      final response = await http.get(
        Uri.parse('https://graph.microsoft.com/v1.0/me/messages/\$count?\$filter=$filter'),
        headers: {
          'Authorization': 'Bearer $token',
          'ConsistencyLevel': 'eventual',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return 0;
      }

      return int.tryParse(response.body) ?? 0;
    } catch (_) {
      return 0;
    }
  }
}
