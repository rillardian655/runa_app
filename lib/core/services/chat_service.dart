import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:runa_app/core/services/encryption_service.dart';

class ChatService {
  final EncryptionService _encryptionService = EncryptionService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String getChatId(String uid1, String uid2) {
    final ids = [uid1, uid2]..sort();
    return ids.join('_');
  }

  /// Get messages for a chat as a realtime stream
  Stream<List<Map<String, dynamic>>> getMessages(String chatId) {
    return _firestore
        .collection('messages')
        .where('chat_id', isEqualTo: chatId)
        .orderBy('created_at', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList());
  }

  /// Get recent chats for a user as a realtime stream
  Stream<List<Map<String, dynamic>>> getRecentChats(String currentUid) {
    return _firestore
        .collection('recent_chats')
        .where('user_id', isEqualTo: currentUid)
        .orderBy('updated_at', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
      final List<Map<String, dynamic>> chats = [];
      for (final doc in snapshot.docs) {
        final row = doc.data();
        final otherUid = row['other_user_id'] as String;
        final userDoc = await _firestore.collection('users').doc(otherUid).get();

        if (userDoc.exists) {
          final userData = userDoc.data()!;
          String rawMsg = row['last_message'] as String? ?? '';
          String finalMsg = rawMsg;
          if (rawMsg.isNotEmpty && rawMsg != '[Encrypted]') {
            try {
              finalMsg = await _encryptionService.decryptMessage(
                  rawMsg, getChatId(currentUid, otherUid));
            } catch (_) {
              finalMsg = '[Encrypted Message]';
            }
          }

          chats.add({
            'uid': otherUid,
            'name': userData['username'] ?? 'Unknown',
            'photoUrl': userData['photo_url'] ?? '',
            'presence_status': userData['presence_status'] ?? 'offline',
            'lastMessage': finalMsg,
            'unreadCount': row['unread_count'] ?? 0,
            'updated_at': row['updated_at'],
          });
        }
      }
      return chats;
    });
  }

  Future<void> sendMessage(
    String senderId,
    String receiverId,
    String text, {
    String? replyToId,
    String? replyToText,
    String type = 'text',
    String? caption,
  }) async {
    final chatId = getChatId(senderId, receiverId);
    final encryptedText = await _encryptionService.encryptMessage(text, chatId);

    // Ensure chat exists
    await _firestore.collection('chats').doc(chatId).set({
      'id': chatId,
      'participant1_id': chatId.split('_')[0],
      'participant2_id': chatId.split('_')[1],
      'last_message': encryptedText,
      'last_message_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Insert message
    final messageData = <String, dynamic>{
      'chat_id': chatId,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'text': encryptedText,
      'type': type,
      'status': 'sent',
      'created_at': FieldValue.serverTimestamp(),
      // For listeners to use stringly typed created_at for sorting locally if needed
      'timestamp': DateTime.now().toIso8601String(),
    };
    if (replyToId != null) messageData['reply_to_id'] = replyToId;
    if (replyToText != null) {
      messageData['reply_to_text'] =
          await _encryptionService.encryptMessage(replyToText, chatId);
    }
    if (caption != null) messageData['caption'] = caption;

    final docRef = await _firestore.collection('messages').add(messageData);
    await docRef.update({'id': docRef.id});

    // Update recent_chats for sender
    final senderRecentRef = _firestore.collection('recent_chats').doc('${senderId}_$receiverId');
    await senderRecentRef.set({
      'user_id': senderId,
      'other_user_id': receiverId,
      'last_message': encryptedText,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Update recent_chats for receiver (increment unread)
    final receiverRecentRef = _firestore.collection('recent_chats').doc('${receiverId}_$senderId');
    final existing = await receiverRecentRef.get();
    final currentUnread = (existing.data()?['unread_count'] as int?) ?? 0;
    
    await receiverRecentRef.set({
      'user_id': receiverId,
      'other_user_id': senderId,
      'last_message': encryptedText,
      'unread_count': currentUnread + 1,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<String> decrypt(String cipherText, String chatId) async {
    return await _encryptionService.decryptMessage(cipherText, chatId);
  }

  Future<void> toggleReaction(
      String messageId, String uid, String emoji) async {
    final docRef = _firestore.collection('messages').doc(messageId);
    final row = await docRef.get();
    
    if (!row.exists) return;

    final reactions = Map<String, dynamic>.from(row.data()?['reactions'] as Map? ?? <String, dynamic>{});
    if (reactions[uid] == emoji) {
      reactions.remove(uid);
    } else {
      reactions[uid] = emoji;
    }

    await docRef.update({'reactions': reactions});
  }

  Future<void> editMessage(
      String messageId, String chatId, String newText) async {
    final encryptedText =
        await _encryptionService.encryptMessage(newText, chatId);
    await _firestore.collection('messages').doc(messageId).update({
      'text': encryptedText,
      'edited_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteMessage(String messageId) async {
    await _firestore.collection('messages').doc(messageId).delete();
  }

  Future<void> markMessagesAsRead(
      String chatId, String currentUid, String friendUid) async {
    // Update message statuses
    final unreadMessages = await _firestore
        .collection('messages')
        .where('chat_id', isEqualTo: chatId)
        .where('receiver_id', isEqualTo: currentUid)
        .where('status', isNotEqualTo: 'read')
        .get();

    final batch = _firestore.batch();
    for (var doc in unreadMessages.docs) {
      batch.update(doc.reference, {'status': 'read'});
    }
    await batch.commit();

    // Reset unread count
    final receiverRecentRef = _firestore.collection('recent_chats').doc('${currentUid}_$friendUid');
    await receiverRecentRef.set({
      'user_id': currentUid,
      'other_user_id': friendUid,
      'unread_count': 0,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> sendMediaMessage(
    String senderId,
    String receiverId,
    String mediaUrl,
    String type, {
    String? caption,
    int? mediaSize,
  }) async {
    final chatId = getChatId(senderId, receiverId);

    await _firestore.collection('chats').doc(chatId).set({
      'id': chatId,
      'participant1_id': chatId.split('_')[0],
      'participant2_id': chatId.split('_')[1],
      'last_message': '[$type]',
      'last_message_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final docRef = await _firestore.collection('messages').add({
      'chat_id': chatId,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'text': '',
      'type': type,
      'status': 'sent',
      'media_url': mediaUrl,
      'media_size': mediaSize,
      'caption': caption,
      'created_at': FieldValue.serverTimestamp(),
      'timestamp': DateTime.now().toIso8601String(),
    });
    await docRef.update({'id': docRef.id});

    // Update recent_chats for sender
    final senderRecentRef = _firestore.collection('recent_chats').doc('${senderId}_$receiverId');
    await senderRecentRef.set({
      'user_id': senderId,
      'other_user_id': receiverId,
      'last_message': '[$type]',
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Update recent_chats for receiver (increment unread)
    final receiverRecentRef = _firestore.collection('recent_chats').doc('${receiverId}_$senderId');
    final existing = await receiverRecentRef.get();
    final currentUnread = (existing.data()?['unread_count'] as int?) ?? 0;
    
    await receiverRecentRef.set({
      'user_id': receiverId,
      'other_user_id': senderId,
      'last_message': '[$type]',
      'unread_count': currentUnread + 1,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
  Future<void> deleteChat(String currentUid, String otherUid) async {
    await _firestore.collection('recent_chats').doc('${currentUid}_$otherUid').delete();
  }
}
