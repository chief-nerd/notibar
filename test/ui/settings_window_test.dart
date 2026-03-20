import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:notibar/bloc/notibar_bloc.dart';
import 'package:notibar/bloc/notibar_state.dart';
import 'package:notibar/models/account.dart';
import 'package:notibar/plugins/plugin_interface.dart';
import 'package:notibar/ui/settings_window.dart';

class MockNotibarBloc extends Mock implements NotibarBloc {}

void main() {
  testWidgets('SettingsWindow renders tabs and loaded state', (
    WidgetTester tester,
  ) async {
    final mockBloc = MockNotibarBloc();

    when(() => mockBloc.state).thenReturn(
      const NotibarLoaded(accounts: [], options: [], summariesByAccountId: {}),
    );
    when(() => mockBloc.stream).thenAnswer((_) => const Stream.empty());
    when(() => mockBloc.close()).thenAnswer((_) async {});
    when(
      () => mockBloc.plugins,
    ).thenReturn(const <ServiceType, NotibarPlugin>{});

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<NotibarBloc>.value(
          value: mockBloc,
          child: const SettingsWindow(),
        ),
      ),
    );

    expect(find.text('Notibar Settings'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Accounts'), findsOneWidget);

    // Notifications tab is active by default
    expect(
      find.text('Add an account first in the Accounts tab'),
      findsOneWidget,
    );

    // Tap Accounts tab
    await tester.tap(find.text('Accounts'));
    await tester.pumpAndSettle();

    expect(find.text('No accounts yet'), findsOneWidget);
  });
}
