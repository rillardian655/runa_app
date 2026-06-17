import 'package:cloud_firestore/cloud_firestore.dart';

class FriendService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Mendapatkan daftar teman (hanya yang statusnya 'accepted')
  Stream<List<Map<String, dynamic>>> getFriends(String currentUid) {
    return _firestore
        .collection('users')
        .doc(currentUid)
        .collection('friends')
        .snapshots()
        .asyncMap((snapshot) async {
      List<Map<String, dynamic>> friends = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final status = data['status'] ?? 'accepted'; // Fallback for old data

        if (status == 'accepted') {
          var userDoc = await _firestore.collection('users').doc(doc.id).get();
          if (userDoc.exists) {
            friends.add({
              'uid': userDoc.id,
              'name': userDoc.data()?['username'] ?? 'Unknown',
              'status': userDoc.data()?['bio'] ?? 'Available',
              'photoUrl': userDoc.data()?['photoUrl'] ?? '',
            });
          }
        }
      }
      return friends;
    });
  }

  /// Returns just the UIDs of accepted friends — used by StatusService
  Future<List<String>> getFriendUids(String currentUid) async {
    final snapshot = await _firestore
        .collection('users')
        .doc(currentUid)
        .collection('friends')
        .where('status', isEqualTo: 'accepted')
        .get();
    return snapshot.docs.map((d) => d.id).toList();
  }

  // Mendapatkan daftar permintaan pertemanan (status 'requested')
  Stream<List<Map<String, dynamic>>> getPendingRequests(String currentUid) {
    return _firestore
        .collection('users')
        .doc(currentUid)
        .collection('friends')
        .where('status', isEqualTo: 'requested')
        .snapshots()
        .asyncMap((snapshot) async {
      List<Map<String, dynamic>> requests = [];
      for (var doc in snapshot.docs) {
        var userDoc = await _firestore.collection('users').doc(doc.id).get();
        if (userDoc.exists) {
          requests.add({
            'uid': userDoc.id,
            'name': userDoc.data()?['username'] ?? 'Unknown',
            'status': userDoc.data()?['bio'] ?? 'Available',
          });
        }
      }
      return requests;
    });
  }

  // Mencari pengguna berdasarkan awalan nama (seperti IG)
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    if (query.isEmpty) return [];

    // Jika user mengetik '@', hapus
    if (query.startsWith('@')) {
      query = query.substring(1);
    }
    
    String lowerQuery = query.toLowerCase();
    print('🔍 [SearchUsers] Searching for: "$lowerQuery"');

    var snapshot = await _firestore.collection('users').get();
    print('🔍 [SearchUsers] Total documents in "users" collection: ${snapshot.docs.length}');
    
    List<Map<String, dynamic>> results = [];

    for (var doc in snapshot.docs) {
      final data = doc.data();
      print('🔍 [SearchUsers] Found user doc: id=${doc.id}, data=$data');
      String username = (data['username'] ?? '').toString().toLowerCase();
      if (username.contains(lowerQuery)) {
        results.add({
          'uid': doc.id,
          'username': data['username'],
          'bio': data['bio'] ?? 'Available',
          'photoUrl': data['photoUrl'] ?? '',
        });
      }
    }
    print('🔍 [SearchUsers] Matching results: ${results.length}');
    return results;
  }

  // Mengirim permintaan pertemanan
  Future<void> addFriendByUid(String currentUid, String targetUid) async {
    if (targetUid == currentUid) throw Exception("Cannot add yourself");

    await _firestore
        .collection('users')
        .doc(currentUid)
        .collection('friends')
        .doc(targetUid)
        .set({
          'timestamp': FieldValue.serverTimestamp(),
          'status': 'pending'
        });
        
    await _firestore
        .collection('users')
        .doc(targetUid)
        .collection('friends')
        .doc(currentUid)
        .set({
          'timestamp': FieldValue.serverTimestamp(),
          'status': 'requested'
        });
  }

  // Menerima permintaan pertemanan
  Future<void> acceptFriendRequest(String currentUid, String requesterUid) async {
    await _firestore
        .collection('users')
        .doc(currentUid)
        .collection('friends')
        .doc(requesterUid)
        .update({'status': 'accepted'});
        
    await _firestore
        .collection('users')
        .doc(requesterUid)
        .collection('friends')
        .doc(currentUid)
        .update({'status': 'accepted'});
  }

  // Menolak permintaan pertemanan
  Future<void> rejectFriendRequest(String currentUid, String requesterUid) async {
    await _firestore
        .collection('users')
        .doc(currentUid)
        .collection('friends')
        .doc(requesterUid)
        .delete();
        
    await _firestore
        .collection('users')
        .doc(requesterUid)
        .collection('friends')
        .doc(currentUid)
        .delete();
  }
  // Mendapatkan daftar semua user
  Stream<List<Map<String, dynamic>>> getAllUsers(String currentUid) {
    return _firestore.collection('users').snapshots().map((snapshot) {
      return snapshot.docs
          .where((doc) => doc.id != currentUid)
          .map((doc) => {
                'uid': doc.id,
                ...doc.data(),
              })
          .toList();
    });
  }

  // Mendapatkan daftar permintaan pertemanan yang dikirim (status 'pending')
  Stream<List<Map<String, dynamic>>> getSentRequests(String currentUid) {
    return _firestore
        .collection('users')
        .doc(currentUid)
        .collection('friends')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .asyncMap((snapshot) async {
      List<Map<String, dynamic>> requests = [];
      for (var doc in snapshot.docs) {
        var userDoc = await _firestore.collection('users').doc(doc.id).get();
        if (userDoc.exists) {
          requests.add({
            'uid': userDoc.id,
            'name': userDoc.data()?['username'] ?? 'Unknown',
            'status': userDoc.data()?['bio'] ?? 'Available',
            'photoUrl': userDoc.data()?['photoUrl'] ?? '',
          });
        }
      }
      return requests;
    });
  }
}
