import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:runa_app/core/services/encryption_service.dart';

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final EncryptionService _encryptionService = EncryptionService();

  String getChatId(String uid1, String uid2) {
    List<String> ids = [uid1, uid2];
    ids.sort();
    return ids.join('_');
  }

  Stream<QuerySnapshot> getMessages(String chatId) {
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(30)
        .snapshots();
  }

  Stream<List<Map<String, dynamic>>> getRecentChats(String currentUid) {
    return _firestore
        .collection('users')
        .doc(currentUid)
        .collection('recent_chats')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
      List<Map<String, dynamic>> chats = [];
      for (var doc in snapshot.docs) {
        var userDoc = await _firestore.collection('users').doc(doc.id).get();
        if (userDoc.exists) {
          chats.add({
            'uid': userDoc.id,
            'name': userDoc.data()?['username'] ?? 'Unknown',
            'lastMessage': doc.data()['lastMessage'] ?? '',
          });
        }
      }
      return chats;
    });
  }

  Future<void> sendMessage(String senderId, String receiverId, String text) async {
    final chatId = getChatId(senderId, receiverId);
    final encryptedText = await _encryptionService.encryptMessage(text, chatId);

    await _firestore.collection('chats').doc(chatId).collection('messages').add({
      'senderId': senderId,
      'receiverId': receiverId,
      'text': encryptedText,
      'timestamp': FieldValue.serverTimestamp(),
      'status': 'sent', // sent, delivered, read
    });

    // Update recent_chats for both users
    await _firestore.collection('users').doc(senderId).collection('recent_chats').doc(receiverId).set({
      'lastMessage': '[Encrypted]',
      'timestamp': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _firestore.collection('users').doc(receiverId).collection('recent_chats').doc(senderId).set({
      'lastMessage': '[Encrypted]',
      'timestamp': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<String> decrypt(String cipherText, String chatId) async {
    return await _encryptionService.decryptMessage(cipherText, chatId);
  }
}
