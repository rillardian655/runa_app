import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Background message handler — harus top-level function (di luar class)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Background message received: ${message.messageId}');
}

class NotificationService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  // Android notification channel — harus sama dengan channelId di functions/index.js
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'runa_chat_channel',
    'Pesan Chat Runa',
    description: 'Notifikasi untuk pesan chat baru di Runa App',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  Future<void> initialize(String userId) async {
    // Setup local notifications & buat channel Android
    await _setupLocalNotifications();

    // Request permission notifikasi (iOS + Android 13+)
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
      announcement: false,
      carPlay: false,
      criticalAlert: false,
    );

    debugPrint('Notification status: ${settings.authorizationStatus}');

    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      // Dapatkan FCM token
      String? token;
      if (kIsWeb) {
        token = await _firebaseMessaging.getToken(
          vapidKey: 'YOUR_PUBLIC_VAPID_KEY_HERE',
        );
      } else {
        token = await _firebaseMessaging.getToken();
      }

      debugPrint('FCM Token: $token');

      if (token != null) {
        await _saveTokenToDatabase(userId, token);
      }

      // Update token jika di-refresh oleh Firebase
      _firebaseMessaging.onTokenRefresh.listen((newToken) {
        _saveTokenToDatabase(userId, newToken);
      });

      // Handle pesan saat app FOREGROUND → tampilkan local notification
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('Foreground message: ${message.notification?.title}');
        _showLocalNotification(message);
      });
    } else {
      debugPrint('Notification permission denied by user');
    }
  }

  Future<void> _setupLocalNotifications() async {
    // Buat Android notification channel (wajib untuk Android 8.0+)
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    // Request POST_NOTIFICATIONS permission (Android 13+)
    if (!kIsWeb && Platform.isAndroid) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('launcher_icon');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(initSettings);
  }

  // Tampilkan notifikasi lokal saat app di foreground
  void _showLocalNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          icon: 'launcher_icon',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  Future<void> _saveTokenToDatabase(String userId, String token) async {
    await _firestore.collection('users').doc(userId).set(
      {'fcmToken': token},
      SetOptions(merge: true),
    );
    debugPrint('FCM token saved for user: $userId');
  }
}
