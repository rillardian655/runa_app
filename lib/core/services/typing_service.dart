import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

class TypingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? _myUid;
  String? _chatId;
  StreamSubscription? _subscription;

  Timer? _selfStopTimer;
  Timer? _friendExpiryTimer;

  final _friendTypingController = StreamController<bool>.broadcast();

  Stream<bool> get friendTyping => _friendTypingController.stream;

  void subscribe(String chatId, String myUid) {
    _chatId = chatId;
    _myUid = myUid;
    
    _subscription = _firestore
        .collection('typing_status')
        .doc(chatId)
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists) return;
      final data = snapshot.data();
      if (data == null) return;
      
      bool friendIsTyping = false;
      for (final key in data.keys) {
        if (key != _myUid && data[key] == true) {
          friendIsTyping = true;
          break;
        }
      }

      if (_friendTypingController.isClosed) return;
      _friendTypingController.add(friendIsTyping);

      _friendExpiryTimer?.cancel();
      if (friendIsTyping) {
        _friendExpiryTimer = Timer(const Duration(seconds: 5), () {
          if (!_friendTypingController.isClosed) {
            _friendTypingController.add(false);
          }
        });
      }
    });
  }

  void onTextChanged(bool hasText) {
    if (_chatId == null || _myUid == null) return;
    _sendTyping(hasText);
    _selfStopTimer?.cancel();
    if (hasText) {
      _selfStopTimer = Timer(
        const Duration(seconds: 3),
        () => _sendTyping(false),
      );
    }
  }

  void _sendTyping(bool typing) {
    if (_chatId == null || _myUid == null) return;
    _firestore.collection('typing_status').doc(_chatId!).set({
      _myUid!: typing,
    }, SetOptions(merge: true)).catchError((_) {});
  }

  Future<void> dispose() async {
    _selfStopTimer?.cancel();
    _friendExpiryTimer?.cancel();
    _sendTyping(false);
    await _subscription?.cancel();
    _subscription = null;
    await _friendTypingController.close();
  }
}
