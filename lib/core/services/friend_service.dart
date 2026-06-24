import 'package:cloud_firestore/cloud_firestore.dart';

class FriendService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get accepted friends as a realtime stream
  Stream<List<Map<String, dynamic>>> getFriends(String currentUid) {
    return _firestore
        .collection('friends')
        .where('user_id', isEqualTo: currentUid)
        .where('status', isEqualTo: 'accepted')
        .snapshots()
        .asyncMap((snapshot) async {
      final List<Map<String, dynamic>> friends = [];
      for (final doc in snapshot.docs) {
        final row = doc.data();
        final uid = row['friend_id'] as String;
        final userDoc = await _firestore.collection('users').doc(uid).get();
        if (userDoc.exists) {
          final userData = userDoc.data()!;
          friends.add({
            'uid': uid,
            'name': userData['username'] ?? 'Unknown',
            'status': userData['bio'] ?? 'Available',
            'photoUrl': userData['photo_url'] ?? '',
          });
        }
      }
      return friends;
    });
  }

  /// Get just the UIDs of accepted friends
  Future<List<String>> getFriendUids(String currentUid) async {
    final snapshot = await _firestore
        .collection('friends')
        .where('user_id', isEqualTo: currentUid)
        .where('status', isEqualTo: 'accepted')
        .get();
    return snapshot.docs.map((r) => r.data()['friend_id'] as String).toList();
  }

  /// Get pending friend requests (received)
  Stream<List<Map<String, dynamic>>> getPendingRequests(String currentUid) {
    return _firestore
        .collection('friends')
        .where('user_id', isEqualTo: currentUid)
        .where('status', isEqualTo: 'requested')
        .snapshots()
        .asyncMap((snapshot) async {
      final List<Map<String, dynamic>> requests = [];
      for (final doc in snapshot.docs) {
        final row = doc.data();
        final uid = row['friend_id'] as String;
        final userDoc = await _firestore.collection('users').doc(uid).get();
        if (userDoc.exists) {
          final userData = userDoc.data()!;
          requests.add({
            'uid': uid,
            'name': userData['username'] ?? 'Unknown',
            'status': userData['bio'] ?? 'Available',
            'photoUrl': userData['photo_url'] ?? '',
          });
        }
      }
      return requests;
    });
  }

  /// Get sent friend requests (pending on sender side)
  Stream<List<Map<String, dynamic>>> getSentRequests(String currentUid) {
    return _firestore
        .collection('friends')
        .where('user_id', isEqualTo: currentUid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .asyncMap((snapshot) async {
      final List<Map<String, dynamic>> requests = [];
      for (final doc in snapshot.docs) {
        final row = doc.data();
        final uid = row['friend_id'] as String;
        final userDoc = await _firestore.collection('users').doc(uid).get();
        if (userDoc.exists) {
          final userData = userDoc.data()!;
          requests.add({
            'uid': uid,
            'name': userData['username'] ?? 'Unknown',
            'status': userData['bio'] ?? 'Available',
            'photoUrl': userData['photo_url'] ?? '',
          });
        }
      }
      return requests;
    });
  }

  /// Get all users for discovery
  Stream<List<Map<String, dynamic>>> getAllUsers(String currentUid) {
    return _firestore
        .collection('users')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .where((doc) => doc.data()['uid'] != currentUid)
            .map((doc) {
                  final r = doc.data();
                  return {
                    'uid': r['uid'],
                    'username': r['username'] ?? 'Unknown',
                    'bio': r['bio'] ?? 'Available',
                    'photoUrl': r['photo_url'] ?? '',
                  };
                })
            .toList());
  }

  /// Search users by username (case-insensitive) - partial matching handled locally for simplicity in Firebase
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    if (query.isEmpty) return [];
    if (query.startsWith('@')) query = query.substring(1);
    final lowerQuery = query.toLowerCase();

    // Firebase doesn't have native case-insensitive LIKE. 
    // We fetch all users and filter locally (ok for small scale app).
    final snapshot = await _firestore.collection('users').limit(100).get();

    final results = snapshot.docs.where((doc) {
      final username = (doc.data()['username'] as String? ?? '').toLowerCase();
      return username.contains(lowerQuery);
    }).map((doc) {
      final r = doc.data();
      return {
        'uid': r['uid'],
        'username': r['username'] ?? 'Unknown',
        'bio': r['bio'] ?? 'Available',
        'photoUrl': r['photo_url'] ?? '',
      };
    }).toList();

    return results.take(20).toList();
  }

  /// Send a friend request
  Future<void> addFriendByUid(String currentUid, String targetUid) async {
    if (targetUid == currentUid) throw Exception('Cannot add yourself');

    // Sender side: pending
    await _firestore.collection('friends').doc('${currentUid}_$targetUid').set({
      'user_id': currentUid,
      'friend_id': targetUid,
      'status': 'pending',
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Receiver side: requested
    await _firestore.collection('friends').doc('${targetUid}_$currentUid').set({
      'user_id': targetUid,
      'friend_id': currentUid,
      'status': 'requested',
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Accept a friend request
  Future<void> acceptFriendRequest(
      String currentUid, String requesterUid) async {

    await _firestore.collection('friends').doc('${currentUid}_$requesterUid').update({
      'status': 'accepted', 
      'updated_at': FieldValue.serverTimestamp()
    });

    await _firestore.collection('friends').doc('${requesterUid}_$currentUid').update({
      'status': 'accepted', 
      'updated_at': FieldValue.serverTimestamp()
    });
  }

  /// Reject a friend request
  Future<void> rejectFriendRequest(
      String currentUid, String requesterUid) async {
    
    await _firestore.collection('friends').doc('${currentUid}_$requesterUid').delete();
    await _firestore.collection('friends').doc('${requesterUid}_$currentUid').delete();
  }
}
