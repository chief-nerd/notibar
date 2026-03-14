import 'package:equatable/equatable.dart';

abstract class NotibarEvent extends Equatable {
  const NotibarEvent();
  @override
  List<Object?> get props => [];
}

class LoadAccounts extends NotibarEvent {}

class RefreshAccount extends NotibarEvent {
  final String accountId;
  const RefreshAccount(this.accountId);

  @override
  List<Object?> get props => [accountId];
}

class RefreshAll extends NotibarEvent {}
