import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static String buildChannelNotificationKey({
    required String channelId,
    required String postId,
    required String receiverId,
  }) {
    final safeChannelId = channelId.trim();
    final safePostId = postId.trim();
    final safeReceiverId = receiverId.trim();
    if (safeChannelId.isEmpty || safePostId.isEmpty || safeReceiverId.isEmpty) {
      return 'channel_notification_invalid';
    }
    return 'channel_notification:$safeChannelId:$safePostId:$safeReceiverId';
  }

  static Map<String, bool> normalizeChannelSettings(Map? rawSettings) {
    final normalized = <String, bool>{};
    if (rawSettings == null) return normalized;
    for (final entry in rawSettings.entries) {
      final key = entry.key.toString();
      final value = entry.value;
      if (value is bool) normalized[key] = value;
    }
    return normalized;
  }

  Future<void> createNotification({
    required String senderId,
    required String receiverId,
    required String type,
    String referenceId = '',
    String roomId = '',
    bool isRead = false,
    String channelId = '',
    String postId = '',
    String notificationKey = '',
  }) async {
    if (senderId == receiverId) return;
    final safeNotificationKey = notificationKey.trim();
    if (safeNotificationKey.isNotEmpty) {
      final notificationRef = _firestore.collection('Notifications').doc(safeNotificationKey);
      final existing = await notificationRef.get();
      if (existing.exists) return;
      await notificationRef.set({
        'senderId': senderId,
        'receiverId': receiverId,
        'type': type,
        'referenceId': referenceId,
        'roomId': roomId,
        'channelId': channelId,
        'postId': postId,
        'isRead': isRead,
        'timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }

    await _firestore.collection('Notifications').add({
      'senderId': senderId,
      'receiverId': receiverId,
      'type': type,
      'referenceId': referenceId,
      'roomId': roomId,
      'channelId': channelId,
      'postId': postId,
      'isRead': isRead,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setChannelNotificationPreference({
    required String userId,
    required String channelId,
    required bool enabled,
  }) async {
    final safeUserId = userId.trim();
    final safeChannelId = channelId.trim();
    if (safeUserId.isEmpty || safeChannelId.isEmpty) return;

    final userRef = _firestore.collection('users').doc(safeUserId);
    final currentSnapshot = await userRef.get();
    final currentSettings = normalizeChannelSettings(
      currentSnapshot.data()?['channelNotifications'] as Map?,
    );
    currentSettings[safeChannelId] = enabled;

    await userRef.set({
      'channelNotifications': currentSettings,
    }, SetOptions(merge: true));
  }

  Future<bool> isChannelNotificationEnabled({
    required String userId,
    required String channelId,
  }) async {
    final safeUserId = userId.trim();
    final safeChannelId = channelId.trim();
    if (safeUserId.isEmpty || safeChannelId.isEmpty) return true;

    final doc = await _firestore.collection('users').doc(safeUserId).get();
    final settings = normalizeChannelSettings(
      doc.data()?['channelNotifications'] as Map?,
    );
    if (!settings.containsKey(safeChannelId)) return true;
    return settings[safeChannelId] == true;
  }

  Future<void> sendChannelPostNotification({
    required String channelId,
    required String postId,
    required String channelName,
    required String senderId,
    required String senderName,
    required List<String> receiverIds,
  }) async {
    final safeChannelId = channelId.trim();
    final safePostId = postId.trim();
    if (safeChannelId.isEmpty || safePostId.isEmpty) return;

    final uniqueReceiverIds = receiverIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty && id != senderId.trim())
        .toSet()
        .toList();

    for (final receiverId in uniqueReceiverIds) {
      final enabled = await isChannelNotificationEnabled(
        userId: receiverId,
        channelId: safeChannelId,
      );
      if (!enabled) continue;

      final notificationKey = buildChannelNotificationKey(
        channelId: safeChannelId,
        postId: safePostId,
        receiverId: receiverId,
      );

      await createNotification(
        senderId: senderId,
        receiverId: receiverId,
        type: 'channel_post',
        referenceId: safePostId,
        roomId: safeChannelId,
        channelId: safeChannelId,
        postId: safePostId,
        notificationKey: notificationKey,
      );
    }
  }

  Future<void> markAsRead(String notificationId) async {
    await _firestore.collection('Notifications').doc(notificationId).update({'isRead': true});
  }
}
