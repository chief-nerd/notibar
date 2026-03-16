# Notibar — Copilot Instructions

## Workflow Rules

- **After every round of changes**, check for Problems (errors, warnings, info). Fix all errors before moving on. Warnings and infos should be addressed unless there's a strong reason not to.
- **Always update `TODO.md`** at the project root at the end of a session. Record what was done, what's left, and any known issues. Keep it minimal — just enough context for the next agent session. Move the items to the correct sections (Completed, Open) and add any relevant items about workarounds for issues encountered.
- **Run tests** (`flutter test`) after modifying bloc, model, or repository code to catch regressions.
- **Learn from mistakes**: When you encounter a repeated error or discover a non-obvious gotcha (e.g. platform-specific logging behavior, API quirks), add it to the relevant section of this file (Debugging, Common Pitfalls, etc.) so the same mistake is never made twice.

## Architecture

- **State Management**: flutter_bloc. Prefer **Cubits** for new features. The existing `NotibarBloc` uses full Bloc (events/states) — keep that pattern there but use Cubits for any new isolated features.
- **Repository Pattern**: All persistence goes through repository classes that wrap SharedPreferences. Repositories are injected into Blocs/Cubits via constructor.
- **Plugin System**: Each service (Outlook, GitHub, Jira, etc.) implements `NotibarPlugin`. Plugins return `NotificationSummary` with error info rather than throwing exceptions.
- **Two core domain models**:
  - `Account` — a connection to an external service (auth, config)
  - `NotificationOption` — a tray menu entry tied to an account + display metric (unread/flagged/all), independently orderable and toggleable

## Project Structure

```
lib/
  main.dart              # Entry point, window setup, BlocProvider
  bloc/                  # BLoC classes, events, states
  models/                # Data classes (Equatable, JSON serialization)
  plugins/               # NotibarPlugin interface + service implementations
  repositories/          # SharedPreferences-backed persistence
  services/              # External integrations (OAuth, etc.)
  ui/                    # Widgets — settings window, tray manager
test/
  bloc/                  # Bloc tests using bloc_test + mocktail
  models/                # Model unit tests
macos/                   # Native macOS config (menu bar / accessory app)
```

## Coding Conventions

- **Models** extend `Equatable`. Use `json_serializable` for codegen where `account.g.dart` already exists; hand-written `fromJson`/`toJson` is fine for simple models.
- **Events**: Verb-first naming (`LoadAccounts`, `AddAccount`, `RefreshAll`, `ToggleNotificationOption`).
- **States**: Noun-first naming (`NotibarInitial`, `NotibarLoading`, `NotibarLoaded`).
- **Immutability**: Models use `const` constructors and `copyWith` methods. Do not mutate state directly.
- **Error handling in plugins**: Return errors inside `NotificationSummary.withError(PluginError(...))`, never throw from `fetchNotifications`.

## UI

- **macOS menu bar app** — runs as `.accessory` (no dock icon). Window is hidden on startup, shown when user clicks "Settings" in the tray.
- Use **Material 3** theming with `colorScheme` from the theme, not hardcoded colors.
- Settings window uses **tabs** (Notifications and Accounts).
- Dialogs for add/edit flows. Keep them in the same file as the parent widget unless they grow large.
- `ReorderableListView` with `buildDefaultDragHandles: false` + explicit `ReorderableDragStartListener` for drag handles.

## Dependencies

- `flutter_bloc` / `equatable` for state
- Custom `MultiStatusItemPlugin` for macOS menu bar (native Swift, multiple NSStatusItems)
- `window_manager` for window show/hide
- `shared_preferences` for persistence
- `crypto` for PKCE auth flows
- `mocktail` + `bloc_test` for testing

Do **not** add new dependencies without justification. Prefer what's already in `pubspec.yaml`.

## Testing

- Use `mocktail` for mocks (not mockito).
- Use `blocTest` from `bloc_test` for bloc state transitions.
- Register fallback values for any Equatable types used with `any()`.
- Mock both `AccountRepository` and `NotificationOptionRepository` in bloc tests.

## macOS Specifics

- `AppDelegate.swift`: `applicationShouldTerminateAfterLastWindowClosed` returns `false`. App sets `NSApp.setActivationPolicy(.accessory)`.
- Tray icon: `assets/app_icon.png`.
- The app must keep running when the window is closed/hidden.

## Common Pitfalls

- `DropdownButtonFormField` uses `initialValue:` (not the deprecated `value:`).
- When editing `settings_window.dart`, watch out for duplicate class names — the file is large.
- After removing fields from a model, check all UI code that references those fields.
- Removing a Bloc event requires checking both the Bloc handlers and all `bloc.add(...)` call sites in UI code.
- **Microsoft Graph API rate limits (429)**: Too many parallel API calls can trigger throttling. Prefer deriving data from existing responses (e.g. find "Inbox" folder ID from the folder map) rather than making separate API calls. Keep parallel Graph API requests to a minimum.

## Debugging

- **Flutter `debugPrint` / `print` output does NOT appear in macOS system logs** (`log show`). It only goes to the stdout of the `flutter run` process. To see it:
  1. Run the app with output redirected to a file: `flutter run -d macos > /tmp/notibar_debug.log 2>&1` (in a background job or separate terminal).
  2. Wait for the app to start and perform the action you want to debug.
  3. Read the log: `grep -i "your_search_term" /tmp/notibar_debug.log`.
- **Native Swift `NSLog` output** (e.g. from `MultiStatusItemPlugin`) **does** appear in system logs: `log show --predicate 'process == "notibar"' --last 2m --style compact`.
- **Do not** waste time trying to read `debugPrint` output via `log show` — it will never appear there.
- Logging tags in the codebase: `[App]`, `[Bloc]`, `[Tray]`, `[Outlook]`, `[OutlookAuth]`. Use these to grep for relevant output.
- When adding temporary debug logging, always remove it after the issue is resolved.
