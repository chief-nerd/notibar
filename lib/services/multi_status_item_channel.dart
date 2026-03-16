import 'package:flutter/services.dart';

/// Represents a single menu entry for a status item's dropdown.
class StatusMenuItem {
  final String label;
  final String? subtitle;
  final bool enabled;
  final bool isSeparator;
  final bool hasCallback;
  final List<StatusMenuItem>? children;

  const StatusMenuItem({
    this.label = '',
    this.subtitle,
    this.enabled = true,
    this.isSeparator = false,
    this.hasCallback = false,
    this.children,
  });

  const StatusMenuItem.separator()
    : label = '',
      subtitle = null,
      enabled = false,
      isSeparator = true,
      hasCallback = false,
      children = null;

  Map<String, dynamic> toMap() => {
    'label': label,
    if (subtitle != null) 'subtitle': subtitle,
    'enabled': enabled,
    'type': isSeparator ? 'separator' : 'item',
    'hasCallback': hasCallback,
    if (children != null) 'children': children!.map((c) => c.toMap()).toList(),
  };
}

/// Dart wrapper around the native MultiStatusItemPlugin.
/// Creates and manages multiple independent macOS menu bar status items.
class MultiStatusItemChannel {
  static const _channel = MethodChannel('notibar/multi_status_item');

  /// Callback when a menu item with a callback is clicked.
  /// Receives the status item ID and the menu item index.
  void Function(String itemId, int menuIndex)? onMenuItemClick;

  /// Callback when a status item itself is clicked (no menu set).
  void Function(String itemId)? onStatusItemClick;

  MultiStatusItemChannel() {
    _channel.setMethodCallHandler(_handleMethod);
  }

  Future<void> _handleMethod(MethodCall call) async {
    final args = call.arguments as Map<Object?, Object?>;
    switch (call.method) {
      case 'onMenuItemClick':
        final itemId = args['itemId'] as String;
        final menuIndex = args['menuIndex'] as int;
        onMenuItemClick?.call(itemId, menuIndex);
        break;
      case 'onStatusItemClick':
        final itemId = args['itemId'] as String;
        onStatusItemClick?.call(itemId);
        break;
    }
  }

  /// Create a new status item in the menu bar.
  Future<void> create(String id, String title, {String? iconName}) async {
    await _channel.invokeMethod('create', {
      'id': id,
      'title': title,
      'iconName': iconName,
    });
  }

  /// Update the title of an existing status item (creates if missing).
  Future<void> update(String id, String title, {String? iconName}) async {
    await _channel.invokeMethod('update', {
      'id': id,
      'title': title,
      'iconName': iconName,
    });
  }

  /// Remove a status item from the menu bar.
  Future<void> remove(String id) async {
    await _channel.invokeMethod('remove', {'id': id});
  }

  /// Set the dropdown menu for a status item.
  Future<void> setMenu(String id, List<StatusMenuItem> items) async {
    await _channel.invokeMethod('setMenu', {
      'id': id,
      'items': items.map((i) => i.toMap()).toList(),
    });
  }

  /// Remove all status items.
  Future<void> removeAll() async {
    await _channel.invokeMethod('removeAll');
  }
}
