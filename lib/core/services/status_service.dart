import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class StatusService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

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
      'photo_url': photoUrl,
      'content': content,
      'type': 'text',
      'bg_color': bgColorValue,
      'viewed_by': [],
      'expires_at': expiresAt.toIso8601String(),
      'created_at': now.toIso8601String(),
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Post an image status (Base64 encoded for small images, or upload to storage)
  Future<void> postImageStatus({
    required String uid,
    required String username,
    required String photoUrl,
    required XFile imageFile,
    String? caption,
  }) async {
    final now = DateTime.now();
    final expiresAt = now.add(const Duration(hours: 24));

    String content;
    final bytes = await imageFile.readAsBytes();

    if (bytes.length < 500 * 1024) {
      // < 500KB: store as base64
      content = 'data:image/jpeg;base64,${base64Encode(bytes)}';
    } else {
      // Upload to Firebase Storage
      final fileName = '${uid}_${now.millisecondsSinceEpoch}.jpg';
      final ref = _storage.ref().child('status_media').child(fileName);
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      content = await ref.getDownloadURL();
    }

    await _firestore.collection('statuses').add({
      'uid': uid,
      'username': username,
      'photo_url': photoUrl,
      'content': content,
      'caption': caption,
      'type': 'image',
      'bg_color': 0xFF000000,
      'viewed_by': [],
      'expires_at': expiresAt.toIso8601String(),
      'created_at': now.toIso8601String(),
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Post a video status (uploaded to Firebase Storage)
  Future<void> postVideoStatus({
    required String uid,
    required String username,
    required String photoUrl,
    required XFile videoFile,
    String? caption,
  }) async {
    final now = DateTime.now();
    final expiresAt = now.add(const Duration(hours: 24));

    final fileName = '${uid}_${now.millisecondsSinceEpoch}.mp4';
    final bytes = await videoFile.readAsBytes();

    final ref = _storage.ref().child('status_media').child(fileName);
    await ref.putData(bytes, SettableMetadata(contentType: 'video/mp4'));
    final videoUrl = await ref.getDownloadURL();

    await _firestore.collection('statuses').add({
      'uid': uid,
      'username': username,
      'photo_url': photoUrl,
      'content': videoUrl,
      'caption': caption,
      'type': 'video',
      'bg_color': 0xFF000000,
      'viewed_by': [],
      'expires_at': expiresAt.toIso8601String(),
      'created_at': now.toIso8601String(),
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Get all public statuses within 24h, grouped by user
  Stream<List<Map<String, dynamic>>> getPublicStatuses(String currentUid) {
    final cutoff =
        DateTime.now().subtract(const Duration(hours: 24)).toIso8601String();

    return _firestore
        .collection('statuses')
        .where('created_at', isGreaterThanOrEqualTo: cutoff)
        .orderBy('created_at', descending: true)
        .snapshots()
        .map((snapshot) {
      final Map<String, Map<String, dynamic>> grouped = {};
      for (final doc in snapshot.docs) {
        final row = doc.data();
        row['id'] = doc.id;
        final uid = row['uid'] as String;
        if (!grouped.containsKey(uid)) {
          grouped[uid] = {
            'uid': uid,
            'username': row['username'] ?? 'Unknown',
            'photoUrl': row['photo_url'] ?? '',
            'statuses': <Map<String, dynamic>>[],
            'latestTimestamp': row['created_at'],
          };
        }
        (grouped[uid]!['statuses'] as List<Map<String, dynamic>>).add(row);
      }

      final list = grouped.values.toList();
      list.sort((a, b) {
        if (a['uid'] == currentUid) return -1;
        if (b['uid'] == currentUid) return 1;
        final aTs = a['latestTimestamp'] as String? ?? '';
        final bTs = b['latestTimestamp'] as String? ?? '';
        return bTs.compareTo(aTs);
      });

      return list;
    });
  }

  /// Get own statuses
  Stream<List<Map<String, dynamic>>> getMyStatuses(String uid) {
    final cutoff =
        DateTime.now().subtract(const Duration(hours: 24)).toIso8601String();

    return _firestore
        .collection('statuses')
        .where('uid', isEqualTo: uid)
        .orderBy('created_at', descending: false)
        .snapshots()
        .map((snapshot) {
           return snapshot.docs
             .where((doc) {
                final row = doc.data();
                return ((row['created_at'] as String?) ?? '').compareTo(cutoff) >= 0;
             })
             .map((doc) {
                final row = doc.data();
                row['id'] = doc.id;
                return row;
             }).toList();
        });
  }

  /// Mark status as viewed by currentUid
  Future<void> markAsViewed(String statusId, String currentUid) async {
    try {
      final docRef = _firestore.collection('statuses').doc(statusId);
      final doc = await docRef.get();

      if (!doc.exists) return;
      final viewedBy = List<String>.from(doc.data()?['viewed_by'] as List? ?? []);
      if (!viewedBy.contains(currentUid)) {
        viewedBy.add(currentUid);
        await docRef.update({'viewed_by': viewedBy});
      }
    } catch (e) {
      debugPrint('Error marking as viewed: $e');
    }
  }

  /// Delete own status
  Future<void> deleteStatus(String statusId) async {
    await _firestore.collection('statuses').doc(statusId).delete();
  }

  /// Clean up expired statuses
  Future<void> cleanupExpiredStatuses() async {
    try {
      final snapshot = await _firestore
          .collection('statuses')
          .where('expires_at', isLessThan: DateTime.now().toIso8601String())
          .get();
      
      final batch = _firestore.batch();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Error cleaning up statuses: $e');
    }
  }

  /// Check if all statuses from a user group have been viewed
  bool allViewed(List<Map<String, dynamic>> statuses, String currentUid) {
    return statuses.every((s) {
      final viewedBy = List<String>.from(s['viewed_by'] as List? ?? []);
      return viewedBy.contains(currentUid);
    });
  }
}
