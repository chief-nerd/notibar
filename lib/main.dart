import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'bloc/notibar_bloc.dart';
import 'bloc/notibar_event.dart';
import 'models/account.dart';
import 'repositories/account_repository.dart';
import 'ui/tray_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Must initialize window manager before hiding
  await windowManager.ensureInitialized();
  WindowOptions windowOptions = const WindowOptions(
    size: Size(0, 0),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.hide();
  });

  final prefs = await SharedPreferences.getInstance();
  final repository = AccountRepository(prefs);
  
  // Seed mock data if empty for first run demo
  final accounts = await repository.getAccounts();
  if (accounts.isEmpty) {
    await repository.saveAccounts([
      const Account(
        id: '1',
        name: 'Work Outlook',
        serviceType: ServiceType.outlook,
        apiKey: 'MOCK_TOKEN',
        pollingInterval: Duration(minutes: 5),
      ),
    ]);
  }

  final bloc = NotibarBloc(accountRepository: repository);
  final trayManager = TrayManager(bloc);
  await trayManager.init();

  runApp(
    BlocProvider.value(
      value: bloc..add(LoadAccounts()),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // This app is tray-only, so we return a dummy widget
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SizedBox.shrink(),
    );
  }
}
