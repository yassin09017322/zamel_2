import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/app_user.dart';
import '../screens/channel_screen.dart';
import '../screens/chat_room_screen.dart';
import '../screens/atyaaf_reels_screen.dart';
import '../screens/group_details_screen.dart';
import '../screens/post_detail_screen.dart';
import '../screens/user_profile_screen.dart';

class NotificationService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
  static Map<String, dynamic>? _pendingTapData;
  static bool _initialized = false;

  static const _messagesChannel = AndroidNotificationChannel(
    'messages',
    'Messages',
    description: 'Direct and group messages',
    importance: Importance.high,
  );
  static const _socialChannel = AndroidNotificationChannel(
    'social_activity',
    'Social activity',
    description: 'Follows, comments, replies, and reactions',
    importance: Importance.defaultImportance,
  );
  static const _contentChannel = AndroidNotificationChannel(
    'content',
    'Content updates',
    description: 'New content from followed channels and creators',
    importance: Importance.defaultImportance,
  );

  static Future<void> initialize() async {
    if (_initialized || kIsWeb) return;
    _initialized = true;

    await _messaging.requestPermission(alert: true, badge: true, sound: true);
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: true,
      sound: false,
    );

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
      macOS: DarwinInitializationSettings(),
      linux: LinuxInitializationSettings(defaultActionName: 'Open notification'),
    );
    
    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final data = response.payload;
        if (data == null || data.isEmpty) return;
        _handleTapData(_decodePayload(data));
      },
    );
    
    final android = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(_messagesChannel);
    await android?.createNotificationChannel(_socialChannel);
    await android?.createNotificationChannel(_contentChannel);

    _messaging.onTokenRefresh.listen(_saveToken);
    FirebaseMessaging.onMessage.listen(_showForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => _handleTapData(message.data),
    );
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) _pendingTapData = initialMessage.data;
    await _saveToken(await _messaging.getToken());
  }

  static Future<void> bindAuthenticatedUser(User? user) async {
    if (kIsWeb || user == null) return;
    await _saveToken(await _messaging.getToken(), userId: user.uid);
  }

  static Future<void> removeAuthenticatedUser(String userId) async {
    if (kIsWeb || userId.trim().isEmpty) return;
    final token = await _messaging.getToken();
    if (token == null || token.isEmpty) return;
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('devices')
        .doc(_deviceId(token))
        .delete();
  }

  static Future<void> _saveToken(String? token, {String? userId}) async {
    final uid = userId ?? FirebaseAuth.instance.currentUser?.uid;
    if (kIsWeb ||
        uid == null ||
        uid.isEmpty ||
        token == null ||
        token.isEmpty) {
      return;
    }
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('devices')
        .doc(_deviceId(token))
        .set({
          'token': token,
          'platform': defaultTargetPlatform.name,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  static String _deviceId(String token) =>
      token.hashCode.toUnsigned(32).toRadixString(16);

  static Future<void> _showForegroundMessage(RemoteMessage message) async {
    final title =
        message.notification?.title ?? message.data['title'] ?? 'Zamel';
    final body = message.notification?.body ?? message.data['body'] ?? '';
    if (body.toString().trim().isEmpty) return;
    final type =
        message.data['notificationType'] ?? message.data['type'] ?? 'system';
    final channel = _channelForType(type.toString());
    await _localNotifications.show(
      _notificationId(message.data),
      title.toString(),
      body.toString(),
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: channel.importance,
          priority: channel.importance == Importance.high
              ? Priority.high
              : Priority.defaultPriority,
          groupKey: _groupForData(message.data),
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: _encodePayload(message.data),
    );
  }

  static AndroidNotificationChannel _channelForType(String type) {
    if (type == 'message' || type == 'group_message') return _messagesChannel;
    if (type == 'atyaf_video' || type == 'channel_post') return _contentChannel;
    return _socialChannel;
  }

  static int _notificationId(Map<String, dynamic> data) =>
      (_groupForData(data).hashCode & 0x7fffffff);

  static String _groupForData(Map<String, dynamic> data) {
    final type = data['notificationType'] ?? data['type'] ?? 'system';
    final conversation = data['chatId'] ?? data['roomId'] ?? data['channelId'];
    return conversation == null || conversation.toString().isEmpty
        ? 'zamel_$type'
        : 'zamel_${type}_$conversation';
  }

  static String _encodePayload(Map<String, dynamic> data) => data.entries
      .map((entry) => '${entry.key}=${Uri.encodeComponent('${entry.value}')}')
      .join('&');

  static Map<String, dynamic> _decodePayload(String value) => {
    for (final part in value.split('&'))
      if (part.contains('='))
        part.substring(0, part.indexOf('=')): Uri.decodeComponent(
          part.substring(part.indexOf('=') + 1),
        ),
  };

  static void handlePendingTap() {
    final data = _pendingTapData;
    _pendingTapData = null;
    if (data != null) _handleTapData(data);
  }

  static Future<void> _handleTapData(Map<String, dynamic> data) async {
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      _pendingTapData = data;
      return;
    }
    final type = data['notificationType'] ?? data['type'] ?? '';
    final currentUser = FirebaseAuth.instance.currentUser;
    if ((type == 'message' ||
            type == 'group_message' ||
            type == 'missed_call') &&
        currentUser != null) {
      if (type == 'group_message') {
        final groupId = (data['groupId'] ?? data['roomId'] ?? '').toString();
        if (groupId.isNotEmpty) {
          navigator.push(
            MaterialPageRoute(
              builder: (_) => GroupDetailsScreen(groupId: groupId),
            ),
          );
        }
        return;
      }
      final snapshot = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .get();
      final userData = snapshot.data();
      if (userData != null) {
        navigator.push(
          MaterialPageRoute(
            builder: (_) => ChatRoomScreen(
              currentUser: AppUser.fromFirestore(userData, currentUser.uid),
              roomId: (data['chatId'] ?? data['roomId'] ?? '').toString(),
            ),
          ),
        );
      }
    } else if (type == 'follow') {
      final actorId = (data['actorUserId'] ?? data['senderId'] ?? '')
          .toString();
      if (actorId.isNotEmpty)
        navigator.push(
          MaterialPageRoute(builder: (_) => UserProfileScreen(userId: actorId)),
        );
    } else if (type == 'comment' ||
        type == 'comment_reply' ||
        type == 'reply' ||
        type == 'like') {
      final postId = (data['postId'] ?? data['referenceId'] ?? '').toString();
      if (postId.isNotEmpty)
        navigator.push(
          MaterialPageRoute(builder: (_) => PostDetailScreen(postId: postId)),
        );
    } else if (type == 'channel_post') {
      final channelId = (data['channelId'] ?? data['roomId'] ?? '').toString();
      if (channelId.isNotEmpty)
        navigator.push(
          MaterialPageRoute(
            builder: (_) => ChannelScreen(channelId: channelId),
          ),
        );
    } else if (type == 'atyaf_video') {
      navigator.push(
        MaterialPageRoute(
          builder: (_) => AtyaafReelsScreen(
            initialVideoId: (data['videoId'] ?? data['referenceId'] ?? '')
                .toString(),
          ),
        ),
      );
    }
  }

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
    String commentId = '',
    String parentCommentId = '',
    String notificationKey = '',
    String actorName = '',
    String title = '',
    String body = '',
    String actorUserId = '',
    String messageId = '',
    String videoId = '',
  }) async {
    if (senderId == receiverId) return;
    final safeNotificationKey = notificationKey.trim();
    if (safeNotificationKey.isNotEmpty) {
      final notificationRef = _firestore
          .collection('Notifications')
          .doc(safeNotificationKey);
      try {
        await notificationRef.set({
          'senderId': senderId,
          'actorUserId': actorUserId.isEmpty ? senderId : actorUserId,
          'actorName': actorName,
          'receiverId': receiverId,
          'type': type,
          'notificationType': type,
          'title': title,
          'body': body,
          'referenceId': referenceId,
          'roomId': roomId,
          'groupId': '',
          'channelId': channelId,
          'postId': postId,
          'commentId': commentId,
          'parentCommentId': parentCommentId,
          'messageId': messageId,
          'videoId': videoId,
          'isRead': isRead,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } on FirebaseException catch (error) {
        if (error.code != 'already-exists') rethrow;
      }
      return;
    }

    final notificationRef = _firestore.collection('Notifications').doc();
    await notificationRef.set({
      'senderId': senderId,
      'actorUserId': actorUserId.isEmpty ? senderId : actorUserId,
      'actorName': actorName,
      'receiverId': receiverId,
      'type': type,
      'notificationType': type,
      'title': title,
      'body': body,
      'referenceId': referenceId,
      'roomId': roomId,
      'groupId': '',
      'channelId': channelId,
      'postId': postId,
      'commentId': commentId,
      'parentCommentId': parentCommentId,
      'messageId': messageId,
      'videoId': videoId,
      'isRead': isRead,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> createAtyafPublishEvent({
    required String reelId,
    required String actorUserId,
    required String actorName,
    required String title,
  }) async {
    final safeReelId = reelId.trim();
    final safeActorId = actorUserId.trim();
    if (safeReelId.isEmpty || safeActorId.isEmpty) return;
    await _firestore
        .collection('NotificationEvents')
        .doc('atyaf:$safeReelId')
        .set({
          'type': 'atyaf_video',
          'notificationType': 'atyaf_video',
          'actorUserId': safeActorId,
          'actorName': actorName,
          'videoId': safeReelId,
          'referenceId': safeReelId,
          'title': title,
          'createdAt': FieldValue.serverTimestamp(),
        });
  }

  Future<void> createGroupMessageEvent({
    required String groupId,
    required String messageId,
    required String actorUserId,
    required String actorName,
    required String body,
  }) async {
    final safeGroupId = groupId.trim();
    final safeMessageId = messageId.trim();
    if (safeGroupId.isEmpty || safeMessageId.isEmpty) return;
    await _firestore
        .collection('NotificationEvents')
        .doc('group_message:$safeGroupId:$safeMessageId')
        .set({
          'type': 'group_message',
          'notificationType': 'group_message',
          'groupId': safeGroupId,
          'roomId': safeGroupId,
          'messageId': safeMessageId,
          'referenceId': safeMessageId,
          'actorUserId': actorUserId,
          'actorName': actorName,
          'title': actorName,
          'body': body,
          'createdAt': FieldValue.serverTimestamp(),
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
        actorName: senderName,
        title: channelName,
        body: 'منشور جديد في القناة',
        notificationKey: notificationKey,
      );
    }
  }

  Future<void> markAsRead(String notificationId) async {
    await _firestore.collection('Notifications').doc(notificationId).update({
      'isRead': true,
    });
  }
}
