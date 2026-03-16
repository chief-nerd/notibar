import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../models/account.dart';
import '../../models/notification_item.dart';
import '../../services/outlook_auth_service.dart';
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
        PluginError(
          type: PluginErrorType.authentication,
          message: 'Outlook API key (token) is missing',
        ),
      );
    }

    // Try fetching with current token; on 401 refresh and retry once.
    var result = await _doFetch(token, account);
    if (result.error?.type == PluginErrorType.authentication) {
      final refreshed = await _tryRefreshToken(account);
      if (refreshed != null) {
        result = await _doFetch(refreshed.apiKey!, refreshed);
        // Attach the refreshed account so the bloc persists new tokens
        if (result.error == null) {
          result = NotificationSummary(
            unreadCount: result.unreadCount,
            flaggedCount: result.flaggedCount,
            items: result.items,
            refreshedAccount: refreshed,
          );
        }
      }
    }
    return result;
  }

  /// Attempts to refresh the access token using the stored refresh token.
  Future<Account?> _tryRefreshToken(Account account) async {
    final refreshToken = account.config['refreshToken'];
    final clientId = account.config['clientId'];
    if (refreshToken == null || refreshToken.isEmpty || clientId == null) {
      debugPrint('$_tag no refresh token available, cannot auto-refresh');
      return null;
    }

    final authService = OutlookAuthService(
      clientId: clientId,
      tenantId: account.config['tenantId'] ?? 'common',
    );
    final result = await authService.refreshAccessToken(refreshToken);
    if (result == null) {
      debugPrint('$_tag token refresh failed');
      return null;
    }

    debugPrint('$_tag token refreshed successfully');
    final updatedConfig = Map<String, String>.from(account.config);
    if (result.refreshToken != null) {
      updatedConfig['refreshToken'] = result.refreshToken!;
    }
    return account.copyWith(apiKey: result.accessToken, config: updatedConfig);
  }

  Future<NotificationSummary> _doFetch(String token, Account account) async {
    try {
      debugPrint(
        '$_tag fetchNotifications for account=${account.name} (${account.id})',
      );
      final stopwatch = Stopwatch()..start();

      // Quick auth check — if count returns 401, bail early for refresh
      final unreadCount = await _fetchCount(token, 'isRead eq false');
      if (unreadCount == -1) {
        return NotificationSummary.withError(
          PluginError(
            type: PluginErrorType.authentication,
            message: 'Token expired',
          ),
        );
      }
      final flaggedCount = await _fetchCount(
        token,
        "flag/flagStatus eq 'flagged'",
      );
      debugPrint(
        '$_tag counts: unread=$unreadCount, flagged=$flaggedCount (${stopwatch.elapsedMilliseconds}ms)',
      );

      // Fetch unread and flagged messages in parallel so both dropdowns have items.
      const fields =
          'id,subject,from,receivedDateTime,webLink,isRead,flag,bodyPreview,parentFolderId';
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
        _fetchInboxChildFolders(token),
      ]);

      // Message fetch failures are non-fatal; counts still show.
      final unreadMessages = results[0] as List<dynamic>;
      final flaggedMessages = results[1] as List<dynamic>;
      final folderMap = results[2] as Map<String, String>;
      final inboxChildFolders = results[3] as Map<String, String>;
      // Derive inbox folder ID from folderMap (find the "Inbox" entry)
      final inboxFolderId =
          folderMap.entries
              .where((e) => e.value == 'Inbox')
              .map((e) => e.key)
              .firstOrNull ??
          '';
      // Merge child folder names into folderMap so they get proper display names
      folderMap.addAll(inboxChildFolders);
      final inboxFolderIds = {inboxFolderId, ...inboxChildFolders.keys};
      debugPrint(
        '$_tag fetched ${unreadMessages.length} unread items, ${flaggedMessages.length} flagged items, ${folderMap.length} folders, inbox=$inboxFolderId (${stopwatch.elapsedMilliseconds}ms)',
      );

      // Merge and deduplicate by message ID.
      // For unread messages, only include those in Inbox (or Inbox subfolders).
      // Flagged messages are included from all folders.
      final seen = <String>{};
      final allMessages = <dynamic>[];
      for (final m in unreadMessages) {
        final id = m['id'] as String? ?? '';
        final folderId = m['parentFolderId'] as String? ?? '';
        if (inboxFolderIds.contains(folderId) && seen.add(id)) {
          allMessages.add(m);
        }
      }
      for (final m in flaggedMessages) {
        final id = m['id'] as String? ?? '';
        if (seen.add(id)) allMessages.add(m);
      }
      debugPrint(
        '$_tag merged ${allMessages.length} unique items, total time: ${stopwatch.elapsedMilliseconds}ms',
      );

      // Use inbox-filtered count for unread badge
      final inboxUnreadCount = allMessages
          .where((m) => m['isRead'] != true)
          .length;

      return parseSummary(
        {
          'value': allMessages,
          'folderMap': folderMap,
          'inboxFolderId': inboxFolderId,
        },
        unreadCount: inboxUnreadCount,
        flaggedCount: flaggedCount,
      );
    } on SocketException catch (e) {
      debugPrint('$_tag SocketException: $e');
      return NotificationSummary.withError(
        PluginError(
          type: PluginErrorType.network,
          message: 'No internet connection',
        ),
      );
    } catch (e, stack) {
      debugPrint('$_tag unexpected error: $e\n$stack');
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
      // Only root Inbox is flat; subfolders get their own grouping
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
    }).toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return NotificationSummary(
      unreadCount: unreadCount ?? items.where((i) => i.isUnread).length,
      flaggedCount: flaggedCount ?? items.where((i) => i.isFlagged).length,
      items: items,
    );
  }

  /// Fetches messages with the given OData query params, paginating in batches of 50.
  /// Returns a list of raw message JSON objects. Returns empty on any failure.
  Future<List<dynamic>> _fetchMessages(
    String token,
    Map<String, String> queryParams,
  ) async {
    try {
      final allItems = <dynamic>[];
      Uri? nextUri = Uri.https('graph.microsoft.com', '/v1.0/me/messages', {
        ...queryParams,
        r'$top': '50',
      });

      while (nextUri != null) {
        final response = await http
            .get(
              nextUri,
              headers: {
                'Authorization': 'Bearer $token',
                'Accept': 'application/json',
              },
            )
            .timeout(const Duration(seconds: 15));

        if (response.statusCode != 200) {
          debugPrint(
            '$_tag _fetchMessages failed: ${response.statusCode} ${response.body.length > 200 ? response.body.substring(0, 200) : response.body}',
          );
          return allItems;
        }

        final data = json.decode(response.body);
        final items = data['value'] as List<dynamic>? ?? [];
        allItems.addAll(items);
        debugPrint(
          '$_tag _fetchMessages page: ${items.length} items (total ${allItems.length})',
        );

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
      final uri = Uri.https('graph.microsoft.com', '/v1.0/me/mailFolders', {
        r'$select': 'id,displayName',
        r'$top': '50',
      });
      final response = await http
          .get(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));

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
      debugPrint(
        '$_tag _fetchFolderMap OK: ${map.length} folders (${map.values.join(', ')})',
      );
      return map;
    } catch (e) {
      debugPrint('$_tag _fetchFolderMap exception: $e');
      return {};
    }
  }

  /// Fetches child folders of Inbox, returning a map of folderId → displayName.
  Future<Map<String, String>> _fetchInboxChildFolders(String token) async {
    try {
      final uri = Uri.https(
        'graph.microsoft.com',
        '/v1.0/me/mailFolders/Inbox/childFolders',
        {r'$select': 'id,displayName', r'$top': '100'},
      );
      final response = await http
          .get(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint(
          '$_tag _fetchInboxChildFolders failed: ${response.statusCode}',
        );
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
      debugPrint(
        '$_tag _fetchInboxChildFolders OK: ${map.length} child folders (${map.values.join(', ')})',
      );
      return map;
    } catch (e) {
      debugPrint('$_tag _fetchInboxChildFolders exception: $e');
      return {};
    }
  }

  Future<int> _fetchCount(String token, String filter) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              'https://graph.microsoft.com/v1.0/me/messages/\$count?\$filter=$filter',
            ),
            headers: {
              'Authorization': 'Bearer $token',
              'ConsistencyLevel': 'eventual',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 401) {
        debugPrint('$_tag _fetchCount($filter) failed: 401 (token expired)');
        return -1;
      }
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
