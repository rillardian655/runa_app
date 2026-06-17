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
          String rawMsg = doc.data()['lastMessage'] ?? '';
          String finalMsg = rawMsg;
          if (rawMsg != '' && rawMsg != '[Encrypted]') {
            final decrypted = await decrypt(rawMsg, getChatId(currentUid, userDoc.id));
            // Jika last message adalah foto (base64), tampilkan label ramah
            if (decrypted.startsWith('data:image/')) {
              finalMsg = '📷 Foto';
            } else {
              finalMsg = decrypted;
            }
          } else if (rawMsg == '[Encrypted]') {
            finalMsg = '[Encrypted Message]';
          }
          
          chats.add({
            'uid': userDoc.id,
            'name': userDoc.data()?['username'] ?? 'Unknown',
            'photoUrl': userDoc.data()?['photoUrl'] ?? '',
            'lastMessage': finalMsg,
            'unreadCount': doc.data()['unreadCount'] ?? 0,
          });
        }
      }
      return chats;
    });
  }

  Future<void> sendMessage(String senderId, String receiverId, String text,
      {String? replyToId,
      String? replyToText,
      String? replyToType,
      String type = 'text'}) async {
    final chatId = getChatId(senderId, receiverId);
    final encryptedText = await _encryptionService.encryptMessage(text, chatId);

    final messageData = <String, dynamic>{
      'senderId': senderId,
      'receiverId': receiverId,
      'text': encryptedText,
      'type': type,
      'timestamp': FieldValue.serverTimestamp(),
      'status': 'sent', // sent, delivered, read
    };

    if (replyToId != null) messageData['replyToId'] = replyToId;
    if (replyToText != null) messageData['replyToText'] = replyToText;
    if (replyToType != null) messageData['replyToType'] = replyToType;

    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .add(messageData);

    // lastMessage untuk tampilan di chat list:
    // jika foto → tampilkan '📷 Foto', bukan base64 terenkripsi
    final lastMessagePreview = type == 'image' ? '📷 Foto' : encryptedText;

    // Update recent_chats untuk pengirim
    await _firestore
        .collection('users')
        .doc(senderId)
        .collection('recent_chats')
        .doc(receiverId)
        .set({
      'lastMessage': lastMessagePreview,
      'timestamp': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Update recent_chats untuk penerima (+ increment unread)
    await _firestore
        .collection('users')
        .doc(receiverId)
        .collection('recent_chats')
        .doc(senderId)
        .set({
      'lastMessage': lastMessagePreview,
      'timestamp': FieldValue.serverTimestamp(),
      'unreadCount': FieldValue.increment(1),
    }, SetOptions(merge: true));
  }

  Future<String> decrypt(String cipherText, String chatId) async {
    return await _encryptionService.decryptMessage(cipherText, chatId);
  }

  Future<void> markMessagesAsRead(String chatId, String currentUid, String friendUid) async {
    final unreadMessages = await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('receiverId', isEqualTo: currentUid)
        .get();

    bool hasUpdates = false;
    final batch = _firestore.batch();

    for (var doc in unreadMessages.docs) {
      if (doc.data()['status'] != 'read') {
        batch.update(doc.reference, {'status': 'read'});
        hasUpdates = true;
      }
    }

    if (hasUpdates) {
      await batch.commit();
    }
    
    // Reset unread count
    await _firestore
        .collection('users')
        .doc(currentUid)
        .collection('recent_chats')
        .doc(friendUid)
        .set({'unreadCount': 0}, SetOptions(merge: true));
  }
}
