import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../models/account.dart';
import '../plugins/plugin_interface.dart';
import '../plugins/microsoft/microsoft_plugin.dart';
import '../plugins/github/github_plugin.dart';
import '../plugins/jira/jira_plugin.dart';
import '../plugins/slack/slack_plugin.dart';
import '../plugins/teams/teams_plugin.dart';
import '../plugins/frappe/frappe_plugin.dart';
import '../plugins/mattermost/mattermost_plugin.dart';
import '../repositories/account_repository.dart';
import '../repositories/notification_option_repository.dart';
import 'notibar_event.dart';
import 'notibar_state.dart';

class NotibarBloc extends Bloc<NotibarEvent, NotibarState> {
  final Map<ServiceType, NotibarPlugin> plugins;
  final AccountRepository _accountRepository;
  final NotificationOptionRepository _optionRepository;
  final Map<String, Timer> _pollingTimers = {};

  NotibarBloc({
    required AccountRepository accountRepository,
    required NotificationOptionRepository optionRepository,
    Map<ServiceType, NotibarPlugin>? plugins,
  }) : _accountRepository = accountRepository,
       _optionRepository = optionRepository,
       plugins =
           plugins ??
           {
             ServiceType.microsoft: MicrosoftPlugin(),
             ServiceType.github: GithubPlugin(),
             ServiceType.jira: JiraPlugin(),
             ServiceType.slack: SlackPlugin(),
             ServiceType.teams: TeamsPlugin(),
             ServiceType.frappe: FrappePlugin(),
             ServiceType.mattermost: MattermostPlugin(),
           },
       super(NotibarInitial()) {
    debugPrint(
      '[Bloc] init with ${this.plugins.length} plugins: ${this.plugins.keys.join(', ')}',
    );
    on<LoadAccounts>(_onLoadAccounts);
    on<RefreshAll>(_onRefreshAll);
    on<RefreshAccount>(_onRefreshAccount);
    on<AddAccount>(_onAddAccount);
    on<RemoveAccount>(_onRemoveAccount);
    on<UpdateAccountToken>(_onUpdateAccountToken);
    on<UpdateAccount>(_onUpdateAccount);
    on<AddNotificationOption>(_onAddOption);
    on<RemoveNotificationOption>(_onRemoveOption);
    on<ToggleNotificationOption>(_onToggleOption);
    on<ReorderNotificationOptions>(_onReorderOptions);
    on<UpdateNotificationOption>(_onUpdateOption);
  }

  Future<void> _onLoadAccounts(
    LoadAccounts event,
    Emitter<NotibarState> emit,
  ) async {
    emit(NotibarLoading());
    try {
      final accounts = await _accountRepository.getAccounts();
      final options = await _optionRepository.getOptions();
      debugPrint(
        '[Bloc] LoadAccounts: ${accounts.length} accounts, ${options.length} options',
      );

      // Fetch summaries for accounts that have enabled options
      final activeAccountIds = options
          .where((o) => o.enabled)
          .map((o) => o.accountId)
          .toSet();

      final summaries = <String, NotificationSummary>{};
      final updatedAccounts = List<Account>.from(accounts);
      final now = DateTime.now();

      for (var i = 0; i < updatedAccounts.length; i++) {
        final account = updatedAccounts[i];
        if (!activeAccountIds.contains(account.id)) continue;
        final plugin = plugins[account.serviceType];
        if (plugin != null) {
          debugPrint(
            '[Bloc]   fetching ${account.serviceType.name}/${account.name} (${account.id})',
          );
          summaries[account.id] = await plugin.fetchNotifications(account);
          updatedAccounts[i] = account.copyWith(lastRefreshTime: now);
        } else {
          summaries[account.id] = NotificationSummary.withError(
            PluginError(
              type: PluginErrorType.unknown,
              message: 'Plugin not found for ${account.serviceType}',
            ),
          );
        }
      }

      if (updatedAccounts != accounts) {
        await _accountRepository.saveAccounts(updatedAccounts);
      }

      emit(
        NotibarLoaded(
          summariesByAccountId: summaries,
          accounts: updatedAccounts,
          options: options,
        ),
      );
      debugPrint(
        '[Bloc] LoadAccounts done: ${summaries.length} summaries emitted',
      );
      _startPolling(updatedAccounts, activeAccountIds);
    } catch (e, stack) {
      debugPrint('[Bloc] LoadAccounts error: $e\n$stack');
      emit(NotibarError('Failed to load: $e'));
    }
  }

  void _startPolling(List<Account> accounts, Set<String> activeAccountIds) {
    for (var timer in _pollingTimers.values) {
      timer.cancel();
    }
    _pollingTimers.clear();
    debugPrint(
      '[Bloc] starting polling for ${activeAccountIds.length} active accounts',
    );

    final now = DateTime.now();
    for (final account in accounts) {
      if (!activeAccountIds.contains(account.id)) continue;

      // Calculate when the next poll should happen
      Duration initialDelay = Duration.zero;
      if (account.lastRefreshTime != null) {
        final timeSinceLastRefresh = now.difference(account.lastRefreshTime!);
        if (timeSinceLastRefresh < account.pollingInterval) {
          initialDelay = account.pollingInterval - timeSinceLastRefresh;
        }
      }

      if (initialDelay == Duration.zero) {
        debugPrint(
          '[Bloc]   poll ${account.name}: every ${account.pollingInterval.inSeconds}s',
        );
        // Start periodic timer immediately
        _pollingTimers[account.id] = Timer.periodic(account.pollingInterval, (
          _,
        ) {
          add(RefreshAccount(account.id));
        });
      } else {
        debugPrint(
          '[Bloc]   poll ${account.name}: first in ${initialDelay.inSeconds}s, then every ${account.pollingInterval.inSeconds}s',
        );
        // Wait for initial delay, then start periodic timer
        _pollingTimers[account.id] = Timer(initialDelay, () {
          add(RefreshAccount(account.id));
          _pollingTimers[account.id] = Timer.periodic(account.pollingInterval, (
            _,
          ) {
            add(RefreshAccount(account.id));
          });
        });
      }
    }
  }

  Future<void> _onRefreshAll(
    RefreshAll event,
    Emitter<NotibarState> emit,
  ) async {
    if (state is NotibarLoaded) {
      final currentState = state as NotibarLoaded;
      final summaries = Map<String, NotificationSummary>.from(
        currentState.summariesByAccountId,
      );
      final updatedAccounts = List<Account>.from(currentState.accounts);
      final now = DateTime.now();

      final results = await Future.wait(
        currentState.accounts.where((a) => summaries.containsKey(a.id)).map((
          account,
        ) async {
          final plugin = plugins[account.serviceType];
          if (plugin != null) {
            final summary = await plugin.fetchNotifications(account);
            final idx = updatedAccounts.indexWhere((a) => a.id == account.id);
            if (idx != -1) {
              final base = summary.refreshedAccount ?? account;
              updatedAccounts[idx] = base.copyWith(lastRefreshTime: now);
            }
            return MapEntry(account.id, summary);
          }
          return MapEntry(
            account.id,
            NotificationSummary.withError(
              PluginError(
                type: PluginErrorType.unknown,
                message: 'Plugin not found',
              ),
            ),
          );
        }),
      );

      summaries.addEntries(results);
      await _accountRepository.saveAccounts(updatedAccounts);

      emit(
        NotibarLoaded(
          summariesByAccountId: summaries,
          accounts: updatedAccounts,
          options: currentState.options,
        ),
      );
    }
  }

  Future<void> _onRefreshAccount(
    RefreshAccount event,
    Emitter<NotibarState> emit,
  ) async {
    if (state is NotibarLoaded) {
      final currentState = state as NotibarLoaded;
      final account = currentState.accounts
          .where((a) => a.id == event.accountId)
          .firstOrNull;
      if (account == null) {
        debugPrint(
          '[Bloc] RefreshAccount: account ${event.accountId} not found',
        );
        return;
      }

      debugPrint(
        '[Bloc] RefreshAccount: ${account.name} (${account.serviceType.name})',
      );

      final plugin = plugins[account.serviceType];
      if (plugin != null) {
        final summary = await plugin.fetchNotifications(account);
        final summaries = Map<String, NotificationSummary>.from(
          currentState.summariesByAccountId,
        );

        // On network errors, keep the previous summary so the tray doesn't
        // flash to zero while the connection is recovering (e.g. after sleep).
        final isNetworkError = summary.error?.type == PluginErrorType.network;
        final hasPrevious =
            summaries.containsKey(account.id) &&
            summaries[account.id]?.error == null;
        if (isNetworkError && hasPrevious) {
          debugPrint(
            '[Bloc] Network error for ${account.name}, keeping previous summary',
          );
          return;
        }
        summaries[account.id] = summary;

        final updatedAccounts = List<Account>.from(currentState.accounts);
        final idx = updatedAccounts.indexWhere((a) => a.id == account.id);
        if (idx != -1) {
          // If the plugin refreshed the token, use the updated account
          final base = summary.refreshedAccount ?? account;
          updatedAccounts[idx] = base.copyWith(lastRefreshTime: DateTime.now());
        }
        await _accountRepository.saveAccounts(updatedAccounts);

        emit(
          NotibarLoaded(
            summariesByAccountId: summaries,
            accounts: updatedAccounts,
            options: currentState.options,
          ),
        );
      }
    }
  }

  Future<void> _onAddAccount(
    AddAccount event,
    Emitter<NotibarState> emit,
  ) async {
    debugPrint(
      '[Bloc] AddAccount: ${event.account.name} (${event.account.serviceType.name})',
    );
    await _accountRepository.addAccount(event.account);
    add(LoadAccounts());
  }

  Future<void> _onRemoveAccount(
    RemoveAccount event,
    Emitter<NotibarState> emit,
  ) async {
    debugPrint('[Bloc] RemoveAccount: ${event.accountId}');
    // Also remove all notification options for this account
    final options = await _optionRepository.getOptions();
    final updated = options
        .where((o) => o.accountId != event.accountId)
        .toList();
    await _optionRepository.saveOptions(updated);
    await _accountRepository.removeAccount(event.accountId);
    add(LoadAccounts());
  }

  Future<void> _onUpdateAccountToken(
    UpdateAccountToken event,
    Emitter<NotibarState> emit,
  ) async {
    debugPrint('[Bloc] UpdateAccountToken: ${event.accountId}');
    final accounts = await _accountRepository.getAccounts();
    final idx = accounts.indexWhere((a) => a.id == event.accountId);
    if (idx == -1) return;
    accounts[idx] = accounts[idx].copyWith(apiKey: event.token);
    await _accountRepository.saveAccounts(accounts);
    add(LoadAccounts());
  }

  Future<void> _onUpdateAccount(
    UpdateAccount event,
    Emitter<NotibarState> emit,
  ) async {
    final accounts = await _accountRepository.getAccounts();
    final idx = accounts.indexWhere((a) => a.id == event.account.id);
    if (idx == -1) return;
    accounts[idx] = event.account;
    await _accountRepository.saveAccounts(accounts);
    add(LoadAccounts());
  }

  // ─── Notification Option handlers ───

  Future<void> _onAddOption(
    AddNotificationOption event,
    Emitter<NotibarState> emit,
  ) async {
    await _optionRepository.addOption(event.option);
    add(LoadAccounts());
  }

  Future<void> _onRemoveOption(
    RemoveNotificationOption event,
    Emitter<NotibarState> emit,
  ) async {
    await _optionRepository.removeOption(event.optionId);
    add(LoadAccounts());
  }

  Future<void> _onToggleOption(
    ToggleNotificationOption event,
    Emitter<NotibarState> emit,
  ) async {
    final options = await _optionRepository.getOptions();
    final idx = options.indexWhere((o) => o.id == event.optionId);
    if (idx == -1) return;
    options[idx] = options[idx].copyWith(enabled: !options[idx].enabled);
    await _optionRepository.saveOptions(options);
    add(LoadAccounts());
  }

  Future<void> _onReorderOptions(
    ReorderNotificationOptions event,
    Emitter<NotibarState> emit,
  ) async {
    final options = await _optionRepository.getOptions();
    var newIndex = event.newIndex;
    if (newIndex > event.oldIndex) newIndex--;
    final item = options.removeAt(event.oldIndex);
    options.insert(newIndex, item);
    for (var i = 0; i < options.length; i++) {
      options[i] = options[i].copyWith(sortOrder: i);
    }
    await _optionRepository.saveOptions(options);
    add(LoadAccounts());
  }

  Future<void> _onUpdateOption(
    UpdateNotificationOption event,
    Emitter<NotibarState> emit,
  ) async {
    final options = await _optionRepository.getOptions();
    final idx = options.indexWhere((o) => o.id == event.option.id);
    if (idx == -1) return;
    options[idx] = event.option;
    await _optionRepository.saveOptions(options);
    add(LoadAccounts());
  }

  @override
  Future<void> close() {
    for (var timer in _pollingTimers.values) {
      timer.cancel();
    }
    return super.close();
  }
}
