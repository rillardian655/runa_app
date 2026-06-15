import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

class StatusService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Post a text status
  Future<void> postTextStatus({
    required String uid,
    required String username,
    required String photoUrl,
    required String content,
    required int bgColorValue,
  }) async {
    final now = DateTime.now();
    final expiresAt = now.add(const Duration(hours: 24));

    await _firestore.collection('statuses').add({
      'uid': uid,
      'username': username,
      'photoUrl': photoUrl,
      'content': content,
      'type': 'text',
      'bgColor': bgColorValue,
      'timestamp': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'viewedBy': [],
    });
  }

  /// Post an image status (Base64 encoded)
  Future<void> postImageStatus({
    required String uid,
    required String username,
    required String photoUrl,
    required XFile imageFile,
  }) async {
    final bytes = await imageFile.readAsBytes();
    final base64Image = 'data:image/jpeg;base64,${base64Encode(bytes)}';

    final now = DateTime.now();
    final expiresAt = now.add(const Duration(hours: 24));

    await _firestore.collection('statuses').add({
      'uid': uid,
      'username': username,
      'photoUrl': photoUrl,
      'content': base64Image,
      'type': 'image',
      'bgColor': 0xFF000000,
      'timestamp': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'viewedBy': [],
    });
  }

  /// Get ALL public statuses within 24h, grouped by user.
  /// Own status is always sorted first.
  Stream<List<Map<String, dynamic>>> getPublicStatuses(String currentUid) {
    final cutoff = Timestamp.fromDate(DateTime.now().subtract(const Duration(hours: 24)));

    return _firestore
        .collection('statuses')
        .where('timestamp', isGreaterThan: cutoff)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      // Group statuses by user
      final Map<String, Map<String, dynamic>> grouped = {};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final uid = data['uid'] as String;
        if (!grouped.containsKey(uid)) {
          grouped[uid] = {
            'uid': uid,
            'username': data['username'] ?? 'Unknown',
            'photoUrl': data['photoUrl'] ?? '',
            'statuses': <Map<String, dynamic>>[],
            'latestTimestamp': data['timestamp'],
          };
        }
        (grouped[uid]!['statuses'] as List<Map<String, dynamic>>).add({
          'id': doc.id,
          ...data,
        });
      }

      // Sort: own status first, then by latest timestamp
      final list = grouped.values.toList();
      list.sort((a, b) {
        if (a['uid'] == currentUid) return -1;
        if (b['uid'] == currentUid) return 1;
        final aTs = a['latestTimestamp'] as Timestamp;
        final bTs = b['latestTimestamp'] as Timestamp;
        return bTs.compareTo(aTs);
      });

      return list;
    });
  }

  /// Get own statuses
  Stream<List<Map<String, dynamic>>> getMyStatuses(String uid) {
    final cutoff = Timestamp.fromDate(DateTime.now().subtract(const Duration(hours: 24)));
    return _firestore
        .collection('statuses')
        .where('uid', isEqualTo: uid)
        .where('timestamp', isGreaterThan: cutoff)
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList());
  }

  /// Mark status as viewed by currentUid
  Future<void> markAsViewed(String statusId, String currentUid) async {
    try {
      await _firestore.collection('statuses').doc(statusId).update({
        'viewedBy': FieldValue.arrayUnion([currentUid]),
      });
    } catch (e) {
      debugPrint('Error marking as viewed: $e');
    }
  }

  /// Delete own status
  Future<void> deleteStatus(String statusId) async {
    await _firestore.collection('statuses').doc(statusId).delete();
  }

  /// Clean up expired statuses (older than 24h)
  /// Call this periodically or on app start
  Future<void> cleanupExpiredStatuses() async {
    try {
      final now = Timestamp.fromDate(DateTime.now());
      final expired = await _firestore
          .collection('statuses')
          .where('expiresAt', isLessThan: now)
          .get();

      for (var doc in expired.docs) {
        await doc.reference.delete();
      }
      if (expired.docs.isNotEmpty) {
        debugPrint('Cleaned up ${expired.docs.length} expired statuses');
      }
    } catch (e) {
      debugPrint('Error cleaning up statuses: $e');
    }
  }

  /// Check if all statuses from a user group have been viewed by currentUid
  bool allViewed(List<Map<String, dynamic>> statuses, String currentUid) {
    return statuses.every((s) {
      final viewedBy = List<String>.from(s['viewedBy'] ?? []);
      return viewedBy.contains(currentUid);
    });
  }
}
