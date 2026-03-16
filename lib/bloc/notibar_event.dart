import 'package:equatable/equatable.dart';
import '../models/account.dart';
import '../models/notification_option.dart';

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

class AddAccount extends NotibarEvent {
  final Account account;
  const AddAccount(this.account);

  @override
  List<Object?> get props => [account];
}

class RemoveAccount extends NotibarEvent {
  final String accountId;
  const RemoveAccount(this.accountId);

  @override
  List<Object?> get props => [accountId];
}

class UpdateAccountToken extends NotibarEvent {
  final String accountId;
  final String token;
  const UpdateAccountToken(this.accountId, this.token);

  @override
  List<Object?> get props => [accountId, token];
}

class UpdateAccount extends NotibarEvent {
  final Account account;
  const UpdateAccount(this.account);

  @override
  List<Object?> get props => [account];
}

// ─── Notification Option events ───

class AddNotificationOption extends NotibarEvent {
  final NotificationOption option;
  const AddNotificationOption(this.option);

  @override
  List<Object?> get props => [option];
}

class RemoveNotificationOption extends NotibarEvent {
  final String optionId;
  const RemoveNotificationOption(this.optionId);

  @override
  List<Object?> get props => [optionId];
}

class ToggleNotificationOption extends NotibarEvent {
  final String optionId;
  const ToggleNotificationOption(this.optionId);

  @override
  List<Object?> get props => [optionId];
}

class ReorderNotificationOptions extends NotibarEvent {
  final int oldIndex;
  final int newIndex;
  const ReorderNotificationOptions(this.oldIndex, this.newIndex);

  @override
  List<Object?> get props => [oldIndex, newIndex];
}

class UpdateNotificationOption extends NotibarEvent {
  final NotificationOption option;
  const UpdateNotificationOption(this.option);

  @override
  List<Object?> get props => [option];
}
