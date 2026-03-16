import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'bloc/notibar_bloc.dart';
import 'bloc/notibar_event.dart';
import 'models/account.dart';
import 'models/notification_option.dart';
import 'repositories/account_repository.dart';
import 'repositories/notification_option_repository.dart';
import 'ui/settings_window.dart';
import 'ui/tray_manager.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

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
  final accountRepo = AccountRepository(prefs);
  final optionRepo = NotificationOptionRepository(prefs);

  // Seed demo data on first run only
  final hasRunBefore = prefs.getBool('has_run_before') ?? false;
  if (!hasRunBefore) {
    // Start with a clean slate in production
    await prefs.setBool('has_run_before', true);
  }

  final bloc = NotibarBloc(
    accountRepository: accountRepo,
    optionRepository: optionRepo,
  );

  final trayManager = TrayManager(
    bloc,
    onSettingsPressed: () => _showSettings(),
  );
  await trayManager.init();

  runApp(
    BlocProvider.value(value: bloc..add(LoadAccounts()), child: const MyApp()),
  );
}

Future<void> _showSettings() async {
  await windowManager.setSize(const Size(600, 500));
  await windowManager.center();
  await windowManager.show();
  await windowManager.focus();

  // Navigate to settings
  navigatorKey.currentState?.pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const SettingsWindow()),
    (_) => false,
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const _HiddenHome(),
    );
  }
}

class _HiddenHome extends StatefulWidget {
  const _HiddenHome();

  @override
  State<_HiddenHome> createState() => _HiddenHomeState();
}

class _HiddenHomeState extends State<_HiddenHome> with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() async {
    // Hide instead of close — tray app stays alive
    await windowManager.hide();
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
