import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// OneSignal App ID — khusus untuk kirim notifikasi background
const String _kOneSignalAppId = '7b94f919-28fb-4379-bfda-ca4b5cf6ef85';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  FlutterLocalNotificationsPlugin? _localNotificationsPlugin;
  bool _initialized = false;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Chat id currently open on screen. Message notifications for this chat are
  /// suppressed so the user isn't notified about the conversation they're in.
  static String? activeChatId;

  final StreamController<String> _onNotificationTapController = StreamController<String>.broadcast();
  Stream<String> get onNotificationTap => _onNotificationTapController.stream;

  Future<void> initialize(String userId) async {
    if (!kIsWeb && !Platform.isLinux && !_initialized) {
      await _initLocalNotifications();
      await _initOneSignal(userId);
      _initialized = true;
    }
  }

  /// Inisialisasi OneSignal dan daftarkan player ID ke database
  Future<void> _initOneSignal(String userId) async {
    try {
      OneSignal.initialize(_kOneSignalAppId);

      // Minta izin notifikasi dari pengguna (Android 13+ / iOS)
      await OneSignal.Notifications.requestPermission(true);

      // Hubungkan OneSignal subscription dengan user ID kita
      await OneSignal.login(userId);

      // Ambil OneSignal Subscription ID (player ID) dan simpan ke database
      final subscriptionId = OneSignal.User.pushSubscription.id;
      if (subscriptionId != null && subscriptionId.isNotEmpty) {
        debugPrint('[NotificationService] OneSignal ID: $subscriptionId');
        await _saveTokenToDatabase(userId, subscriptionId);
      }

      // Listen jika subscription ID berubah (misalnya setelah reinstall)
      OneSignal.User.pushSubscription.addObserver((state) {
        final newId = state.current.id;
        if (newId != null && newId.isNotEmpty) {
          _saveTokenToDatabase(userId, newId);
        }
      });

      // Handle notifikasi saat app di FOREGROUND (tampilkan sebagai lokal)
      OneSignal.Notifications.addForegroundWillDisplayListener((event) {
        // Biarkan OneSignal tampilkan notifikasi di foreground juga
        event.notification.display();
      });

      // Handle ketika notifikasi di-tap
      OneSignal.Notifications.addClickListener((event) {
        final data = event.notification.additionalData;
        if (data != null) {
          final chatId = data['chatId'] as String?;
          final senderId = data['senderId'] as String?;
          if (senderId != null) {
            _onNotificationTapController.add('/chat/$senderId');
          } else if (chatId != null) {
            _onNotificationTapController.add('/chat/$chatId');
          }
        }
      });

      debugPrint('[NotificationService] OneSignal initialized successfully');
    } catch (e, st) {
      debugPrint('[NotificationService] Failed to init OneSignal: $e\n$st');
    }
  }

  Future<void> _initLocalNotifications() async {
    try {
      _localNotificationsPlugin = FlutterLocalNotificationsPlugin();

      const initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/launcher_icon');
      const initializationSettingsIOS = DarwinInitializationSettings();
      const initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsIOS,
      );

      await _localNotificationsPlugin!.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          final payload = response.payload;
          if (payload != null) {
            _onNotificationTapController.add(payload);
          }
        },
      );

      final android = _localNotificationsPlugin!
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        await android.requestNotificationsPermission();
        await android.createNotificationChannel(const AndroidNotificationChannel(
          'runa_chat_channel',
          'Chat Messages',
          description: 'Notifications for new chat messages',
          importance: Importance.high,
        ));
        await android.createNotificationChannel(const AndroidNotificationChannel(
          'runa_call_channel',
          'Incoming Calls',
          description: 'Notifications for incoming calls',
          importance: Importance.max,
        ));
      }

      debugPrint('[NotificationService] Local notifications initialized');
    } catch (e, stackTrace) {
      debugPrint('[NotificationService] Failed to initialize: $e');
      debugPrint('[NotificationService] Stack: $stackTrace');
      _localNotificationsPlugin = null;
    }
  }

  Future<void> showMessageNotification({
    required String senderName,
    required String message,
    String? payload,
  }) async {
    if (_localNotificationsPlugin == null) return;
    try {
      const androidDetails = AndroidNotificationDetails(
        'runa_chat_channel',
        'Chat Messages',
        channelDescription: 'Notifications for new chat messages',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
      );
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      const details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );
      await _localNotificationsPlugin!.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        senderName,
        message,
        details,
        payload: payload,
      );
    } catch (e, stackTrace) {
      debugPrint('[NotificationService] Failed to show message notification: $e');
      debugPrint('[NotificationService] Stack: $stackTrace');
    }
  }

  Future<void> showCallNotification({
    required String callerName,
    required String callId,
  }) async {
    if (_localNotificationsPlugin == null) return;
    try {
      const androidDetails = AndroidNotificationDetails(
        'runa_call_channel',
        'Incoming Calls',
        channelDescription: 'Notifications for incoming calls',
        importance: Importance.max,
        priority: Priority.max,
        fullScreenIntent: true,
        showWhen: true,
      );
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      const details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );
      await _localNotificationsPlugin!.show(
        callId.hashCode,
        'Incoming Call',
        '$callerName is calling...',
        details,
        payload: 'call:$callId',
      );
    } catch (e, stackTrace) {
      debugPrint('[NotificationService] Failed to show call notification: $e');
      debugPrint('[NotificationService] Stack: $stackTrace');
    }
  }

  /// Dismiss the incoming-call notification once the call is answered, rejected
  /// or it stops ringing.
  Future<void> cancelCallNotification(String callId) async {
    try {
      await _localNotificationsPlugin?.cancel(callId.hashCode);
    } catch (e) {
      debugPrint('[NotificationService] Failed to cancel call notification: $e');
    }
  }

  Future<void> _saveTokenToDatabase(String userId, String token) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'fcm_token': token,
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[NotificationService] Failed to save token: $e');
    }
  }
}
