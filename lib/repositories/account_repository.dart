import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/account.dart';

class AccountRepository {
  static const _key = 'notibar_accounts';
  final SharedPreferences _prefs;

  AccountRepository(this._prefs);

  Future<List<Account>> getAccounts() async {
    final jsonString = _prefs.getString(_key);
    if (jsonString == null) return [];
    
    try {
      final List<dynamic> jsonList = json.decode(jsonString);
      return jsonList.map((e) => Account.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> saveAccounts(List<Account> accounts) async {
    final jsonString = json.encode(accounts.map((e) => e.toJson()).toList());
    await _prefs.setString(_key, jsonString);
  }

  Future<void> addAccount(Account account) async {
    final accounts = await getAccounts();
    accounts.add(account);
    await saveAccounts(accounts);
  }

  Future<void> removeAccount(String id) async {
    final accounts = await getAccounts();
    accounts.removeWhere((a) => a.id == id);
    await saveAccounts(accounts);
  }
}
