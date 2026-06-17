import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:provider/provider.dart';
import 'package:runa_app/app/routes.dart';
import 'package:runa_app/app/theme.dart';
import 'package:runa_app/core/services/auth_service.dart';
import 'package:runa_app/core/services/notification_service.dart';
import 'package:runa_app/firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Wajib didaftarkan SEBELUM Firebase.initializeApp()
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint("Firebase not initialized yet or config missing: $e");
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
      ],
      child: const RunaApp(),
    ),
  );
}

class RunaApp extends StatelessWidget {
  const RunaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Ru.na',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system, // Or from SettingsProvider
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
