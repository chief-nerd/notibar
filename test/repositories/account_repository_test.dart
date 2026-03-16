import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:notibar/models/account.dart';
import 'package:notibar/repositories/account_repository.dart';

void main() {
  group('AccountRepository', () {
    late SharedPreferences prefs;
    late AccountRepository repository;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      repository = AccountRepository(prefs);
    });

    test('getAccounts returns empty list when no data', () async {
      final accounts = await repository.getAccounts();
      expect(accounts, isEmpty);
    });

    test('addAccount saves a new account', () async {
      final account = Account(id: '1', name: 'Test', serviceType: ServiceType.github);
      await repository.addAccount(account);
      
      final accounts = await repository.getAccounts();
      expect(accounts.length, 1);
      expect(accounts.first.name, 'Test');
      
      // Verify raw JSON string in prefs
      final jsonString = prefs.getString('notibar_accounts');
      expect(jsonString, isNotNull);
      final list = json.decode(jsonString!) as List;
      expect(list.first['id'], '1');
    });

    test('removeAccount deletes the account', () async {
      final account1 = Account(id: '1', name: 'Test 1', serviceType: ServiceType.github);
      final account2 = Account(id: '2', name: 'Test 2', serviceType: ServiceType.jira);
      await repository.saveAccounts([account1, account2]);
      
      await repository.removeAccount('1');
      
      final accounts = await repository.getAccounts();
      expect(accounts.length, 1);
      expect(accounts.first.id, '2');
    });
  });
}
