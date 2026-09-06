const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { logger } = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

function channelForType(type) {
  if (type === 'message' || type === 'group_message') return 'messages';
  if (type === 'atyaf_video' || type === 'channel_post') return 'content';
  return 'social_activity';
}

function stringData(data) {
  return Object.fromEntries(
    Object.entries(data || {})
      .filter(([, value]) => value !== null && value !== undefined)
      .map(([key, value]) => [key, String(value)]),
  );
}

async function sendToUser(notificationId, data) {
  const receiverId = String(data.receiverId || '').trim();
  if (!receiverId) return;

  const devices = await db.collection('users').doc(receiverId).collection('devices').get();
  const tokens = devices.docs
    .map((doc) => ({ id: doc.id, token: String(doc.data().token || '') }))
    .filter(({ token }) => token.length > 0);
  if (tokens.length === 0) return;

  const type = String(data.notificationType || data.type || 'system');
  const title = String(data.title || data.actorName || 'Zamel');
  const body = String(data.body || 'لديك إشعار جديد');
  const payload = {
    ...stringData(data),
    notificationId,
    notificationType: type,
    receiverId,
  };
  const response = await admin.messaging().sendEachForMulticast({
    tokens: tokens.map(({ token }) => token),
    notification: { title, body },
    data: payload,
    android: {
      priority: type === 'message' ? 'high' : 'normal',
      notification: {
        channelId: channelForType(type),
        tag: type === 'message'
          ? `chat_${String(data.roomId || data.chatId || notificationId)}`
          : `notification_${notificationId}`,
      },
    },
  });

  const removals = [];
  response.responses.forEach((result, index) => {
    if (!result.success && (
      result.error?.code === 'messaging/registration-token-not-registered' ||
      result.error?.code === 'messaging/invalid-registration-token'
    )) {
      removals.push(devices.docs[index].ref.delete());
    }
  });
  await Promise.all(removals);
}

exports.dispatchNotification = onDocumentCreated('Notifications/{notificationId}', async (event) => {
  const snapshot = event.data;
  if (!snapshot) return;
  try {
    await sendToUser(event.params.notificationId, snapshot.data());
  } catch (error) {
    logger.error('Notification delivery failed', {
      notificationId: event.params.notificationId,
      error,
    });
  }
});

exports.fanOutAtyafPublish = onDocumentCreated('NotificationEvents/{eventId}', async (event) => {
  const snapshot = event.data;
  if (!snapshot) return;
  const data = snapshot.data();
  const actorUserId = String(data.actorUserId || '').trim();
  if (data.notificationType === 'group_message') {
    const groupId = String(data.groupId || '').trim();
    if (!groupId) return;
    const group = await db.collection('groups').doc(groupId).get();
    const members = Array.isArray(group.data()?.memberIds) ? group.data().memberIds : [];
    await Promise.all(members
      .map((receiverId) => String(receiverId).trim())
      .filter((receiverId) => receiverId && receiverId !== actorUserId)
      .map((receiverId) => db.collection('Notifications')
        .doc(`group_message:${groupId}:${String(data.messageId)}:${receiverId}`)
        .set({
          senderId: actorUserId,
          actorUserId,
          actorName: String(data.actorName || ''),
          receiverId,
          type: 'group_message',
          notificationType: 'group_message',
          title: String(data.title || data.actorName || 'رسالة جديدة'),
          body: String(data.body || 'لديك رسالة جديدة'),
          referenceId: String(data.messageId || ''),
          roomId: groupId,
          messageId: String(data.messageId || ''),
          isRead: false,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: false })));
    return;
  }
  const videoId = String(data.videoId || data.referenceId || '').trim();
  if (!actorUserId || !videoId) return;

  const followers = await db.collection('users')
    .where('following', 'array-contains', actorUserId)
    .get();
  const writes = [];
  for (const follower of followers.docs) {
    if (follower.id === actorUserId) continue;
    const notificationId = `atyaf:${videoId}:${follower.id}`;
    writes.push(db.collection('Notifications').doc(notificationId).set({
      senderId: actorUserId,
      actorUserId,
      actorName: String(data.actorName || ''),
      receiverId: follower.id,
      type: 'atyaf_video',
      notificationType: 'atyaf_video',
      title: String(data.title || 'محتوى جديد في أطياف'),
      body: `${String(data.actorName || 'مستخدم')} نشر محتوى جديد في أطياف`,
      referenceId: videoId,
      videoId,
      isRead: false,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: false }));
  }
  await Promise.all(writes);
});
