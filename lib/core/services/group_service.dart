import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:runa_app/core/services/encryption_service.dart';

class GroupService {
  final EncryptionService _encryptionService = EncryptionService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Create a new group
  Future<String> createGroup({
    required String name,
    required String creatorId,
    required List<String> memberIds,
    String? groupIcon,
  }) async {
    if (!memberIds.contains(creatorId)) {
      memberIds.add(creatorId);
    }

    final docRef = await _firestore.collection('groups').add({
      'name': name,
      'creator_id': creatorId,
      'group_icon': groupIcon ?? '',
      'last_message': '',
      'last_message_at': FieldValue.serverTimestamp(),
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    });

    final groupId = docRef.id;

    // Add all members
    final batch = _firestore.batch();
    for (var uid in memberIds) {
      final memberRef = _firestore.collection('group_members').doc('${groupId}_$uid');
      batch.set(memberRef, {
        'group_id': groupId,
        'user_id': uid,
        'joined_at': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();

    return groupId;
  }

  /// Get all groups for a user as a realtime stream
  Stream<List<Map<String, dynamic>>> getUserGroups(String userId) {
    return _firestore
        .collection('group_members')
        .where('user_id', isEqualTo: userId)
        .snapshots()
        .asyncMap((snapshot) async {
      final List<Map<String, dynamic>> groups = [];
      for (final doc in snapshot.docs) {
        final row = doc.data();
        final groupId = row['group_id'] as String;
        final groupDoc = await _firestore.collection('groups').doc(groupId).get();

        if (groupDoc.exists) {
          final groupData = groupDoc.data()!;
          
          // Get member IDs
          final membersSnapshot = await _firestore
              .collection('group_members')
              .where('group_id', isEqualTo: groupId)
              .get();

          groups.add({
            'groupId': groupId,
            'name': groupData['name'] ?? 'Unnamed Group',
            'groupIcon': groupData['group_icon'] ?? '',
            'memberIds': membersSnapshot.docs.map((m) => m.data()['user_id'] as String).toList(),
            'lastMessage': groupData['last_message'] ?? '',
            'lastMessageTimestamp': groupData['last_message_at'],
          });
        }
      }

      // Sort by last message timestamp
      groups.sort((a, b) {
        final aTs = a['lastMessageTimestamp'];
        final bTs = b['lastMessageTimestamp'];
        
        if (aTs == null && bTs == null) return 0;
        if (aTs == null) return 1;
        if (bTs == null) return -1;
        
        if (aTs is Timestamp && bTs is Timestamp) {
           return bTs.compareTo(aTs);
        }
        return 0;
      });

      return groups;
    });
  }

  /// Get group details
  Future<Map<String, dynamic>?> getGroupDetails(String groupId) async {
    final doc = await _firestore.collection('groups').doc(groupId).get();
    if (!doc.exists) return null;
    final data = doc.data()!;
    data['id'] = doc.id;
    return data;
  }

  /// Send a message to a group
  Future<void> sendGroupMessage({
    required String groupId,
    required String senderId,
    required String text,
    String type = 'text',
  }) async {
    final encryptedText =
        await _encryptionService.encryptMessage(text, groupId);

    final docRef = await _firestore.collection('group_messages').add({
      'group_id': groupId,
      'sender_id': senderId,
      'text': encryptedText,
      'type': type,
      'created_at': FieldValue.serverTimestamp(),
    });
    await docRef.update({'id': docRef.id});

    // Update last message in group
    await _firestore.collection('groups').doc(groupId).update({
      'last_message': encryptedText,
      'last_message_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  /// Get messages from a group as a realtime stream
  Stream<List<Map<String, dynamic>>> getGroupMessages(String groupId) {
    return _firestore
        .collection('group_messages')
        .where('group_id', isEqualTo: groupId)
        .orderBy('created_at', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList());
  }

  /// Decrypt a group message
  Future<String> decryptGroupMessage(String cipherText, String groupId) async {
    return await _encryptionService.decryptMessage(cipherText, groupId);
  }

  /// Send a media message (image/video/audio/file) to a group.
  Future<void> sendGroupMediaMessage({
    required String groupId,
    required String senderId,
    required String mediaUrl,
    required String type,
  }) async {
    final docRef = await _firestore.collection('group_messages').add({
      'group_id': groupId,
      'sender_id': senderId,
      'text': '',
      'type': type,
      'media_url': mediaUrl,
      'created_at': FieldValue.serverTimestamp(),
    });
    await docRef.update({'id': docRef.id});

    await _firestore.collection('groups').doc(groupId).update({
      'last_message': '[$type]',
      'last_message_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  /// Toggle a single-emoji reaction for [uid] on a group message.
  Future<void> toggleReaction(
      String messageId, String uid, String emoji) async {
    final docRef = _firestore.collection('group_messages').doc(messageId);
    final row = await docRef.get();
    if (!row.exists) return;

    final reactions = Map<String, dynamic>.from(
        row.data()?['reactions'] as Map? ?? <String, dynamic>{});
    if (reactions[uid] == emoji) {
      reactions.remove(uid);
    } else {
      reactions[uid] = emoji;
    }

    await docRef.update({'reactions': reactions});
  }

  /// Edit the text of a group message you sent.
  Future<void> editGroupMessage(
      String messageId, String groupId, String newText) async {
    final encryptedText =
        await _encryptionService.encryptMessage(newText, groupId);
    await _firestore.collection('group_messages').doc(messageId).update({
      'text': encryptedText,
      'edited_at': FieldValue.serverTimestamp(),
    });
  }

  /// Delete a group message for everyone.
  Future<void> deleteGroupMessage(String messageId) async {
    await _firestore.collection('group_messages').doc(messageId).delete();
  }

  /// Get the list of member user IDs for a group.
  Future<List<String>> getGroupMemberIds(String groupId) async {
    final snapshot = await _firestore
        .collection('group_members')
        .where('group_id', isEqualTo: groupId)
        .get();
    return snapshot.docs.map((m) => m.data()['user_id'] as String).toList();
  }

  /// Add a member to a group
  Future<void> addMember(String groupId, String userId) async {
    await _firestore.collection('group_members').doc('${groupId}_$userId').set({
      'group_id': groupId,
      'user_id': userId,
      'joined_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Remove a member from a group
  Future<void> removeMember(String groupId, String userId) async {
    await _firestore.collection('group_members').doc('${groupId}_$userId').delete();
  }

  /// Leave a group
  Future<void> leaveGroup(String groupId, String userId) async {
    await removeMember(groupId, userId);
  }

  /// Update group name
  Future<void> updateGroupName(String groupId, String newName) async {
    await _firestore.collection('groups').doc(groupId).update({
      'name': newName,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  /// Update group icon
  Future<void> updateGroupIcon(String groupId, String iconUrl) async {
    await _firestore.collection('groups').doc(groupId).update({
      'group_icon': iconUrl,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }
}
