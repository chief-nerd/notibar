import 'package:flutter_test/flutter_test.dart';
import 'package:notibar/models/account.dart';

void main() {
  group('Account Model', () {
    test('supports value equality', () {
      const account1 = Account(
        id: '1',
        name: 'Work',
        serviceType: ServiceType.outlook,
        apiKey: 'token123',
      );
      const account2 = Account(
        id: '1',
        name: 'Work',
        serviceType: ServiceType.outlook,
        apiKey: 'token123',
      );
      expect(account1, equals(account2));
    });

    test('has correct default polling interval', () {
      const account = Account(
        id: '1',
        name: 'Work',
        serviceType: ServiceType.outlook,
      );
      expect(account.pollingInterval, const Duration(minutes: 5));
    });
  });
}
