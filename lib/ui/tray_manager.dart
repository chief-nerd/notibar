import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../bloc/notibar_bloc.dart';
import '../bloc/notibar_state.dart';
import '../bloc/notibar_event.dart';
import '../models/notification_item.dart';
import '../models/notification_option.dart';
import '../plugins/plugin_interface.dart';
import '../services/multi_status_item_channel.dart';

class TrayManager {
  final MultiStatusItemChannel _channel = MultiStatusItemChannel();
  final NotibarBloc bloc;
  final VoidCallback? onSettingsPressed;
  StreamSubscription? _subscription;

  /// Track which status item IDs currently exist so we can remove stale ones.
  final Set<String> _activeItemIds = {};

  static const int _maxItemsPerOption = 7;

  /// ID for the persistent "gear" status item with Settings / Exit.
  static const String _controlItemId = '__notibar_control__';

  TrayManager(this.bloc, {this.onSettingsPressed});

  Future<void> init() async {
    debugPrint('[TrayManager] init() called');
    // Create the rightmost control item with a gear icon.
    try {
      await _channel.create(_controlItemId, '', iconName: 'gearshape');
      debugPrint('[TrayManager] control item created');
    } catch (e) {
      debugPrint('[TrayManager] ERROR creating control item: $e');
    }
    _activeItemIds.add(_controlItemId);
    await _updateControlMenu();
    debugPrint('[TrayManager] control menu set');

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

    for (final option in state.options) {
      if (!option.enabled) continue;

      final account = state.accounts
          .where((a) => a.id == option.accountId)
          .firstOrNull;
      final summary = state.summariesByAccountId[option.accountId];
      if (account == null) continue;

      final itemId = option.id;

      final icon = _emojiForMetric(option.metric);

      if (summary == null) {
        newItemIds.add(itemId);
        await _channel.update(itemId, '$icon –');
        continue;
      }

      if (summary.error != null) {
        newItemIds.add(itemId);
        await _channel.update(itemId, '$icon ⚠');
        await _setErrorMenu(itemId, summary.error!);
        continue;
      }

      final count = _countForMetric(summary, option.metric);
      if (count == 0) {
        // Hide item if count is 0 to save space
        continue;
      }

      newItemIds.add(itemId);
      await _channel.update(itemId, '$icon $count');

      // Build dropdown menu with notification items.
      final filteredItems = _filterItems(summary, option.metric);
      await _setOptionMenu(itemId, filteredItems);
    }

    // Remove status items that are no longer active.
    final staleIds = _activeItemIds
        .difference(newItemIds)
        .where((id) => id != _controlItemId);
    for (final id in staleIds) {
      await _channel.remove(id);
      _menuCallbacks.remove(id);
    }
    _activeItemIds
      ..removeAll(staleIds)
      ..addAll(newItemIds);
  }

  Future<void> _setOptionMenu(
    String itemId,
    List<NotificationItem> items,
  ) async {
    final menuItems = <StatusMenuItem>[];
    final callbacks = <int, void Function()>{};

    if (items.isEmpty) {
      menuItems.add(const StatusMenuItem(label: 'No items', enabled: false));
    } else {
      final toShow = items.take(_maxItemsPerOption).toList();
      for (var i = 0; i < toShow.length; i++) {
        final item = toShow[i];
        final prefix = item.isUnread ? '● ' : '';
        final flagged = item.isFlagged ? '🚩 ' : '';
        var title = item.title;
        if (title.length > 40) title = '${title.substring(0, 37)}...';

        menuItems.add(
          StatusMenuItem(
            label: '$prefix$flagged$title',
            hasCallback: item.actionUrl.isNotEmpty,
          ),
        );
        if (item.actionUrl.isNotEmpty) {
          callbacks[i] = () => _launchUrl(item.actionUrl);
        }
      }
      if (items.length > _maxItemsPerOption) {
        menuItems.add(const StatusMenuItem.separator());
        menuItems.add(
          StatusMenuItem(
            label: '${items.length - _maxItemsPerOption} more...',
            enabled: false,
          ),
        );
      }
    }

    _menuCallbacks[itemId] = callbacks;
    await _channel.setMenu(itemId, menuItems);
  }

  Future<void> _setErrorMenu(String itemId, PluginError error) async {
    _menuCallbacks.remove(itemId);
    await _channel.setMenu(itemId, [
      StatusMenuItem(label: error.message, enabled: false),
    ]);
  }

  // ── Helpers ───────────────────────────────────────────────────

  String _emojiForMetric(DisplayMetric metric) {
    switch (metric) {
      case DisplayMetric.unread:
        return '📧';
      case DisplayMetric.flagged:
        return '🚩';
      case DisplayMetric.mentions:
        return '@';
      case DisplayMetric.assignedIssues:
        return '🎫';
      case DisplayMetric.assignedPRs:
        return '⤴️';
      case DisplayMetric.reviewRequests:
        return '👀';
      case DisplayMetric.all:
        return '📬';
    }
  }

  int _countForMetric(NotificationSummary summary, DisplayMetric metric) {
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
      case DisplayMetric.all:
        return summary.items.length;
    }
  }

  List<NotificationItem> _filterItems(
    NotificationSummary summary,
    DisplayMetric metric,
  ) {
    switch (metric) {
      case DisplayMetric.unread:
        return summary.items.where((i) => i.isUnread).toList();
      case DisplayMetric.flagged:
        return summary.items.where((i) => i.isFlagged).toList();
      case DisplayMetric.mentions:
        // We use isFlagged as a general "urgent/mention" marker in the item model
        return summary.items.where((i) => i.isFlagged).toList();
      case DisplayMetric.assignedIssues:
        // For GitHub/Jira, we can filter by specific markers if added to NotificationItem,
        // but for now, we'll return all relevant items if they were counted.
        return summary.items;
      case DisplayMetric.assignedPRs:
        return summary.items;
      case DisplayMetric.reviewRequests:
        return summary.items;
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
