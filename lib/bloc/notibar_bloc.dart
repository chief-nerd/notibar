import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../models/account.dart';
import '../plugins/plugin_interface.dart';
import '../plugins/outlook/outlook_plugin.dart';
import '../repositories/account_repository.dart';
import 'notibar_event.dart';
import 'notibar_state.dart';

class NotibarBloc extends Bloc<NotibarEvent, NotibarState> {
  final Map<ServiceType, NotibarPlugin> _plugins;
  final AccountRepository _accountRepository;
  final Map<String, Timer> _pollingTimers = {};

  NotibarBloc({
    required AccountRepository accountRepository,
    Map<ServiceType, NotibarPlugin>? plugins,
  })  : _accountRepository = accountRepository,
        _plugins = plugins ?? {ServiceType.outlook: OutlookPlugin()},
        super(NotibarInitial()) {
    on<LoadAccounts>(_onLoadAccounts);
    on<RefreshAll>(_onRefreshAll);
    on<RefreshAccount>(_onRefreshAccount);
  }

  Future<void> _onLoadAccounts(LoadAccounts event, Emitter<NotibarState> emit) async {
    emit(NotibarLoading());
    try {
      final accounts = await _accountRepository.getAccounts();
      
      // If no accounts exist, maybe add a default one or just return empty
      // For this migration, if empty we can't do much without UI for adding
      // but let's assume accounts are persisted.

      final summaries = <String, NotificationSummary>{};
      for (final account in accounts) {
        final plugin = _plugins[account.serviceType];
        if (plugin != null) {
          summaries[account.id] = await plugin.fetchNotifications(account);
        } else {
          summaries[account.id] = NotificationSummary.withError(
            PluginError(type: PluginErrorType.unknown, message: 'Plugin not found for ${account.serviceType}')
          );
        }
      }

      emit(NotibarLoaded(summariesByAccountId: summaries, accounts: accounts));
      _startPolling(accounts);
    } catch (e) {
      emit(NotibarError('Failed to load accounts: $e'));
    }
  }

  void _startPolling(List<Account> accounts) {
    for (var timer in _pollingTimers.values) {
      timer.cancel();
    }
    _pollingTimers.clear();

    for (final account in accounts) {
      _pollingTimers[account.id] = Timer.periodic(account.pollingInterval, (_) {
        add(RefreshAccount(account.id));
      });
    }
  }

  Future<void> _onRefreshAll(RefreshAll event, Emitter<NotibarState> emit) async {
    if (state is NotibarLoaded) {
      final currentState = state as NotibarLoaded;
      final summaries = Map<String, NotificationSummary>.from(currentState.summariesByAccountId);
      
      final results = await Future.wait(currentState.accounts.map((account) async {
        final plugin = _plugins[account.serviceType];
        if (plugin != null) {
          return MapEntry(account.id, await plugin.fetchNotifications(account));
        }
        return MapEntry(account.id, NotificationSummary.withError(
          PluginError(type: PluginErrorType.unknown, message: 'Plugin not found')
        ));
      }));

      summaries.addEntries(results);
      emit(NotibarLoaded(summariesByAccountId: summaries, accounts: currentState.accounts));
    }
  }

  Future<void> _onRefreshAccount(RefreshAccount event, Emitter<NotibarState> emit) async {
     if (state is NotibarLoaded) {
      final currentState = state as NotibarLoaded;
      final accountIndex = currentState.accounts.indexWhere((a) => a.id == event.accountId);
      if (accountIndex == -1) return;

      final account = currentState.accounts[accountIndex];
      final plugin = _plugins[account.serviceType];
      if (plugin != null) {
        final summary = await plugin.fetchNotifications(account);
        final summaries = Map<String, NotificationSummary>.from(currentState.summariesByAccountId);
        summaries[account.id] = summary;
        emit(NotibarLoaded(summariesByAccountId: summaries, accounts: currentState.accounts));
      }
    }
  }

  @override
  Future<void> close() {
    for (var timer in _pollingTimers.values) {
      timer.cancel();
    }
    return super.close();
  }
}
