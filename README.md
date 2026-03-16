# Notibar

A lightweight macOS menu bar app that shows notification counts from multiple services — each as its own independent status item.

<!-- ![Notibar screenshot](assets/screenshot.png) -->

## Features

- **Multiple menu bar items** — each notification option gets its own `NSStatusItem`, so you see counts at a glance without opening anything
- **Service plugins** — connect Outlook (Office 365), GitHub, Jira, Slack, Teams, Frappe, Mattermost, or build your own
- **Flexible metrics** — show unread, flagged, mentions, assigned issues, assigned PRs, or review requests per service
- **Independent control** — enable/disable, reorder, and configure each status item separately
- **OAuth 2.0 PKCE** — secure browser-based login for services that support it
- **API key auth** — simple token-based auth for GitHub, Jira, and others
- **Settings UI** — Material 3 settings window with Notifications and Accounts tabs
- **Runs in the background** — no dock icon, no window on launch; lives entirely in the menu bar

## Requirements

- macOS 12.0+
- Flutter 3.29+ (Dart SDK ^3.9.0)

## Getting Started

```bash
# Clone the repository
git clone https://github.com/your-username/notibar.git
cd notibar

# Install dependencies
flutter pub get

# Run in debug mode
flutter run -d macos

# Build a release binary
flutter build macos
```

The release `.app` bundle will be at `build/macos/Build/Products/Release/notibar.app`.

## Architecture

```
lib/
  main.dart              # Entry point, window setup, BlocProvider
  bloc/                  # BLoC classes, events, states
  models/                # Data classes (Account, NotificationOption)
  plugins/               # NotibarPlugin interface + service implementations
  repositories/          # SharedPreferences-backed persistence
  services/              # OAuth, platform channels
  ui/                    # Settings window, tray manager
macos/
  Runner/
    MultiStatusItem.swift  # Native plugin for multiple NSStatusItems
```

State management uses **flutter_bloc**. Persistence goes through repository classes wrapping SharedPreferences. Each service implements the `NotibarPlugin` interface and returns a `NotificationSummary`.

Two core models:

| Model                  | Purpose                                                                                         |
| ---------------------- | ----------------------------------------------------------------------------------------------- |
| **Account**            | A connection to an external service (auth credentials, endpoint, config)                        |
| **NotificationOption** | A single tray entry tied to an account + display metric, independently orderable and toggleable |

## Supported Services

| Service              | Auth Method           | Setup Guide                                    |
| -------------------- | --------------------- | ---------------------------------------------- |
| Outlook (Office 365) | OAuth 2.0 PKCE        | [docs/outlook-setup.md](docs/outlook-setup.md) |
| GitHub               | Personal Access Token | [docs/github-setup.md](docs/github-setup.md)   |
| Jira                 | API Token             | [docs/jira-setup.md](docs/jira-setup.md)       |
| Slack                | OAuth / Bot Token     | [docs/slack-setup.md](docs/slack-setup.md)     |
| Custom               | API Key / Token       | [docs/custom-plugin.md](docs/custom-plugin.md) |

## Configuration

When you first launch Notibar, a ⚙ gear icon appears in the menu bar. Click it and choose **Settings** to open the configuration window.

**Accounts tab** — Add service connections. Each account stores its auth credentials and polling interval.

**Notifications tab** — Add tray items. Each notification option ties an account to a display metric (e.g., "GitHub → Assigned PRs"). Drag to reorder, toggle to show/hide.

## Development

```bash
# Run tests
flutter test

# Run analysis
flutter analyze
```

### Adding a New Plugin

1. Create a class implementing `NotibarPlugin` in `lib/plugins/`
2. Implement `fetchNotifications(Account account)` — return a `NotificationSummary`, never throw
3. Register the plugin in `TrayManager`'s plugin map
4. Add the service type to the `ServiceType` enum in `lib/models/account.dart`

See [docs/custom-plugin.md](docs/custom-plugin.md) for a full walkthrough.

## License

MIT
