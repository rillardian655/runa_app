const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

// Native fetch is available in Node 18+ (which is used in package.json)
// Send push notification via OneSignal when a new 1-to-1 message arrives
exports.sendChatNotification = functions.firestore
    .document('messages/{messageId}')
    .onCreate(async (snap, context) => {
        const message = snap.data();
        
        const senderId = message.sender_id;
        const receiverId = message.receiver_id;
        const messageType = message.type || 'text';
        const chatId = message.chat_id;
        
        if (!senderId || !receiverId) return null;

        try {
            // Fetch sender's username
            const senderDoc = await admin.firestore().collection('users').doc(senderId).get();
            const senderName = senderDoc.exists ? (senderDoc.data().username || 'Someone') : 'Someone';

            // Determine notification body based on message type
            let notifBody = "Pesan baru terenkripsi";
            if (messageType === 'image') notifBody = '📷 Mengirim sebuah foto';
            else if (messageType === 'video') notifBody = '🎥 Mengirim sebuah video';
            else if (messageType === 'audio') notifBody = '🎵 Mengirim pesan suara';
            else if (messageType === 'file') notifBody = '📎 Mengirim sebuah file';

            // Fetch OneSignal config
            const oneSignalAppId = process.env.ONESIGNAL_APP_ID || functions.config().onesignal?.app_id || '7b94f919-28fb-4379-bfda-ca4b5cf6ef85';
            const oneSignalKey = process.env.ONESIGNAL_REST_KEY || functions.config().onesignal?.rest_key;

            if (!oneSignalKey) {
                console.error('OneSignal REST API Key is not set in Firebase Config.');
                return null;
            }

            const response = await fetch('https://onesignal.com/api/v1/notifications', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json; charset=utf-8',
                    'Authorization': `Basic ${oneSignalKey}`,
                },
                body: JSON.stringify({
                    app_id: oneSignalAppId,
                    include_external_user_ids: [receiverId],
                    headings: { en: senderName },
                    contents: { en: notifBody },
                    android_channel_id: "runa_chat_channel",
                    priority: 10,
                    data: {
                        chatId: chatId,
                        senderId: senderId,
                        type: messageType,
                    },
                }),
            });

            const result = await response.json();
            console.log('OneSignal 1-to-1 response:', JSON.stringify(result));
        } catch (error) {
            console.error('Error sending private notification:', error);
        }
        return null;
    });

// Send push notification via OneSignal to all members when a new group message arrives
exports.sendGroupChatNotification = functions.firestore
    .document('group_messages/{messageId}')
    .onCreate(async (snap, context) => {
        const message = snap.data();
        
        const senderId = message.sender_id;
        const groupId = message.group_id;
        const messageType = message.type || 'text';
        
        if (!senderId || !groupId) return null;

        try {
            // Fetch group name
            const groupDoc = await admin.firestore().collection('groups').doc(groupId).get();
            if (!groupDoc.exists) return null;
            const groupName = groupDoc.data().name || 'Grup';

            // Fetch sender's username
            const senderDoc = await admin.firestore().collection('users').doc(senderId).get();
            const senderName = senderDoc.exists ? (senderDoc.data().username || 'Someone') : 'Someone';

            // Determine notification body based on message type
            let notifBody = "Pesan baru terenkripsi";
            if (messageType === 'image') notifBody = '📷 Mengirim sebuah foto';
            else if (messageType === 'video') notifBody = '🎥 Mengirim sebuah video';
            else if (messageType === 'audio') notifBody = '🎵 Mengirim pesan suara';
            else if (messageType === 'file') notifBody = '📎 Mengirim sebuah file';

            // Fetch all group members
            const membersSnapshot = await admin.firestore()
                .collection('group_members')
                .where('group_id', isEqualTo: groupId)
                .get();

            // Filter out the sender
            const targetUserIds = [];
            membersSnapshot.forEach((doc) => {
                const uid = doc.data().user_id;
                if (uid && uid !== senderId) {
                    targetUserIds.push(uid);
                }
            });

            if (targetUserIds.length === 0) return null;

            // Fetch OneSignal config
            const oneSignalAppId = process.env.ONESIGNAL_APP_ID || functions.config().onesignal?.app_id || '7b94f919-28fb-4379-bfda-ca4b5cf6ef85';
            const oneSignalKey = process.env.ONESIGNAL_REST_KEY || functions.config().onesignal?.rest_key;

            if (!oneSignalKey) {
                console.error('OneSignal REST API Key is not set in Firebase Config.');
                return null;
            }

            const response = await fetch('https://onesignal.com/api/v1/notifications', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json; charset=utf-8',
                    'Authorization': `Basic ${oneSignalKey}`,
                },
                body: JSON.stringify({
                    app_id: oneSignalAppId,
                    include_external_user_ids: targetUserIds,
                    headings: { en: `${senderName} @ ${groupName}` },
                    contents: { en: notifBody },
                    android_channel_id: "runa_chat_channel",
                    priority: 10,
                    data: {
                        groupId: groupId,
                        senderId: senderId,
                        type: messageType,
                        isGroup: true,
                    },
                }),
            });

            const result = await response.json();
            console.log('OneSignal group response:', JSON.stringify(result));
        } catch (error) {
            console.error('Error sending group notification:', error);
        }
        return null;
    });
