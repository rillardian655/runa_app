import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:runa_app/core/services/notification_service.dart';
import 'package:runa_app/core/services/encryption_service.dart';

class AuthService extends ChangeNotifier {
  final NotificationService _notificationService = NotificationService.instance;
  final EncryptionService _encryptionService = EncryptionService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  StreamSubscription? _messageSubscription;
  String? _lastNotifiedMessageId;
  bool _messageListenerPrimed = false;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  AuthService() {
    _auth.authStateChanges().listen((user) async {
      _isInitialized = true;
      if (user != null) {
        try {
          await _notificationService.initialize(user.uid);
          await _updatePresence(user.uid, 'online');
          _startMessageListener(user.uid);
        } catch (e, stackTrace) {
          debugPrint('[AuthService] Error during auth state change: $e');
          debugPrint('[AuthService] Stack: $stackTrace');
        }
      } else {
        _stopMessageListener();
      }
      notifyListeners();
    });
  }

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  void _startMessageListener(String currentUserId) {
    _stopMessageListener();

    _messageSubscription = _firestore
        .collection('messages')
        .where('receiver_id', isEqualTo: currentUserId)
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .listen((snapshot) async {
      if (snapshot.docs.isEmpty) return;

      final latestMessage = snapshot.docs.first.data();
      final messageId = snapshot.docs.first.id;

      if (!_messageListenerPrimed) {
        _messageListenerPrimed = true;
        _lastNotifiedMessageId = messageId;
        return;
      }

      if (messageId == _lastNotifiedMessageId) return;
      _lastNotifiedMessageId = messageId;

      final senderId = latestMessage['sender_id'] as String;
      final chatId = latestMessage['chat_id'] as String;
      final type = latestMessage['type'] as String? ?? 'text';

      if (chatId == NotificationService.activeChatId) return;

      try {
        final senderDoc = await _firestore.collection('users').doc(senderId).get();
        final senderName = senderDoc.data()?['username'] as String? ?? 'Unknown';

        String messageText = '[Encrypted Message]';
        if (type == 'text') {
          final encryptedText = latestMessage['text'] as String? ?? '';
          if (encryptedText.isNotEmpty) {
            try {
              messageText = await _encryptionService.decryptMessage(encryptedText, chatId);
            } catch (_) {
              messageText = '[Encrypted Message]';
            }
          }
        } else if (type == 'image') {
          messageText = 'Photo';
        } else if (type == 'video') {
          messageText = 'Video';
        } else if (type == 'audio') {
          messageText = 'Audio';
        } else if (type == 'file') {
          messageText = 'File';
        }

        await _notificationService.showMessageNotification(
          senderName: senderName,
          message: messageText,
          payload: 'chat:$chatId',
        );
      } catch (e, stackTrace) {
        debugPrint('[AuthService] Error showing notification: $e');
        debugPrint('[AuthService] Stack: $stackTrace');
      }
    });
  }

  void _stopMessageListener() {
    _messageSubscription?.cancel();
    _messageSubscription = null;
    _messageListenerPrimed = false;
    _lastNotifiedMessageId = null;
  }

  Future<void> loginWithEmail(String email, String password) async {
    final response = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    if (response.user != null) {
      await _updatePresence(response.user!.uid, 'online');
    }
    notifyListeners();
  }

  Future<void> registerWithEmail(
      String email, String password, String username) async {
    final response = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    if (response.user != null) {
      await _firestore.collection('users').doc(response.user!.uid).set({
        'uid': response.user!.uid,
        'email': email,
        'username': username,
        'photo_url': '',
        'banner_url': '',
        'bio': 'Available',
        'presence_status': 'online',
        'last_seen': FieldValue.serverTimestamp(),
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _stopMessageListener();
    final uid = currentUser?.uid;
    if (uid != null) {
      await _updatePresence(uid, 'offline');
    }
    await _auth.signOut();
    notifyListeners();
  }

  @override
  void dispose() {
    _stopMessageListener();
    super.dispose();
  }

  Future<Map<String, dynamic>?> getUserData(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    return doc.data();
  }

  Future<void> setPresence(String status) async {
    final uid = currentUser?.uid;
    if (uid != null) await _updatePresence(uid, status);
  }

  Future<void> _updatePresence(String uid, String status) async {
    try {
      await _firestore.collection('users').doc(uid).set({
        'presence_status': status,
        'last_seen': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[AuthService] Failed to update presence: $e');
    }
  }

  Future<void> updateProfile({
    required String uid,
    String? username,
    String? bio,
    String? photoUrl,
    String? bannerUrl,
  }) async {
    final updates = <String, dynamic>{
      'updated_at': FieldValue.serverTimestamp(),
    };
    if (username != null) updates['username'] = username;
    if (bio != null) updates['bio'] = bio;
    if (photoUrl != null) updates['photo_url'] = photoUrl;
    if (bannerUrl != null) updates['banner_url'] = bannerUrl;

    await _firestore.collection('users').doc(uid).set(updates, SetOptions(merge: true));
  }
}
