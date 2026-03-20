import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../bloc/notibar_bloc.dart';
import '../bloc/notibar_state.dart';
import '../bloc/notibar_event.dart';
import '../models/account.dart';
import '../models/notification_item.dart';
import '../plugins/plugin_interface.dart';
import '../services/multi_status_item_channel.dart';

const _tag = '[Tray]';

class TrayManager {
  final MultiStatusItemChannel _channel = MultiStatusItemChannel();
  final NotibarBloc bloc;
  final Map<ServiceType, NotibarPlugin> plugins;
  final VoidCallback? onSettingsPressed;
  StreamSubscription? _subscription;

  /// Track which status item IDs currently exist so we can remove stale ones.
  final Set<String> _activeItemIds = {};

  static const int _maxItemsPerOption = 15;

  /// ID for the persistent "gear" status item with Settings / Exit.
  static const String _controlItemId = '__notibar_control__';

  TrayManager(this.bloc, {required this.plugins, this.onSettingsPressed});

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

      final plugin = plugins[account.serviceType];
      final metricDef = plugin?.metricById(option.metric);

      final itemId = option.id;
      final icon = metricDef?.sfSymbol ?? 'tray.full';

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

      final count = metricDef?.count(summary, option.config) ?? 0;
      if (count == 0) {
        debugPrint('$_tag  ${option.label}: count=0, hiding');
        // Hide item if count is 0 to save space
        continue;
      }

      newItemIds.add(itemId);
      await _channel.update(itemId, '$count', iconName: icon);

      // Build dropdown menu with notification items.
      final filteredItems = metricDef?.filter(summary, option.config) ?? [];
      await _setOptionMenu(itemId, option.accountId, filteredItems, plugin);
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
    NotibarPlugin? plugin,
  ) async {
    final menuItems = <StatusMenuItem>[];
    final callbacks = <int, void Function()>{};

    if (items.isEmpty) {
      menuItems.add(const StatusMenuItem(label: 'No items', enabled: false));
    } else if (items.length <= _maxItemsPerOption) {
      // Flat list for small counts
      for (var i = 0; i < items.length; i++) {
        menuItems.add(_formatItem(plugin, items[i]));
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
        menuItems.add(_formatItem(plugin, inboxToShow[i]));
        if (inboxToShow[i].actionUrl.isNotEmpty) {
          callbacks[i] = () => _launchUrl(inboxToShow[i].actionUrl);
        }
      }
      if (inboxItems.length > _maxItemsPerOption) {
        final overflow = inboxItems.sublist(_maxItemsPerOption);
        final parentIdx = menuItems.length;
        final children = <StatusMenuItem>[];
        for (var ci = 0; ci < overflow.length; ci++) {
          children.add(_formatItem(plugin, overflow[ci]));
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
          children.add(_formatItem(plugin, folderItems[ci]));
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

  StatusMenuItem _formatItem(NotibarPlugin? plugin, NotificationItem item) {
    if (plugin != null) return plugin.formatMenuEntry(item);
    // Fallback for unknown plugin
    var title = item.title;
    if (title.length > 60) title = '${title.substring(0, 57)}...';
    return StatusMenuItem(
      label: title,
      subtitle: item.subtitle,
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

  Future<void> _launchUrl(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}
