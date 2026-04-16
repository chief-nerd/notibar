# TODO — Notibar

## Open

- [ ] Port MultiStatusItemPlugin to Windows/Linux (currently macOS only)
- [ ] Add "Select Plan" auto-discovery UI for Planner plan selection (currently fetches from user's M365 groups — may need additional permissions for some orgs)
- [ ] Existing users with `ServiceType.outlook` accounts will auto-migrate via backward-compat in account.g.dart, but need to re-login for Planner scopes (`Tasks.Read`, `Group.Read.All`)
- [ ] Consider merging Teams plugin into Microsoft plugin for a unified M365 experience

## Completed

- [x] **Add "Open in Browser" to tray menus**: Each metric's dropdown now has an "Open in Browser" link below Refresh. Opens the service's web UI filtered to the relevant view (e.g., GitHub issues filtered by assignee, Outlook inbox, Jira JQL query). Implemented via `webUrl()` method on `NotibarPlugin` with per-plugin URL logic.
- [x] **Fix Outlook showing 0 after sleep/wake**: `_fetchCount` was swallowing network exceptions (`SocketException`, `ClientException`, `TimeoutException`) and returning 0 instead of propagating them. The tray then treated these as real zero counts and hid the Outlook items. Fixed by rethrowing network exceptions from `_fetchCount` so `_doFetch` catches them as `PluginErrorType.network`. Also added `ClientException`/`TimeoutException` catch blocks in `_doFetch`, and made the bloc preserve the previous summary on network errors instead of replacing it with zeros.
- [x] **Plugin architecture refactoring**: Moved all plugin-specific presentation logic out of TrayManager and settings_window into the plugins themselves. Removed global `DisplayMetric` enum — metrics are now string-based IDs owned by each plugin's `MetricDefinition` list. Plugins are fully self-describing: they declare `serviceLabel`, `serviceIcon`, `configFields`, `supportedMetrics` (with SF Symbol, Material icon, count/filter functions), and `formatMenuEntry`. The tray and settings UI have zero plugin-specific knowledge. All plugins changed from `implements` to `extends NotibarPlugin`. Updated docs/custom-plugin.md and .instructions.md. All 22 tests pass, 0 analysis issues.
- [x] **Rename Outlook → Microsoft 365**: `ServiceType.outlook` → `ServiceType.microsoft`, all UI labels and plugin classes updated. Backward-compatible deserialization preserves existing accounts.
- [x] **Fix Planner: My Tasks showing 0** — was gated on a `planId` config being set; now always calls `GET /me/planner/tasks` (returns tasks assigned to current user across all plans). Bucket names are resolved by collecting unique `planId`s from the response and fetching `/planner/plans/{id}/buckets` for each in parallel.
- [x] **Add MS Planner Tasks support** under the Microsoft plugin: fetches tasks for a selected plan, with display metrics for My Tasks, by Bucket, Open, In Progress, and Completed
- [x] `NotificationOption.config` map added to support per-option settings (e.g., bucket selection for Planner)
- [x] OAuth scopes updated to include `Tasks.Read` and `Group.Read.All` for Planner access
- [x] Tray manager supports Planner metrics with emoji indicators, per-bucket filtering, and task status display
- [x] Fix GitHub assigned issues/PRs/review requests showing 0 — was counting from notifications inbox `reason` field only; now uses GitHub Search API (`/search/issues`) for real counts
- [x] macOS menu bar app running as `.accessory` (no dock icon, tray-only)
- [x] `NotibarBloc` with full event/state cycle: load, refresh, add/remove/update accounts, polling
- [x] `Account` model with generic `config` map (supports Outlook, GitHub, Jira, Slack, Custom)
- [x] `NotificationOption` model — decoupled from Account; each option = one tray menu entry with metric (unread/flagged/all), sort order, enable toggle
- [x] `NotificationOptionRepository` for persistence via SharedPreferences
- [x] `AccountRepository` for account persistence
- [x] Outlook OAuth2 PKCE login flow (`OutlookAuthService`)
- [x] Plugin system (`NotibarPlugin` interface, `OutlookPlugin` implementation)
- [x] Settings window with two tabs: **Notifications** (reorderable tray items) and **Accounts** (service connections)
- [x] Tray manager renders notification options with icon + count (📧 5  🚩 2), no text labels
- [x] Custom native `MultiStatusItemPlugin` (Swift) — each NotificationOption gets its own `NSStatusItem` in the menu bar, with independent click + dropdown menu
- [x] Replaced `system_tray` package with custom platform channel (`notibar/multi_status_item`)
- [x] Persistent ⚙ control item in menu bar with Refresh All / Settings / Exit
- [x] Bloc tests passing (6 tests) with mocktail mocks
- [x] Fix remaining lint warnings (check `flutter analyze`)
- [x] Implement real data fetching in `OutlookPlugin` (currently returns empty/mock data)
- [x] Add GitHub, Jira, Slack, Teams, Frappe, Mattermost plugin implementations
- [x] Persist polling timer state across hot restarts
- [x] Add tests for `NotificationOptionRepository`, `AccountRepository`, and UI widgets
- [x] Add Plugin parsing tests with JSON fixtures for all services
- [x] Add error display in settings UI when a plugin fetch fails (per-account status)
- [x] Support API key auth (non-OAuth) for GitHub/Jira
- [x] README and docs/ folder with setup guides for each service
