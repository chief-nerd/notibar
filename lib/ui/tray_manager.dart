import 'dart:async';
import 'dart:io';
import 'package:system_tray/system_tray.dart';
import 'package:url_launcher/url_launcher.dart';
import '../bloc/notibar_bloc.dart';
import '../bloc/notibar_state.dart';
import '../bloc/notibar_event.dart';
import '../plugins/plugin_interface.dart';

class TrayManager {
  final SystemTray _systemTray = SystemTray();
  final Menu _menu = Menu();
  final NotibarBloc bloc;
  StreamSubscription? _subscription;
  
  // Constant limits
  static const int _maxItemsPerAccount = 7;

  TrayManager(this.bloc);

  Future<void> init() async {
    await _systemTray.initSystemTray(
      title: "Notibar",
      iconPath: "assets/app_icon.png", // In a real app, use multi-resolution/theme icons
    );

    _systemTray.registerSystemTrayEventHandler((eventName) {
      if (eventName == "click") {
        _systemTray.popUpContextMenu();
      }
    });

    _subscription = bloc.stream.listen((state) {
      if (state is NotibarLoaded) {
        _updateTray(state);
      }
    });
  }

  void dispose() {
    _subscription?.cancel();
  }

  Future<void> _updateTray(NotibarLoaded state) async {
    int totalUnread = 0;
    int totalFlagged = 0;
    
    for (var summary in state.summariesByAccountId.values) {
      totalUnread += summary.unreadCount;
      totalFlagged += summary.flaggedCount;
    }

    // Update title with indicator icons
    await _systemTray.setTitle("📧 $totalUnread | 🚩 $totalFlagged");

    // Efficiently build menu items
    final List<MenuItemBase> menuItems = [
      MenuItemLabel(label: 'Refresh All', onClicked: (_) => bloc.add(RefreshAll())),
      MenuSeparator(),
    ];

    for (var account in state.accounts) {
      final summary = state.summariesByAccountId[account.id];
      if (summary == null) continue;

      final accountLabel = summary.error != null 
          ? "${account.name} (⚠️ Error)" 
          : account.name;
          
      menuItems.add(MenuItemLabel(label: accountLabel, enabled: false));
      
      if (summary.error != null) {
        menuItems.add(MenuItemLabel(label: "  Error: ${summary.error!.message}", enabled: false));
      } else if (summary.items.isEmpty) {
        menuItems.add(MenuItemLabel(label: "  No notifications", enabled: false));
      } else {
        // Limit items to prevent massive menus
        final itemsToShow = summary.items.take(_maxItemsPerAccount).toList();
        for (var item in itemsToShow) {
          final prefix = item.isUnread ? "• " : "  ";
          final flaggedIcon = item.isFlagged ? "🚩 " : "";
          
          // Truncate title if too long
          String title = item.title;
          if (title.length > 40) {
            title = "${title.substring(0, 37)}...";
          }

          menuItems.add(MenuItemLabel(
            label: "$prefix$flaggedIcon$title (${item.subtitle})",
            onClicked: (_) => _launchUrl(item.actionUrl),
          ));
        }
        
        if (summary.items.length > _maxItemsPerAccount) {
          menuItems.add(MenuItemLabel(
            label: "  ... and ${summary.items.length - _maxItemsPerAccount} more",
            enabled: false,
          ));
        }
      }
      menuItems.add(MenuSeparator());
    }

    menuItems.add(MenuItemLabel(label: 'Exit', onClicked: (_) => exit(0)));

    await _menu.buildFrom(menuItems);
    await _systemTray.setContextMenu(_menu);
  }

  Future<void> _launchUrl(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}
