# Custom Plugin Guide

Build your own Notibar plugin to display notification counts from any service.

## Quick Start

### 1. Create the Plugin Class

Create a new file at `lib/plugins/my_service/my_service_plugin.dart`:

```dart
import '../../models/account.dart';
import '../../models/notification_item.dart';
import '../plugin_interface.dart';

class MyServicePlugin implements NotibarPlugin {
  @override
  ServiceType get serviceType => ServiceType.custom;

  @override
  Future<NotificationSummary> fetchNotifications(Account account) async {
    final token = account.apiKey;
    if (token == null || token.isEmpty) {
      return NotificationSummary.withError(
        PluginError(
          type: PluginErrorType.authentication,
          message: 'API token is missing',
        ),
      );
    }

    try {
      // Make your API call here
      final count = await _fetchUnreadCount(token, account.endpoint);

      return NotificationSummary(
        unreadCount: count,
        items: [], // Optionally populate with NotificationItem list
      );
    } catch (e) {
      return NotificationSummary.withError(
        PluginError(
          type: PluginErrorType.unknown,
          message: e.toString(),
        ),
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
    // Parse the raw API response into a NotificationSummary
    return NotificationSummary(
      unreadCount: unreadCount ?? 0,
      items: [],
    );
  }

  Future<int> _fetchUnreadCount(String token, String? endpoint) async {
    // Your API integration here
    return 0;
  }
}
```

### 2. Register the Plugin

In `lib/ui/tray_manager.dart`, add your plugin to the plugin map:

```dart
final _plugins = <ServiceType, NotibarPlugin>{
  ServiceType.outlook: OutlookPlugin(),
  ServiceType.custom: MyServicePlugin(),  // Add this
};
```

### 3. Add a Service Type (Optional)

If you want a dedicated service type instead of using `custom`, add it to the enum in `lib/models/account.dart`:

```dart
enum ServiceType { outlook, github, jira, slack, teams, myService, custom }
```

Then update your plugin's `serviceType` getter to return the new value.

## Key Rules

### Never Throw Exceptions

The `fetchNotifications` method must **never** throw. Always catch errors and return them wrapped in a `NotificationSummary`:

```dart
return NotificationSummary.withError(
  PluginError(type: PluginErrorType.network, message: 'Connection failed'),
);
```

### Error Types

| Type                             | When to use                               |
| -------------------------------- | ----------------------------------------- |
| `PluginErrorType.authentication` | Bad/expired token, 401/403 responses      |
| `PluginErrorType.network`        | Connection issues, timeouts, DNS failures |
| `PluginErrorType.unknown`        | Everything else                           |

### Use the Account's Config Map

The `Account.config` field is a `Map<String, String>` for service-specific settings. Use it for anything beyond the standard fields:

```dart
final customHeader = account.config['customHeader'] ?? '';
final projectId = account.config['projectId'] ?? '';
```

### Populate NotificationItems (Optional)

If you want to show individual items in the dropdown menu, return them in the `items` list:

```dart
NotificationItem(
  id: 'item-1',
  title: 'New deployment ready',
  subtitle: 'Production',
  timestamp: DateTime.now(),
  actionUrl: 'https://example.com/deploy/123',
  isUnread: true,
  isFlagged: false,
  metadata: {'priority': 'high'},
)
```

## Using the Custom Service Type in Notibar

1. Open Settings → **Accounts** tab → **Add Account**
2. Select **Custom** as the service type
3. Enter:
   - **Name**: Display name for the account
   - **Endpoint**: Your service's API base URL
   - **API Key**: Authentication token
4. Add any extra config key/value pairs as needed
5. Switch to **Notifications** tab and add a tray item for the account

## Testing Your Plugin

Write tests using `mocktail` and real JSON fixtures:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:notibar/plugins/my_service/my_service_plugin.dart';

void main() {
  final plugin = MyServicePlugin();

  test('parseSummary returns correct counts', () {
    final json = {
      'notifications': [
        {'id': '1', 'read': false},
        {'id': '2', 'read': true},
      ],
    };

    final summary = plugin.parseSummary(json, unreadCount: 1);

    expect(summary.unreadCount, 1);
    expect(summary.error, isNull);
  });
}
```

## Display Metrics

Your plugin can populate any combination of these counts in `NotificationSummary`:

| Field                 | DisplayMetric    | Tray icon |
| --------------------- | ---------------- | --------- |
| `unreadCount`         | `unread`         | 📧         |
| `flaggedCount`        | `flagged`        | 🚩         |
| `mentionCount`        | `mentions`       | 💬         |
| `assignedIssuesCount` | `assignedIssues` | 📋         |
| `assignedPRsCount`    | `assignedPRs`    | 🔀         |
| `reviewRequestsCount` | `reviewRequests` | 👀         |
