import 'package:cloud_firestore/cloud_firestore.dart';

class FriendService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Mendapatkan daftar teman (Stream)
  Stream<List<Map<String, dynamic>>> getFriends(String currentUid) {
    return _firestore
        .collection('users')
        .doc(currentUid)
        .collection('friends')
        .snapshots()
        .asyncMap((snapshot) async {
      List<Map<String, dynamic>> friends = [];
      for (var doc in snapshot.docs) {
        // Ambil data detail user dari collection users
        var userDoc = await _firestore.collection('users').doc(doc.id).get();
        if (userDoc.exists) {
          friends.add({
            'uid': userDoc.id,
            'name': userDoc.data()?['username'] ?? 'Unknown',
            'status': userDoc.data()?['bio'] ?? 'Available',
          });
        }
      }
      return friends;
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

  // Mengirim permintaan pertemanan berdasarkan UID target
  Future<void> addFriendByUid(String currentUid, String targetUid) async {
    if (targetUid == currentUid) throw Exception("Cannot add yourself");

    // Untuk demo: Langsung tambahkan secara dua arah (mutual)
    await _firestore
        .collection('users')
        .doc(currentUid)
        .collection('friends')
        .doc(targetUid)
        .set({'timestamp': FieldValue.serverTimestamp()});
        
    await _firestore
        .collection('users')
        .doc(targetUid)
        .collection('friends')
        .doc(currentUid)
        .set({'timestamp': FieldValue.serverTimestamp()});
  }
}
