# TODO — Notibar

## Completed

- macOS menu bar app running as `.accessory` (no dock icon, tray-only)
- `NotibarBloc` with full event/state cycle: load, refresh, add/remove/update accounts, polling
- `Account` model with generic `config` map (supports Outlook, GitHub, Jira, Slack, Custom)
- `NotificationOption` model — decoupled from Account; each option = one tray menu entry with metric (unread/flagged/all), sort order, enable toggle
- `NotificationOptionRepository` for persistence via SharedPreferences
- `AccountRepository` for account persistence
- Outlook OAuth2 PKCE login flow (`OutlookAuthService`)
- Plugin system (`NotibarPlugin` interface, `OutlookPlugin` implementation)
- Settings window with two tabs: **Notifications** (reorderable tray items) and **Accounts** (service connections)
- Tray manager renders notification options with icon + count (📧 5  🚩 2), no text labels
- Custom native `MultiStatusItemPlugin` (Swift) — each NotificationOption gets its own `NSStatusItem` in the menu bar, with independent click + dropdown menu
- Replaced `system_tray` package with custom platform channel (`notibar/multi_status_item`)
- Persistent ⚙ control item in menu bar with Refresh All / Settings / Exit
- Bloc tests passing (6 tests) with mocktail mocks

## Open

- [x] Fix remaining lint warnings (check `flutter analyze`)
- [x] Implement real data fetching in `OutlookPlugin` (currently returns empty/mock data)
- [x] Add GitHub, Jira, Slack, Teams, Frappe, Mattermost plugin implementations
- [x] Persist polling timer state across hot restarts
- [ ] Handle SharedPreferences migration if model fields change
- [x] Add tests for `NotificationOptionRepository`, `AccountRepository`, and UI widgets
- [x] Add Plugin parsing tests with JSON fixtures for all services
- [x] Add error display in settings UI when a plugin fetch fails (per-account status)
- [x] Support API key auth (non-OAuth) for GitHub/Jira
- [x] README and docs/ folder with setup guides for each service
- [ ] Port MultiStatusItemPlugin to Windows/Linux (currently macOS only)

## Completed Features & Fixes

- **First-run Logic:** Added `has_run_before` flag to prevent re-seeding demo data.
- **Polling Persistence:** Added `lastRefreshTime` to `Account` model to resume polling accurately across restarts.
- **Native Tray Icons:** Enhanced `MultiStatusItemPlugin` to support native images (e.g., `NSAppIcon`) instead of just text/emojis.
- **Control Icon:** Control item now uses the application icon.
