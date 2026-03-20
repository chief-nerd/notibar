import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:notibar/bloc/notibar_bloc.dart';
import 'package:notibar/bloc/notibar_event.dart';
import 'package:notibar/bloc/notibar_state.dart';
import 'package:notibar/models/account.dart';
import 'package:notibar/models/notification_option.dart';
import 'package:notibar/plugins/plugin_interface.dart';
import 'package:notibar/repositories/account_repository.dart';
import 'package:notibar/repositories/notification_option_repository.dart';

class MockNotibarPlugin extends Mock implements NotibarPlugin {}

class MockAccountRepository extends Mock implements AccountRepository {}

class MockNotificationOptionRepository extends Mock
    implements NotificationOptionRepository {}

void main() {
  group('NotibarBloc', () {
    late NotibarBloc notibarBloc;
    late MockNotibarPlugin mockPlugin;
    late MockAccountRepository mockRepo;
    late MockNotificationOptionRepository mockOptionRepo;
    final testAccount = const Account(
      id: '1',
      name: 'Test',
      serviceType: ServiceType.microsoft,
    );
    final testOption = const NotificationOption(
      id: 'opt_1',
      accountId: '1',
      label: 'Unread',
      metric: 'unread',
    );

    setUp(() {
      mockPlugin = MockNotibarPlugin();
      mockRepo = MockAccountRepository();
      mockOptionRepo = MockNotificationOptionRepository();

      registerFallbackValue(testAccount);

      when(() => mockPlugin.serviceType).thenReturn(ServiceType.microsoft);
      when(() => mockPlugin.fetchNotifications(any())).thenAnswer(
        (_) async =>
            NotificationSummary(unreadCount: 5, flaggedCount: 2, items: []),
      );

      when(() => mockRepo.getAccounts()).thenAnswer((_) async => [testAccount]);
      when(() => mockRepo.saveAccounts(any())).thenAnswer((_) async {});
      when(
        () => mockOptionRepo.getOptions(),
      ).thenAnswer((_) async => [testOption]);

      notibarBloc = NotibarBloc(
        accountRepository: mockRepo,
        optionRepository: mockOptionRepo,
        plugins: {ServiceType.microsoft: mockPlugin},
      );
    });

    tearDown(() {
      notibarBloc.close();
    });

    test('initial state is NotibarInitial', () {
      expect(notibarBloc.state, equals(NotibarInitial()));
    });

    blocTest<NotibarBloc, NotibarState>(
      'emits [NotibarLoading, NotibarLoaded] when LoadAccounts is added',
      build: () => notibarBloc,
      act: (bloc) => bloc.add(LoadAccounts()),
      expect: () => [
        isA<NotibarLoading>(),
        isA<NotibarLoaded>().having(
          (s) => s.summariesByAccountId['1']?.unreadCount,
          'unreadCount',
          5,
        ),
      ],
      verify: (_) {
        verify(() => mockRepo.getAccounts()).called(1);
        verify(() => mockPlugin.fetchNotifications(any())).called(1);
      },
    );

    blocTest<NotibarBloc, NotibarState>(
      'emits updated state when RefreshAccount is added',
      build: () => notibarBloc,
      seed: () => NotibarLoaded(
        accounts: [testAccount],
        options: [testOption],
        summariesByAccountId: {
          '1': NotificationSummary(unreadCount: 0, flaggedCount: 0, items: []),
        },
      ),
      act: (bloc) => bloc.add(const RefreshAccount('1')),
      expect: () => [
        isA<NotibarLoaded>().having(
          (s) => s.summariesByAccountId['1']?.unreadCount,
          'unreadCount',
          5,
        ),
      ],
    );

    blocTest<NotibarBloc, NotibarState>(
      'handles plugin errors gracefully',
      build: () => notibarBloc,
      setUp: () {
        when(() => mockPlugin.fetchNotifications(any())).thenAnswer(
          (_) async => NotificationSummary.withError(
            PluginError(
              type: PluginErrorType.authentication,
              message: 'Failed',
            ),
          ),
        );
      },
      act: (bloc) => bloc.add(LoadAccounts()),
      expect: () => [
        isA<NotibarLoading>(),
        isA<NotibarLoaded>().having(
          (s) => s.summariesByAccountId['1']?.error?.type,
          'error type',
          PluginErrorType.authentication,
        ),
      ],
    );
  });
}
