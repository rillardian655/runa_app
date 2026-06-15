const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

exports.sendChatNotification = functions.firestore
    .document('chats/{chatId}/messages/{messageId}')
    .onCreate(async (snap, context) => {
        const message = snap.data();
        
        const senderId = message.senderId;
        const receiverId = message.receiverId;
        
        if (!senderId || !receiverId) return null;

        // Fetch receiver's FCM token
        const receiverDoc = await admin.firestore().collection('users').doc(receiverId).get();
        if (!receiverDoc.exists) return null;

        const fcmToken = receiverDoc.data().fcmToken;
        if (!fcmToken) {
            console.log(`No FCM token for user ${receiverId}`);
            return null;
        }

        // Fetch sender's name
        const senderDoc = await admin.firestore().collection('users').doc(senderId).get();
        const senderName = senderDoc.exists ? senderDoc.data().username : 'Someone';

        const payload = {
            notification: {
                title: `New message from ${senderName}`,
                body: "You have a new encrypted message.",
                clickAction: 'FLUTTER_NOTIFICATION_CLICK'
            },
            data: {
                chatId: context.params.chatId,
                senderId: senderId
            }
        };

        try {
            const response = await admin.messaging().sendToDevice(fcmToken, payload);
            console.log('Notification sent successfully:', response);
        } catch (error) {
            console.error('Error sending notification:', error);
        }
        return null;
    });
