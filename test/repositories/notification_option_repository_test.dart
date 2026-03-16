import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:notibar/models/notification_option.dart';
import 'package:notibar/repositories/notification_option_repository.dart';

void main() {
  group('NotificationOptionRepository', () {
    late SharedPreferences prefs;
    late NotificationOptionRepository repository;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      repository = NotificationOptionRepository(prefs);
    });

    test('getOptions returns empty list when no data', () async {
      final options = await repository.getOptions();
      expect(options, isEmpty);
    });

    test('addOption saves and sorts by sortOrder', () async {
      final opt1 = NotificationOption(id: '1', accountId: 'a1', label: 'L1', sortOrder: 1);
      final opt2 = NotificationOption(id: '2', accountId: 'a1', label: 'L2', sortOrder: 0);
      
      await repository.addOption(opt1);
      await repository.addOption(opt2);
      
      final options = await repository.getOptions();
      expect(options.length, 2);
      expect(options.first.id, '2'); // sorted by sortOrder 0
      expect(options.last.id, '1');  // sorted by sortOrder 1
    });

    test('removeOption deletes the option', () async {
      final opt1 = NotificationOption(id: '1', accountId: 'a1', label: 'L1');
      final opt2 = NotificationOption(id: '2', accountId: 'a1', label: 'L2');
      await repository.saveOptions([opt1, opt2]);
      
      await repository.removeOption('1');
      
      final options = await repository.getOptions();
      expect(options.length, 1);
      expect(options.first.id, '2');
    });
  });
}
