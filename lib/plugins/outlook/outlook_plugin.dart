import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../models/account.dart';
import '../../models/notification_item.dart';
import '../plugin_interface.dart';

const _tag = '[Outlook]';

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
      debugPrint('$_tag fetchNotifications for account=${account.name} (${account.id})');
      final stopwatch = Stopwatch()..start();

      // Unread count
      final unreadCount = await _fetchCount(token, 'isRead eq false');
      // Flagged count
      final flaggedCount = await _fetchCount(token, "flag/flagStatus eq 'flagged'");
      debugPrint('$_tag counts: unread=$unreadCount, flagged=$flaggedCount (${stopwatch.elapsedMilliseconds}ms)');

      // Fetch unread and flagged messages in parallel so both dropdowns have items.
      const fields = 'id,subject,from,receivedDateTime,webLink,isRead,flag,bodyPreview,parentFolderId';
      final results = await Future.wait([
        _fetchMessages(token, {
          r'$filter': 'isRead eq false',
          r'$select': fields,
          r'$orderby': 'receivedDateTime desc',
        }),
        _fetchMessages(token, {
          r'$filter': "flag/flagStatus eq 'flagged'",
          r'$select': fields,
        }),
        _fetchFolderMap(token),
        _fetchInboxFolderId(token),
      ]);

      // Message fetch failures are non-fatal; counts still show.
      final unreadMessages = results[0] as List<dynamic>;
      final flaggedMessages = results[1] as List<dynamic>;
      final folderMap = results[2] as Map<String, String>;
      final inboxFolderId = results[3] as String;
      debugPrint('$_tag fetched ${unreadMessages.length} unread items, ${flaggedMessages.length} flagged items, ${folderMap.length} folders, inbox=$inboxFolderId (${stopwatch.elapsedMilliseconds}ms)');

      // Merge and deduplicate by message ID.
      final seen = <String>{};
      final allMessages = <dynamic>[];
      for (final m in [...unreadMessages, ...flaggedMessages]) {
        final id = m['id'] as String? ?? '';
        if (seen.add(id)) allMessages.add(m);
      }
      debugPrint('$_tag merged ${allMessages.length} unique items, total time: ${stopwatch.elapsedMilliseconds}ms');

      return parseSummary(
        {'value': allMessages, 'folderMap': folderMap, 'inboxFolderId': inboxFolderId},
        unreadCount: unreadCount,
        flaggedCount: flaggedCount,
      );
    } on SocketException catch (e) {
      debugPrint('$_tag SocketException: $e');
      return NotificationSummary.withError(
        PluginError(type: PluginErrorType.network, message: 'No internet connection'),
      );
    } catch (e, stack) {
      debugPrint('$_tag unexpected error: $e\n$stack');
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
    final List<dynamic> messages = json['value'] ?? [];
    final folderMap = (json['folderMap'] as Map<String, String>?) ?? {};
    final inboxFolderId = (json['inboxFolderId'] as String?) ?? '';

    final items = messages.map((m) {
      final fromData = m['from']?['emailAddress'];
      final fromName = fromData?['name'] ?? fromData?['address'] ?? 'Unknown';
      
      DateTime? timestamp;
      try {
        if (m['receivedDateTime'] != null) {
          timestamp = DateTime.parse(m['receivedDateTime']);
        }
      } catch (_) {}

      final folderId = m['parentFolderId'] as String? ?? '';
      final folderName = folderMap[folderId] ?? '';
      final isInbox = folderId == inboxFolderId;

      return NotificationItem(
        id: m['id'] ?? '',
        title: m['subject'] ?? '(No Subject)',
        subtitle: fromName,
        body: m['bodyPreview'] as String?,
        timestamp: timestamp ?? DateTime.now(),
        actionUrl: m['webLink'] ?? '',
        isUnread: !(m['isRead'] ?? true),
        isFlagged: m['flag']?['flagStatus'] == 'flagged',
        metadata: {
          'id': m['id'],
          'from': fromName,
          'isRead': m['isRead'],
          'folder': folderName,
          'isInbox': isInbox,
        },
      );
    }).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return NotificationSummary(
      unreadCount: unreadCount ?? items.where((i) => i.isUnread).length,
      flaggedCount: flaggedCount ?? items.where((i) => i.isFlagged).length,
      items: items,
    );
  }

  /// Fetches messages with the given OData query params, paginating in batches of 50.
  /// Returns a list of raw message JSON objects. Returns empty on any failure.
  Future<List<dynamic>> _fetchMessages(String token, Map<String, String> queryParams) async {
    try {
      final allItems = <dynamic>[];
      Uri? nextUri = Uri.https(
        'graph.microsoft.com',
        '/v1.0/me/messages',
        {...queryParams, r'$top': '50'},
      );

      while (nextUri != null) {
        final response = await http.get(
          nextUri,
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode != 200) {
          debugPrint('$_tag _fetchMessages failed: ${response.statusCode} ${response.body.length > 200 ? response.body.substring(0, 200) : response.body}');
          return allItems;
        }

        final data = json.decode(response.body);
        final items = data['value'] as List<dynamic>? ?? [];
        allItems.addAll(items);
        debugPrint('$_tag _fetchMessages page: ${items.length} items (total ${allItems.length})');

        final nextLink = data['@odata.nextLink'] as String?;
        nextUri = nextLink != null ? Uri.parse(nextLink) : null;
      }

      debugPrint('$_tag _fetchMessages OK: ${allItems.length} total items');
      return allItems;
    } catch (e) {
      debugPrint('$_tag _fetchMessages exception: $e');
      return [];
    }
  }

  /// Fetches mail folders and returns a map of folderId → displayName.
  Future<Map<String, String>> _fetchFolderMap(String token) async {
    try {
      final uri = Uri.https(
        'graph.microsoft.com',
        '/v1.0/me/mailFolders',
        {r'$select': 'id,displayName', r'$top': '50'},
      );
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint('$_tag _fetchFolderMap failed: ${response.statusCode}');
        return {};
      }

      final data = json.decode(response.body);
      final folders = data['value'] as List<dynamic>? ?? [];
      final map = <String, String>{};
      for (final f in folders) {
        final id = f['id'] as String?;
        final name = f['displayName'] as String?;
        if (id != null && name != null) map[id] = name;
      }
      debugPrint('$_tag _fetchFolderMap OK: ${map.length} folders (${map.values.join(', ')})');
      return map;
    } catch (e) {
      debugPrint('$_tag _fetchFolderMap exception: $e');
      return {};
    }
  }

  /// Fetches the Inbox folder ID using the well-known name.
  Future<String> _fetchInboxFolderId(String token) async {
    try {
      final uri = Uri.https(
        'graph.microsoft.com',
        '/v1.0/me/mailFolders/Inbox',
        {r'$select': 'id'},
      );
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint('$_tag _fetchInboxFolderId failed: ${response.statusCode}');
        return '';
      }

      final data = json.decode(response.body);
      return (data['id'] as String?) ?? '';
    } catch (e) {
      debugPrint('$_tag _fetchInboxFolderId exception: $e');
      return '';
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
        debugPrint('$_tag _fetchCount($filter) failed: ${response.statusCode}');
        return 0;
      }

      final count = int.tryParse(response.body) ?? 0;
      return count;
    } catch (e) {
      debugPrint('$_tag _fetchCount($filter) exception: $e');
      return 0;
    }
  }
}
