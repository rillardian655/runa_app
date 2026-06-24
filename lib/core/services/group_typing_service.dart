import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

class GroupTypingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? _myUid;
  String? _groupId;
  StreamSubscription? _subscription;

  Timer? _selfStopTimer;
  final Map<String, Timer> _expiryTimers = {};
  final Map<String, String> _typers = {};

  final _typersController = StreamController<List<String>>.broadcast();

  Stream<List<String>> get typers => _typersController.stream;

  void subscribe(String groupId, String myUid) {
    _groupId = groupId;
    _myUid = myUid;
    
    _subscription = _firestore
        .collection('typing_group_status')
        .doc(groupId)
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists) return;
      final data = snapshot.data();
      if (data == null) return;
      
      for (final key in data.keys) {
        if (key == _myUid) continue;
        
        final val = data[key] as Map<String, dynamic>?;
        if (val == null) continue;
        
        final isTyping = val['typing'] == true;
        final name = (val['name'] as String?) ?? 'Someone';

        _expiryTimers[key]?.cancel();
        
        if (isTyping) {
          _typers[key] = name;
          _expiryTimers[key] = Timer(const Duration(seconds: 5), () {
            _typers.remove(key);
            _expiryTimers.remove(key);
            _emit();
          });
        } else {
          _typers.remove(key);
          _expiryTimers.remove(key);
        }
      }
      _emit();
    });
  }

  void _emit() {
    if (_typersController.isClosed) return;
    _typersController.add(_typers.values.toList());
  }

  void onTextChanged(bool hasText, String myName) {
    if (_groupId == null || _myUid == null) return;
    _sendTyping(hasText, myName);
    _selfStopTimer?.cancel();
    if (hasText) {
      _selfStopTimer = Timer(
        const Duration(seconds: 3),
        () => _sendTyping(false, myName),
      );
    }
  }

  void _sendTyping(bool typing, String myName) {
    if (_groupId == null || _myUid == null) return;
    _firestore.collection('typing_group_status').doc(_groupId!).set({
      _myUid!: {
        'typing': typing,
        'name': myName,
        'timestamp': FieldValue.serverTimestamp(),
      }
    }, SetOptions(merge: true)).catchError((_) {});
  }

  Future<void> dispose() async {
    _selfStopTimer?.cancel();
    for (final t in _expiryTimers.values) {
      t.cancel();
    }
    _expiryTimers.clear();
    _sendTyping(false, '');
    
    await _subscription?.cancel();
    _subscription = null;
    await _typersController.close();
  }
}
