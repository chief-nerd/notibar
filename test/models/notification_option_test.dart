import 'package:flutter_test/flutter_test.dart';
import 'package:notibar/models/notification_option.dart';

void main() {
  group('NotificationOption Model', () {
    test('supports value equality', () {
      const opt1 = NotificationOption(id: '1', accountId: 'a1', label: 'L1');
      const opt2 = NotificationOption(id: '1', accountId: 'a1', label: 'L1');
      expect(opt1, equals(opt2));
    });

    test('toJson and fromJson work correctly', () {
      const original = NotificationOption(
        id: '1',
        accountId: 'a1',
        label: 'L1',
        metric: 'flagged',
        enabled: false,
        sortOrder: 5,
      );

      final json = original.toJson();
      final decoded = NotificationOption.fromJson(json);

      expect(decoded, original);
      expect(json['metric'], 'flagged');
      expect(json['enabled'], false);
    });
  });
}
