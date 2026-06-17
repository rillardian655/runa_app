const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

exports.sendChatNotification = functions.firestore
    .document('chats/{chatId}/messages/{messageId}')
    .onCreate(async (snap, context) => {
        const message = snap.data();

        const senderId = message.senderId;
        const receiverId = message.receiverId;
        const messageType = message.type || 'text';

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

        // Determine notification body based on message type
        const notifBody = messageType === 'image'
            ? '📷 Mengirim sebuah foto'
            : 'Pesan baru terenkripsi';

        // Use FCM v1 API (send) — Legacy sendToDevice() was shut down June 2024
        const fcmMessage = {
            token: fcmToken,
            notification: {
                title: senderName,
                body: notifBody,
            },
            android: {
                priority: 'high',
                notification: {
                    channelId: 'runa_chat_channel',
                    priority: 'max',
                    sound: 'default',
                    clickAction: 'FLUTTER_NOTIFICATION_CLICK',
                    icon: 'launcher_icon',
                },
            },
            apns: {
                headers: {
                    'apns-priority': '10',
                },
                payload: {
                    aps: {
                        sound: 'default',
                        badge: 1,
                        contentAvailable: true,
                    },
                },
            },
            data: {
                chatId: context.params.chatId,
                senderId: senderId,
                type: messageType,
                click_action: 'FLUTTER_NOTIFICATION_CLICK',
            },
        };

        try {
            const response = await admin.messaging().send(fcmMessage);
            console.log('Notification sent successfully:', response);
        } catch (error) {
            console.error('Error sending notification:', error);
        }
        return null;
    });

