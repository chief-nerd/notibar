import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../models/account.dart';
import '../../models/notification_item.dart';
import '../../services/multi_status_item_channel.dart';
import '../plugin_interface.dart';

class FrappePlugin extends NotibarPlugin {
  @override
  ServiceType get serviceType => ServiceType.frappe;

  @override
  String get serviceLabel => 'Frappe / ERPNext';

  @override
  IconData get serviceIcon => Icons.task_alt;

  @override
  Map<String, String> get configFields => {'baseUrl': 'Frappe Base URL'};

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
  ];

  @override
  StatusMenuItem formatMenuEntry(NotificationItem item) {
    var title = item.title;
    if (title.length > 60) title = '${title.substring(0, 57)}...';
    final priority = item.metadata['priority'] as String? ?? '';
    final flagIndicator = item.isFlagged ? '\uD83D\uDEA9 ' : '';
    return StatusMenuItem(
      label: '$flagIndicator$title',
      subtitle: [
        item.subtitle ?? '',
        if (priority.isNotEmpty) '($priority)',
      ].join(' ').trim(),
      hasCallback: item.actionUrl.isNotEmpty,
    );
  }

  @override
  Future<NotificationSummary> fetchNotifications(Account account) async {
    final token = account.apiKey;
    if (token == null || token.isEmpty || !token.contains(':')) {
      return NotificationSummary.withError(
        PluginError(
          type: PluginErrorType.authentication,
          message: 'Frappe API token must be "api_key:api_secret"',
        ),
      );
    }

    final baseUrl = account.config['baseUrl']?.trim().replaceAll(
      RegExp(r'/$'),
      '',
    );
    if (baseUrl == null || baseUrl.isEmpty) {
      return NotificationSummary.withError(
        PluginError(
          type: PluginErrorType.unknown,
          message: 'Frappe Base URL is required',
        ),
      );
    }

    try {
      final authHeader = 'token $token';
      final filters = json.encode([
        ['ToDo', 'status', '=', 'Open'],
      ]);

      final response = await http
          .get(
            Uri.parse(
              '$baseUrl/api/resource/ToDo?filters=$filters&fields=["name","description","owner","modified","priority","reference_type","reference_name"]&order_by=modified desc&limit_page_length=20',
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
            message: 'Frappe authentication failed',
          ),
        );
      }

      if (response.statusCode != 200) {
        return NotificationSummary.withError(
          PluginError(
            type: PluginErrorType.network,
            message: 'Failed to fetch Frappe ToDos: ${response.statusCode}',
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
    final List<dynamic> todos = json['data'] ?? [];

    final items = todos.map((todo) {
      final name = todo['name'] ?? '';
      final description = todo['description'] ?? '(No Description)';
      final priority = todo['priority'] ?? 'Medium';
      final referenceType = todo['reference_type'];
      final referenceName = todo['reference_name'];

      final cleanDescription = description
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .trim();
      final displayDescription = cleanDescription.length > 60
          ? '${cleanDescription.substring(0, 57)}...'
          : cleanDescription;

      DateTime? timestamp;
      try {
        if (todo['modified'] != null) {
          timestamp = DateTime.parse(todo['modified']);
        }
      } catch (_) {}

      final actionUrl = baseUrl != null ? '$baseUrl/app/todo/$name' : '';

      return NotificationItem(
        id: name,
        title: displayDescription.isNotEmpty ? displayDescription : name,
        subtitle: referenceType != null && referenceName != null
            ? '$referenceType: $referenceName'
            : 'ToDo: $name',
        timestamp: timestamp ?? DateTime.now(),
        actionUrl: actionUrl,
        isUnread: true,
        isFlagged: priority == 'High',
        metadata: {
          'name': name,
          'priority': priority,
          'reference_type': referenceType,
          'reference_name': referenceName,
        },
      );
    }).toList();

    return NotificationSummary(
      unreadCount: unreadCount ?? items.length,
      flaggedCount: flaggedCount ?? items.where((i) => i.isFlagged).length,
      items: items,
    );
  }
}
