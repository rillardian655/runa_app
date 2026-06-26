import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:runa_app/firebase_options.dart';
import 'package:provider/provider.dart';
import 'package:runa_app/app/routes.dart';
import 'package:runa_app/app/theme.dart';
import 'package:runa_app/core/services/auth_service.dart';
import 'package:runa_app/core/services/theme_service.dart';
import 'dart:async';
import 'package:runa_app/core/services/app_update_service.dart';
import 'package:runa_app/core/services/notification_service.dart';
import 'package:runa_app/features/call/dynamic_island.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => ThemeService()),
      ],
      child: const RunaApp(),
    ),
  );
}

class RunaApp extends StatefulWidget {
  const RunaApp({super.key});

  @override
  State<RunaApp> createState() => _RunaAppState();
}

class _RunaAppState extends State<RunaApp> with WidgetsBindingObserver {
  bool _updateChecked = false;
  GoRouter? _router;
  StreamSubscription? _notifSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notifSub = NotificationService.instance.onNotificationTap.listen((payload) {
      if (_router != null) {
        _router!.push(payload);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notifSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Keep the user's online/last-seen status in sync with app visibility.
    final auth = context.read<AuthService>();
    if (state == AppLifecycleState.resumed) {
      auth.setPresence('online');
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      auth.setPresence('offline');
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<ThemeService>().themeMode;
    final authService = context.read<AuthService>();
    
    // It's safe to use a memoized router or just recreate. Actually, to avoid recreating GoRouter on every build:
    // We'll create a GoRouter provider or just create it once. Let's create it once using an internal variable.
    // Wait, since we need to do this cleanly:
    
    return MaterialApp.router(
      title: 'Ru.na',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: _router ??= createAppRouter(authService),
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        // Check for updates using a context below MaterialApp
        if (!_updateChecked) {
          _updateChecked = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _checkForUpdates(context);
          });
        }

        return Stack(
          children: [
            child ?? const SizedBox.shrink(),
            const DynamicIsland(),
          ],
        );
      },
    );
  }

  Future<void> _checkForUpdates(BuildContext context) async {
    try {
      final updateInfo = await AppUpdateService.checkForUpdate();
      if (updateInfo != null && mounted) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted && context.mounted) {
          AppUpdateService.showUpdateDialog(context, updateInfo);
        }
      }
    } catch (e) {
      debugPrint('[RunaApp] Update check failed: $e');
    }
  }
}
