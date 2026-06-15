import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:runa_app/app/routes.dart';
import 'package:runa_app/app/theme.dart';
import 'package:runa_app/core/services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // TODO: Add firebase configuration using google-services.json
  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'AIzaSyBhXMt6b8Ih44h6fQ1sCErS6mqExp8wJAI',
        appId: '1:762306964857:web:9cbdd52195759875c113a8',
        messagingSenderId: '762306964857',
        projectId: 'runa-f1e8e',
        authDomain: 'runa-f1e8e.firebaseapp.com',
        storageBucket: 'runa-f1e8e.firebasestorage.app',
        measurementId: 'G-VQX24PJMPJ',
      ),
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
