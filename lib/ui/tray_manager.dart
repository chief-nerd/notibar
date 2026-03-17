import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../bloc/notibar_bloc.dart';
import '../bloc/notibar_state.dart';
import '../bloc/notibar_event.dart';
import '../models/notification_item.dart';
import '../models/notification_option.dart';
import '../plugins/plugin_interface.dart';
import '../services/multi_status_item_channel.dart';

const _tag = '[Tray]';

class TrayManager {
  final MultiStatusItemChannel _channel = MultiStatusItemChannel();
  final NotibarBloc bloc;
  final VoidCallback? onSettingsPressed;
  StreamSubscription? _subscription;

  /// Track which status item IDs currently exist so we can remove stale ones.
  final Set<String> _activeItemIds = {};

  static const int _maxItemsPerOption = 15;

  /// ID for the persistent "gear" status item with Settings / Exit.
  static const String _controlItemId = '__notibar_control__';

  TrayManager(this.bloc, {this.onSettingsPressed});

  Future<void> init() async {
    debugPrint('$_tag init');
    // Create the rightmost control item with a gear icon.
    try {
      await _channel.create(_controlItemId, '', iconName: 'gearshape');
    } catch (e) {
      debugPrint('$_tag ERROR creating control item: $e');
    }
    _activeItemIds.add(_controlItemId);
    await _updateControlMenu();
    debugPrint('$_tag ready');

    // Wire up menu-click callbacks.
    _channel.onMenuItemClick = _onMenuItemClick;

    _subscription = bloc.stream.listen((state) {
      if (state is NotibarLoaded) {
        _updateTray(state);
      }
    });
  }

  void dispose() {
    _subscription?.cancel();
    _channel.removeAll();
  }

  // ── Menu-click routing ────────────────────────────────────────

  /// Stores callbacks per status-item, indexed by menu-item position.
  final Map<String, Map<int, void Function()>> _menuCallbacks = {};

  void _onMenuItemClick(String itemId, int menuIndex) {
    _menuCallbacks[itemId]?[menuIndex]?.call();
  }

  // ── Control item (Settings / Exit) ────────────────────────────

  Future<void> _updateControlMenu() async {
    final callbacks = <int, void Function()>{};
    final items = <StatusMenuItem>[];

    items.add(StatusMenuItem(label: 'Refresh All', hasCallback: true));
    callbacks[0] = () => bloc.add(RefreshAll());

    items.add(const StatusMenuItem.separator());

    items.add(StatusMenuItem(label: 'Settings...', hasCallback: true));
    callbacks[2] = () => onSettingsPressed?.call();

    items.add(const StatusMenuItem.separator());

    items.add(StatusMenuItem(label: 'Exit', hasCallback: true));
    callbacks[4] = () => exit(0);

    _menuCallbacks[_controlItemId] = callbacks;
    await _channel.setMenu(_controlItemId, items);
  }

  // ── Per-option status items ───────────────────────────────────

  Future<void> _updateTray(NotibarLoaded state) async {
    final newItemIds = <String>{};
    debugPrint(
      '$_tag updating: ${state.options.length} options, ${state.accounts.length} accounts, ${state.summariesByAccountId.length} summaries',
    );

    for (final option in state.options) {
      if (!option.enabled) continue;

      final account = state.accounts
          .where((a) => a.id == option.accountId)
          .firstOrNull;
      final summary = state.summariesByAccountId[option.accountId];
      if (account == null) continue;

      final itemId = option.id;

      final icon = _sfSymbolForMetric(option.metric);

      if (summary == null) {
        newItemIds.add(itemId);
        await _channel.update(itemId, '–', iconName: icon);
        debugPrint('$_tag  ${option.label}: no data yet');
        continue;
      }

      if (summary.error != null) {
        newItemIds.add(itemId);
        await _channel.update(itemId, '⚠', iconName: icon);
        await _setErrorMenu(itemId, summary.error!);
        debugPrint('$_tag  ${option.label}: error — ${summary.error}');
        continue;
      }

      final count = _countForMetric(summary, option.metric, option.config);
      if (count == 0) {
        debugPrint('$_tag  ${option.label}: count=0, hiding');
        // Hide item if count is 0 to save space
        continue;
      }

      newItemIds.add(itemId);
      await _channel.update(itemId, '$count', iconName: icon);

      // Build dropdown menu with notification items.
      final filteredItems = _filterItems(summary, option.metric, option.config);
      await _setOptionMenu(itemId, option.accountId, filteredItems);
      debugPrint(
        '$_tag  ${option.label}: $icon $count (${filteredItems.length} menu items)',
      );
    }

    // Remove status items that are no longer active.
    final staleIds = _activeItemIds
        .difference(newItemIds)
        .where((id) => id != _controlItemId);
    for (final id in staleIds) {
      debugPrint('$_tag removing stale item: $id');
      await _channel.remove(id);
      _menuCallbacks.remove(id);
    }
    _activeItemIds
      ..removeAll(staleIds)
      ..addAll(newItemIds);
  }

  Future<void> _setOptionMenu(
    String itemId,
    String accountId,
    List<NotificationItem> items,
  ) async {
    final menuItems = <StatusMenuItem>[];
    final callbacks = <int, void Function()>{};

    if (items.isEmpty) {
      menuItems.add(const StatusMenuItem(label: 'No items', enabled: false));
    } else if (items.length <= _maxItemsPerOption) {
      // Flat list for small counts
      for (var i = 0; i < items.length; i++) {
        menuItems.add(_buildMenuEntry(items[i]));
        if (items[i].actionUrl.isNotEmpty) {
          callbacks[i] = () => _launchUrl(items[i].actionUrl);
        }
      }
    } else {
      // Group by folder when > 15 items. Inbox stays flat, others go into submenus.
      final inboxItems = <NotificationItem>[];
      final folderGroups = <String, List<NotificationItem>>{};

      for (final item in items) {
        final folder = (item.metadata['folder'] as String?) ?? '';
        final isInbox = item.metadata['isInbox'] == true;
        if (isInbox || folder.isEmpty) {
          inboxItems.add(item);
        } else {
          folderGroups.putIfAbsent(folder, () => []).add(item);
        }
      }

      // Inbox items flat (capped), overflow into a "more" submenu
      final inboxToShow = inboxItems.take(_maxItemsPerOption).toList();
      for (var i = 0; i < inboxToShow.length; i++) {
        menuItems.add(_buildMenuEntry(inboxToShow[i]));
        if (inboxToShow[i].actionUrl.isNotEmpty) {
          callbacks[i] = () => _launchUrl(inboxToShow[i].actionUrl);
        }
      }
      if (inboxItems.length > _maxItemsPerOption) {
        final overflow = inboxItems.sublist(_maxItemsPerOption);
        final parentIdx = menuItems.length;
        final children = <StatusMenuItem>[];
        for (var ci = 0; ci < overflow.length; ci++) {
          children.add(_buildMenuEntry(overflow[ci]));
          if (overflow[ci].actionUrl.isNotEmpty) {
            callbacks[parentIdx * 1000 + ci] = () =>
                _launchUrl(overflow[ci].actionUrl);
          }
        }
        menuItems.add(
          StatusMenuItem(
            label: '${overflow.length} more in Inbox...',
            children: children,
          ),
        );
      }

      // Folder submenus
      final sortedFolders = folderGroups.keys.toList()..sort();
      for (final folder in sortedFolders) {
        final folderItems = folderGroups[folder]!;
        menuItems.add(const StatusMenuItem.separator());

        // Parent index for this folder header
        final parentIdx = menuItems.length;
        final children = <StatusMenuItem>[];
        for (var ci = 0; ci < folderItems.length; ci++) {
          children.add(_buildMenuEntry(folderItems[ci]));
          if (folderItems[ci].actionUrl.isNotEmpty) {
            // Composite index: parentIdx * 1000 + childIndex
            callbacks[parentIdx * 1000 + ci] = () =>
                _launchUrl(folderItems[ci].actionUrl);
          }
        }

        menuItems.add(
          StatusMenuItem(
            label: '$folder (${folderItems.length})',
            children: children,
          ),
        );
      }
    }

    // Add a "Refresh" action at the bottom of every option menu
    menuItems.add(const StatusMenuItem.separator());
    final refreshIdx = menuItems.length;
    menuItems.add(StatusMenuItem(label: 'Refresh', hasCallback: true));
    callbacks[refreshIdx] = () => bloc.add(RefreshAccount(accountId));

    _menuCallbacks[itemId] = callbacks;
    await _channel.setMenu(itemId, menuItems);
  }

  StatusMenuItem _buildMenuEntry(NotificationItem item) {
    final type = item.metadata['type'] as String?;
    final source = item.metadata['source'] as String?;

    // Planner items: line 1 = task title, line 2 = bucket + status
    if (source == 'planner') {
      var title = item.title;
      if (title.length > 60) title = '${title.substring(0, 57)}...';
      final status = item.metadata['status'] as String? ?? '';
      final bucket = item.metadata['bucketName'] as String? ?? '';
      final statusIcon = switch (status) {
        'completed' => '✅',
        'inProgress' => '🔄',
        _ => '⬚',
      };
      final parts = [statusIcon, title];
      final line1 = parts.join(' ');
      final line2 = bucket.isNotEmpty ? bucket : null;

      return StatusMenuItem(
        label: line1,
        subtitle: line2,
        hasCallback: item.actionUrl.isNotEmpty,
      );
    }

    // GitHub items: line 1 = #number title, line 2 = repo + labels
    if (type == 'Issue' || type == 'PullRequest') {
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

    // Default (Outlook, etc.): indicators + sender — subject
    final indicators = [
      if (item.isUnread) '●',
      if (item.isFlagged) '🚩',
    ].join(' ');
    final sender = item.subtitle ?? '';
    var subject = item.title;
    if (subject.length > 50) subject = '${subject.substring(0, 47)}...';
    final line1 = [
      if (indicators.isNotEmpty) indicators,
      if (sender.isNotEmpty) '$sender —',
      subject,
    ].join(' ');

    // Line 2: body preview
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

  Future<void> _setErrorMenu(String itemId, PluginError error) async {
    _menuCallbacks.remove(itemId);
    await _channel.setMenu(itemId, [
      StatusMenuItem(label: error.message, enabled: false),
    ]);
  }

  // ── Helpers ───────────────────────────────────────────────────

  /// Returns an SF Symbol name for the given metric.
  /// Browse available symbols at https://developer.apple.com/sf-symbols/
  String _sfSymbolForMetric(DisplayMetric metric) {
    switch (metric) {
      case DisplayMetric.unread:
        return 'envelope.badge';
      case DisplayMetric.flagged:
        return 'flag';
      case DisplayMetric.mentions:
        return 'tag';
      case DisplayMetric.assignedIssues:
        return 'ticket';
      case DisplayMetric.assignedPRs:
        return 'arrow.trianglehead.pull';
      case DisplayMetric.reviewRequests:
        return 'eye';
      case DisplayMetric.plannerAssigned:
        return 'person.badge.plus';
      case DisplayMetric.plannerBucket:
        return 'tray.2';
      case DisplayMetric.plannerOpen:
        return 'paperplane.circle';
      case DisplayMetric.plannerInProgress:
        return 'arrow.trianglehead.2.clockwise.rotate.90.circle';
      case DisplayMetric.plannerCompleted:
        return 'checkmark.circle';
      case DisplayMetric.all:
        return 'tray.full';
    }
  }

  int _countForMetric(
    NotificationSummary summary,
    DisplayMetric metric, [
    Map<String, String> config = const {},
  ]) {
    switch (metric) {
      case DisplayMetric.unread:
        return summary.unreadCount;
      case DisplayMetric.flagged:
        return summary.flaggedCount;
      case DisplayMetric.mentions:
        return summary.mentionCount;
      case DisplayMetric.assignedIssues:
        return summary.assignedIssuesCount;
      case DisplayMetric.assignedPRs:
        return summary.assignedPRsCount;
      case DisplayMetric.reviewRequests:
        return summary.reviewRequestsCount;
      case DisplayMetric.plannerAssigned:
        return summary.items
            .where(
              (i) =>
                  i.metadata['source'] == 'planner' &&
                  i.metadata['status'] != 'completed',
            )
            .length;
      case DisplayMetric.plannerBucket:
        // Bucket filtering is handled via option.config['bucketId']
        final bucketId = config['bucketId'] ?? '';
        return summary.items
            .where(
              (i) =>
                  i.metadata['source'] == 'planner' &&
                  i.metadata['status'] != 'completed' &&
                  (bucketId.isEmpty || i.metadata['bucketId'] == bucketId),
            )
            .length;
      case DisplayMetric.plannerOpen:
        return summary.items
            .where(
              (i) =>
                  i.metadata['source'] == 'planner' &&
                  i.metadata['status'] == 'open',
            )
            .length;
      case DisplayMetric.plannerInProgress:
        return summary.items
            .where(
              (i) =>
                  i.metadata['source'] == 'planner' &&
                  i.metadata['status'] == 'inProgress',
            )
            .length;
      case DisplayMetric.plannerCompleted:
        return summary.items
            .where(
              (i) =>
                  i.metadata['source'] == 'planner' &&
                  i.metadata['status'] == 'completed',
            )
            .length;
      case DisplayMetric.all:
        return summary.items.length;
    }
  }

  List<NotificationItem> _filterItems(
    NotificationSummary summary,
    DisplayMetric metric, [
    Map<String, String> config = const {},
  ]) {
    switch (metric) {
      case DisplayMetric.unread:
        return summary.items.where((i) => i.isUnread).toList();
      case DisplayMetric.flagged:
        return summary.items.where((i) => i.isFlagged).toList();
      case DisplayMetric.mentions:
        // We use isFlagged as a general "urgent/mention" marker in the item model
        return summary.items.where((i) => i.isFlagged).toList();
      case DisplayMetric.assignedIssues:
        return summary.items
            .where((i) => i.metadata['type'] == 'Issue')
            .toList();
      case DisplayMetric.assignedPRs:
        return summary.items
            .where(
              (i) =>
                  i.metadata['type'] == 'PullRequest' &&
                  i.metadata['reason'] != 'review_requested',
            )
            .toList();
      case DisplayMetric.reviewRequests:
        return summary.items
            .where(
              (i) =>
                  i.metadata['type'] == 'PullRequest' &&
                  i.metadata['reason'] == 'review_requested',
            )
            .toList();
      case DisplayMetric.plannerAssigned:
        return summary.items
            .where(
              (i) =>
                  i.metadata['source'] == 'planner' &&
                  i.metadata['status'] != 'completed',
            )
            .toList();
      case DisplayMetric.plannerBucket:
        final bucketId = config['bucketId'] ?? '';
        return summary.items
            .where(
              (i) =>
                  i.metadata['source'] == 'planner' &&
                  i.metadata['status'] != 'completed' &&
                  (bucketId.isEmpty || i.metadata['bucketId'] == bucketId),
            )
            .toList();
      case DisplayMetric.plannerOpen:
        return summary.items
            .where(
              (i) =>
                  i.metadata['source'] == 'planner' &&
                  i.metadata['status'] == 'open',
            )
            .toList();
      case DisplayMetric.plannerInProgress:
        return summary.items
            .where(
              (i) =>
                  i.metadata['source'] == 'planner' &&
                  i.metadata['status'] == 'inProgress',
            )
            .toList();
      case DisplayMetric.plannerCompleted:
        return summary.items
            .where(
              (i) =>
                  i.metadata['source'] == 'planner' &&
                  i.metadata['status'] == 'completed',
            )
            .toList();
      case DisplayMetric.all:
        return summary.items;
    }
  }

  Future<void> _launchUrl(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}
