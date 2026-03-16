import 'package:equatable/equatable.dart';
import '../models/account.dart';
import '../models/notification_option.dart';
import '../plugins/plugin_interface.dart';

abstract class NotibarState extends Equatable {
  const NotibarState();
  @override
  List<Object?> get props => [];
}

class NotibarInitial extends NotibarState {}

class NotibarLoading extends NotibarState {}

class NotibarLoaded extends NotibarState {
  final Map<String, NotificationSummary> summariesByAccountId;
  final List<Account> accounts;
  final List<NotificationOption> options;

  const NotibarLoaded({
    required this.summariesByAccountId,
    required this.accounts,
    required this.options,
  });

  @override
  List<Object?> get props => [summariesByAccountId, accounts, options];
}

class NotibarError extends NotibarState {
  final String message;
  const NotibarError(this.message);

  @override
  List<Object?> get props => [message];
}
