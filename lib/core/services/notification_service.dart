import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class NotificationService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> initialize(String userId) async {
    // Request permission for iOS/Web
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('User granted permission');
      
      // Get the token
      String? token;
      if (kIsWeb) {
        // VAPID key is required for Web FCM
        token = await _firebaseMessaging.getToken(
          vapidKey: 'YOUR_PUBLIC_VAPID_KEY_HERE', // Needs to be configured in Firebase Console
        );
      } else {
        token = await _firebaseMessaging.getToken();
      }

      if (token != null) {
        await _saveTokenToDatabase(userId, token);
      }

      // Listen for token refresh
      _firebaseMessaging.onTokenRefresh.listen((newToken) {
        _saveTokenToDatabase(userId, newToken);
      });

      // Handle messages while the app is in the foreground
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('Got a message whilst in the foreground!');
        debugPrint('Message data: \${message.data}');

        if (message.notification != null) {
          debugPrint('Message also contained a notification: \${message.notification}');
          // Usually you would show a local notification here
        }
      });
    } else {
      debugPrint('User declined or has not accepted permission');
    }
  }

  Future<void> _saveTokenToDatabase(String userId, String token) async {
    await _firestore.collection('users').doc(userId).set(
      {'fcmToken': token},
      SetOptions(merge: true),
    );
  }
}
