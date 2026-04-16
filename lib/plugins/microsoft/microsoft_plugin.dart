import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../models/account.dart';
import '../../models/notification_item.dart';
import '../../services/multi_status_item_channel.dart';
import '../../services/outlook_auth_service.dart';
import '../plugin_interface.dart';

const _tag = '[Microsoft]';

class MicrosoftPlugin extends NotibarPlugin {
  @override
  ServiceType get serviceType => ServiceType.microsoft;

  @override
  String get serviceLabel => 'Microsoft 365';

  @override
  IconData get serviceIcon => Icons.window;

  @override
  Map<String, String> get configFields => {
    'clientId': 'Azure App Client ID',
    'tenantId': 'Tenant ID (or "common")',
  };

  @override
  List<MetricDefinition> get supportedMetrics => [
    MetricDefinition(
      id: 'unread',
      label: 'Unread',
      sfSymbol: 'envelope.badge',
      materialIcon: Icons.mark_email_unread_outlined,
      count: (s, _) => s.unreadCount,
      filter: (s, _) => s.items.where((i) => i.isUnread).toList(),
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
      id: 'plannerAssigned',
      label: 'Planner: My Tasks',
      sfSymbol: 'person.badge.plus',
      materialIcon: Icons.person_outline,
      count: (s, _) => s.items
          .where(
            (i) =>
                i.metadata['source'] == 'planner' &&
                i.metadata['status'] != 'completed',
          )
          .length,
      filter: (s, _) => s.items
          .where(
            (i) =>
                i.metadata['source'] == 'planner' &&
                i.metadata['status'] != 'completed',
          )
          .toList(),
    ),
    MetricDefinition(
      id: 'plannerBucket',
      label: 'Planner: Bucket',
      sfSymbol: 'tray.2',
      materialIcon: Icons.view_column_outlined,
      count: (s, config) {
        final bucketId = config['bucketId'] ?? '';
        return s.items
            .where(
              (i) =>
                  i.metadata['source'] == 'planner' &&
                  i.metadata['status'] != 'completed' &&
                  (bucketId.isEmpty || i.metadata['bucketId'] == bucketId),
            )
            .length;
      },
      filter: (s, config) {
        final bucketId = config['bucketId'] ?? '';
        return s.items
            .where(
              (i) =>
                  i.metadata['source'] == 'planner' &&
                  i.metadata['status'] != 'completed' &&
                  (bucketId.isEmpty || i.metadata['bucketId'] == bucketId),
            )
            .toList();
      },
    ),
    MetricDefinition(
      id: 'plannerOpen',
      label: 'Planner: Open',
      sfSymbol: 'paperplane.circle',
      materialIcon: Icons.radio_button_unchecked,
      count: (s, _) => s.items
          .where(
            (i) =>
                i.metadata['source'] == 'planner' &&
                i.metadata['status'] == 'open',
          )
          .length,
      filter: (s, _) => s.items
          .where(
            (i) =>
                i.metadata['source'] == 'planner' &&
                i.metadata['status'] == 'open',
          )
          .toList(),
    ),
    MetricDefinition(
      id: 'plannerInProgress',
      label: 'Planner: In Progress',
      sfSymbol: 'arrow.trianglehead.2.clockwise.rotate.90.circle',
      materialIcon: Icons.pending_outlined,
      count: (s, _) => s.items
          .where(
            (i) =>
                i.metadata['source'] == 'planner' &&
                i.metadata['status'] == 'inProgress',
          )
          .length,
      filter: (s, _) => s.items
          .where(
            (i) =>
                i.metadata['source'] == 'planner' &&
                i.metadata['status'] == 'inProgress',
          )
          .toList(),
    ),
    MetricDefinition(
      id: 'plannerCompleted',
      label: 'Planner: Completed',
      sfSymbol: 'checkmark.circle',
      materialIcon: Icons.check_circle_outline,
      count: (s, _) => s.items
          .where(
            (i) =>
                i.metadata['source'] == 'planner' &&
                i.metadata['status'] == 'completed',
          )
          .length,
      filter: (s, _) => s.items
          .where(
            (i) =>
                i.metadata['source'] == 'planner' &&
                i.metadata['status'] == 'completed',
          )
          .toList(),
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
  String? webUrl(Account account, String metricId, Map<String, String> config) {
    switch (metricId) {
      case 'unread':
        return 'https://outlook.office.com/mail/inbox';
      case 'flagged':
        return 'https://outlook.office.com/mail/?isFlagged=true';
      case 'plannerAssigned':
      case 'plannerBucket':
      case 'plannerOpen':
      case 'plannerInProgress':
      case 'plannerCompleted':
        return 'https://tasks.office.com/';
      case 'all':
        return 'https://outlook.office.com/mail/';
      default:
        return null;
    }
  }

  @override
  StatusMenuItem formatMenuEntry(NotificationItem item) {
    final source = item.metadata['source'] as String?;

    // Planner items: line 1 = status icon + task title, line 2 = bucket
    if (source == 'planner') {
      var title = item.title;
      if (title.length > 60) title = '${title.substring(0, 57)}...';
      final status = item.metadata['status'] as String? ?? '';
      final bucket = item.metadata['bucketName'] as String? ?? '';
      final statusIcon = switch (status) {
        'completed' => '\u2705',
        'inProgress' => '\uD83D\uDD04',
        _ => '\u2B1C',
      };
      return StatusMenuItem(
        label: '$statusIcon $title',
        subtitle: bucket.isNotEmpty ? bucket : null,
        hasCallback: item.actionUrl.isNotEmpty,
      );
    }

    // Outlook mail: indicators + sender — subject, body preview
    final indicators = [
      if (item.isUnread) '\u25CF',
      if (item.isFlagged) '\uD83D\uDEA9',
    ].join(' ');
    final sender = item.subtitle ?? '';
    var subject = item.title;
    if (subject.length > 50) subject = '${subject.substring(0, 47)}...';
    final line1 = [
      if (indicators.isNotEmpty) indicators,
      if (sender.isNotEmpty) '$sender \u2014',
      subject,
    ].join(' ');

    String? line2;
    if (item.body != null && item.body!.isNotEmpty) {
      var preview = item.body!.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (preview.length > 80) preview = '${preview.substring(0, 77)}...';
      line2 = preview;
    }

    return StatusMenuItem(
      label: line1,
      subtitle: line2,
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
          message: 'Microsoft API token is missing',
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

      // Fetch Planner tasks if a plan is configured
      final planId = account.config['planId'];
      List<dynamic> plannerTasks = [];
      Map<String, String> bucketMap = {};
      if (planId != null && planId.isNotEmpty) {
        final plannerResults = await Future.wait([
          _fetchPlannerTasks(token, planId),
          _fetchPlannerBuckets(token, planId),
        ]);
        plannerTasks = plannerResults[0] as List<dynamic>;
        bucketMap = plannerResults[1] as Map<String, String>;
        debugPrint(
          '$_tag fetched ${plannerTasks.length} planner tasks, ${bucketMap.length} buckets (${stopwatch.elapsedMilliseconds}ms)',
        );
      }

      return parseSummary(
        {
          'value': allMessages,
          'folderMap': folderMap,
          'inboxFolderId': inboxFolderId,
          'plannerTasks': plannerTasks,
          'bucketMap': bucketMap,
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
    } on http.ClientException catch (e) {
      debugPrint('$_tag ClientException: $e');
      return NotificationSummary.withError(
        PluginError(
          type: PluginErrorType.network,
          message: 'No internet connection',
        ),
      );
    } on TimeoutException catch (e) {
      debugPrint('$_tag TimeoutException: $e');
      return NotificationSummary.withError(
        PluginError(
          type: PluginErrorType.network,
          message: 'Request timed out',
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
    final List<dynamic> plannerTasks = json['plannerTasks'] ?? [];
    final bucketMap = (json['bucketMap'] as Map<String, String>?) ?? {};

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

    // Parse Planner tasks
    final taskItems = plannerTasks.map((t) {
      final title = t['title'] as String? ?? '(No Title)';
      final bucketId = t['bucketId'] as String? ?? '';
      final bucketName = bucketMap[bucketId] ?? '';
      final percentComplete = t['percentComplete'] as int? ?? 0;

      String status;
      if (percentComplete == 100) {
        status = 'completed';
      } else if (percentComplete > 0) {
        status = 'inProgress';
      } else {
        status = 'open';
      }

      DateTime? dueDate;
      try {
        if (t['dueDateTime'] != null) {
          dueDate = DateTime.parse(t['dueDateTime']);
        }
      } catch (_) {}

      DateTime? createdDate;
      try {
        if (t['createdDateTime'] != null) {
          createdDate = DateTime.parse(t['createdDateTime']);
        }
      } catch (_) {}

      final assignments = t['assignments'] as Map<String, dynamic>? ?? {};
      final assigneeCount = assignments.length;

      // Build a web link to the task in Planner
      final taskId = t['id'] as String? ?? '';

      return NotificationItem(
        id: 'planner_$taskId',
        title: title,
        subtitle: bucketName.isNotEmpty ? bucketName : null,
        timestamp: dueDate ?? createdDate ?? DateTime.now(),
        actionUrl: 'https://tasks.office.com',
        isUnread: status != 'completed',
        isFlagged:
            dueDate != null &&
            dueDate.isBefore(DateTime.now()) &&
            status != 'completed',
        metadata: {
          'source': 'planner',
          'taskId': taskId,
          'bucketId': bucketId,
          'bucketName': bucketName,
          'status': status,
          'percentComplete': percentComplete,
          'assigneeCount': assigneeCount,
          'priority': t['priority'] ?? 1,
        },
      );
    }).toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final allItems = [...items, ...taskItems];

    return NotificationSummary(
      unreadCount: unreadCount ?? items.where((i) => i.isUnread).length,
      flaggedCount: flaggedCount ?? items.where((i) => i.isFlagged).length,
      items: allItems,
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
    } on SocketException {
      rethrow;
    } on http.ClientException {
      rethrow;
    } on TimeoutException {
      rethrow;
    } catch (e) {
      debugPrint('$_tag _fetchCount($filter) exception: $e');
      return 0;
    }
  }

  // ── Planner API ─────────────────────────────────────────────

  /// Fetches all tasks for the given Planner plan.
  Future<List<dynamic>> _fetchPlannerTasks(String token, String planId) async {
    try {
      final allTasks = <dynamic>[];
      Uri? nextUri = Uri.https(
        'graph.microsoft.com',
        '/v1.0/planner/plans/$planId/tasks',
        {r'$top': '50'},
      );

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
          debugPrint('$_tag _fetchPlannerTasks failed: ${response.statusCode}');
          return allTasks;
        }

        final data = json.decode(response.body);
        final tasks = data['value'] as List<dynamic>? ?? [];
        allTasks.addAll(tasks);

        final nextLink = data['@odata.nextLink'] as String?;
        nextUri = nextLink != null ? Uri.parse(nextLink) : null;
      }

      debugPrint('$_tag _fetchPlannerTasks OK: ${allTasks.length} tasks');
      return allTasks;
    } catch (e) {
      debugPrint('$_tag _fetchPlannerTasks exception: $e');
      return [];
    }
  }

  /// Fetches all buckets for a plan, returning a map of bucketId → name.
  Future<Map<String, String>> _fetchPlannerBuckets(
    String token,
    String planId,
  ) async {
    try {
      final uri = Uri.https(
        'graph.microsoft.com',
        '/v1.0/planner/plans/$planId/buckets',
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
        debugPrint('$_tag _fetchPlannerBuckets failed: ${response.statusCode}');
        return {};
      }

      final data = json.decode(response.body);
      final buckets = data['value'] as List<dynamic>? ?? [];
      final map = <String, String>{};
      for (final b in buckets) {
        final id = b['id'] as String?;
        final name = b['name'] as String?;
        if (id != null && name != null) map[id] = name;
      }
      debugPrint(
        '$_tag _fetchPlannerBuckets OK: ${map.length} buckets (${map.values.join(', ')})',
      );
      return map;
    } catch (e) {
      debugPrint('$_tag _fetchPlannerBuckets exception: $e');
      return {};
    }
  }

  /// Fetches all plans accessible to the user (via their groups).
  /// Returns a list of {id, title, groupName} maps.
  static Future<List<Map<String, String>>> fetchAvailablePlans(
    String token,
  ) async {
    try {
      // Get user's groups
      final groupsUri = Uri.https(
        'graph.microsoft.com',
        '/v1.0/me/memberOf/microsoft.graph.group',
        {r'$select': 'id,displayName', r'$top': '100'},
      );
      final groupsResponse = await http
          .get(
            groupsUri,
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (groupsResponse.statusCode != 200) {
        debugPrint(
          '$_tag fetchAvailablePlans groups failed: ${groupsResponse.statusCode}',
        );
        return [];
      }

      final groupsData = json.decode(groupsResponse.body);
      final groups = groupsData['value'] as List<dynamic>? ?? [];

      // Fetch plans for each group (in sequence to avoid 429 throttling)
      final plans = <Map<String, String>>[];
      for (final group in groups) {
        final groupId = group['id'] as String? ?? '';
        final groupName = group['displayName'] as String? ?? '';
        if (groupId.isEmpty) continue;

        final plansUri = Uri.https(
          'graph.microsoft.com',
          '/v1.0/groups/$groupId/planner/plans',
          {r'$select': 'id,title'},
        );
        final plansResponse = await http
            .get(
              plansUri,
              headers: {
                'Authorization': 'Bearer $token',
                'Accept': 'application/json',
              },
            )
            .timeout(const Duration(seconds: 10));

        if (plansResponse.statusCode == 200) {
          final plansData = json.decode(plansResponse.body);
          final groupPlans = plansData['value'] as List<dynamic>? ?? [];
          for (final p in groupPlans) {
            plans.add({
              'id': p['id'] as String? ?? '',
              'title': p['title'] as String? ?? '',
              'groupName': groupName,
            });
          }
        }
      }

      debugPrint('$_tag fetchAvailablePlans OK: ${plans.length} plans');
      return plans;
    } catch (e) {
      debugPrint('$_tag fetchAvailablePlans exception: $e');
      return [];
    }
  }

  /// Fetches buckets for a given plan. Used by UI for bucket selection.
  static Future<List<Map<String, String>>> fetchBucketsForPlan(
    String token,
    String planId,
  ) async {
    try {
      final uri = Uri.https(
        'graph.microsoft.com',
        '/v1.0/planner/plans/$planId/buckets',
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

      if (response.statusCode != 200) return [];

      final data = json.decode(response.body);
      final buckets = data['value'] as List<dynamic>? ?? [];
      return buckets
          .map(
            (b) => {
              'id': b['id'] as String? ?? '',
              'name': b['name'] as String? ?? '',
            },
          )
          .toList();
    } catch (e) {
      debugPrint('$_tag fetchBucketsForPlan exception: $e');
      return [];
    }
  }
}
