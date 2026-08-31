import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/channel.dart';
import '../models/channel_message.dart';
import 'notification_service.dart';

class ChannelService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static const Duration _messageWriteTimeout = Duration(seconds: 30);
  static const Duration _channelImageWriteTimeout = Duration(seconds: 30);

  static Map<String, dynamic> buildMessagePayload({
    required String channelId,
    required String senderId,
    required String senderName,
    required String text,
    String mediaUrl = '',
    String mediaType = 'text',
    String thumbnailUrl = '',
    String parentMessageId = '',
    Map<String, dynamic>? reactions,
    int replyCount = 0,
    Map<String, dynamic>? extraData,
  }) {
    final resolvedSenderId = senderId.trim();
    final resolvedSenderName = senderName.trim().isNotEmpty
        ? senderName.trim()
        : 'مستخدم';
    final resolvedMediaType = mediaType.trim().isEmpty ? 'text' : mediaType.trim();

    return {
      'channelId': channelId,
      'senderId': resolvedSenderId,
      'senderName': resolvedSenderName,
      'text': text.trim(),
      'mediaUrl': mediaUrl.trim(),
      'mediaType': resolvedMediaType,
      'thumbnailUrl': thumbnailUrl.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'timestamp': FieldValue.serverTimestamp(),
      'isDeleted': false,
      'parentMessageId': parentMessageId,
      'reactions': reactions ?? const {},
      'replyCount': replyCount,
      'viewCount': 0,
      'viewedBy': const <String>[],
      'extraData': extraData ?? const {},
    };
  }

  Future<void> _ensureAdmin() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('المستخدم غير مسجل دخول');
    }

    final userDoc = await _firestore
        .collection('users')
        .doc(currentUser.uid)
        .get();
    final role = userDoc.data()?['role'] as String? ?? 'user';
    if (role != 'admin') {
      throw Exception('غير مصرح لك بإدارة القنوات');
    }
  }

  Stream<List<Channel>> channelsStream() {
    return _firestore
        .collection('channels')
        .where('isActive', isEqualTo: true)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => Channel.fromFirestore(doc))
              .toList();
        });
  }

  Stream<List<ChannelMessage>> messagesStream(
    String channelId, {
    int limit = 20,
  }) {
    return _firestore
        .collection('channels')
        .doc(channelId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => ChannelMessage.fromFirestore(doc, channelId))
              .where((msg) => !msg.isDeleted)
              // إخفاء التعليقات من القائمة الرئيسية للقناة
              .where((msg) => msg.parentMessageId.isEmpty)
              .toList();
        });
  }

  Future<Channel?> getChannel(String channelId) async {
    final doc = await _firestore.collection('channels').doc(channelId).get();
    if (!doc.exists) return null;
    return Channel.fromFirestore(doc);
  }

  Future<String> createChannel({
    required String name,
    required String description,
    required String imageUrl,
    bool isPrivate = false,
    bool isReadOnly = false,
    String accessType = 'public',
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('المستخدم غير مسجل دخول');
    }

    final userDoc = await _firestore
        .collection('users')
        .doc(currentUser.uid)
        .get();
    final adminName =
        (userDoc.data()?['username'] as String?) ??
        currentUser.email ??
        'admin';

    final normalizedAccessType = _normalizeAccessType(accessType, isPrivate);

    final ref = await _firestore.collection('channels').add({
      'name': name.trim(),
      'description': description.trim(),
      'adminId': currentUser.uid,
      'adminName': adminName,
      'imageUrl': imageUrl,
      'isActive': true,
      'isPrivate': normalizedAccessType == 'private',
      'isReadOnly': isReadOnly,
      'accessType': normalizedAccessType,
      'isMembersHidden': false,
      'isAccountsDisabled': false,
      'pinnedMessageId': '',
      'moderators': [currentUser.uid],
      'memberIds': [currentUser.uid],
      'guestIds': const [],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return ref.id;
  }

  Future<void> updateChannelSettings({
    required String channelId,
    bool? isPrivate,
    bool? isReadOnly,
    String? accessType,
    bool? isMembersHidden,
    bool? isAccountsDisabled,
    String? name,
    String? description,
    String? imageUrl,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('المستخدم غير مسجل دخول');
    }

    final userDoc = await _firestore
        .collection('users')
        .doc(currentUser.uid)
        .get();
    final role = userDoc.data()?['role'] as String? ?? 'user';

    if (isAccountsDisabled != null && role != 'admin') {
      throw Exception('تعطيل الحسابات خاص بإدارة التطبيق فقط');
    }

    final payload = <String, dynamic>{};
    if (isPrivate != null) payload['isPrivate'] = isPrivate;
    if (isReadOnly != null) payload['isReadOnly'] = isReadOnly;
    if (accessType != null) {
      final normalized = _normalizeAccessType(accessType, isPrivate ?? false);
      payload['accessType'] = normalized;
      payload['isPrivate'] = normalized == 'private';
    }
    if (isMembersHidden != null) payload['isMembersHidden'] = isMembersHidden;
    if (isAccountsDisabled != null)
      payload['isAccountsDisabled'] = isAccountsDisabled;
    if (name != null && name.trim().isNotEmpty) payload['name'] = name.trim();
    if (description != null && description.trim().isNotEmpty)
      payload['description'] = description.trim();
    if (imageUrl != null) payload['imageUrl'] = imageUrl;
    payload['updatedAt'] = FieldValue.serverTimestamp();
    if (payload.isEmpty) return;
    await _firestore.collection('channels').doc(channelId).update(payload);
  }

  Future<void> updateChannelImage({
    required String channelId,
    required String imageUrl,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('المستخدم غير مسجل دخول');
    }

    final channelSnapshot =
        await _firestore.collection('channels').doc(channelId).get();
    final channelData = channelSnapshot.data();
    if (channelData == null) {
      throw Exception('القناة غير موجودة');
    }

    final userSnapshot =
        await _firestore.collection('users').doc(currentUser.uid).get();
    final isAppAdmin = userSnapshot.data()?['role'] == 'admin';
    final moderators = List<String>.from(channelData['moderators'] ?? const []);
    final isChannelManager =
        channelData['adminId'] == currentUser.uid ||
        moderators.contains(currentUser.uid);
    if (!isAppAdmin && !isChannelManager) {
      throw Exception('غير مصرح لك بتعديل صورة القناة');
    }

    final normalizedUrl = imageUrl.trim();
    if (normalizedUrl.isNotEmpty) {
      final uri = Uri.tryParse(normalizedUrl);
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
        throw Exception('رابط صورة القناة غير صالح');
      }
    }

    await _firestore.collection('channels').doc(channelId).update({
      'imageUrl': normalizedUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    }).timeout(_channelImageWriteTimeout);
  }

  static bool isUserInMemberList(List<dynamic>? values, String userId) {
    final safeUserId = userId.trim();
    if (safeUserId.isEmpty) return false;
    for (final value in values ?? const <dynamic>[]) {
      if (value is String && value.trim() == safeUserId) return true;
    }
    return false;
  }

  static bool userExistsInList(List<dynamic>? values, String userId) {
    final safeUserId = userId.trim();
    if (safeUserId.isEmpty) return false;
    for (final value in values ?? const <dynamic>[]) {
      if (value is String && value.trim() == safeUserId) return true;
    }
    return false;
  }

  Future<void> addMember({
    required String channelId,
    required String userId,
  }) async {
    final safeUserId = userId.trim();
    if (safeUserId.isEmpty) return;
    final ref = _firestore.collection('channels').doc(channelId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) return;
      final data = snapshot.data() ?? {};
      final members = <String>[];
      final currentMembers = List<dynamic>.from(data['memberIds'] ?? const <dynamic>[]);
      for (final value in currentMembers) {
        if (value is String && value.trim().isNotEmpty) {
          members.add(value.trim());
        }
      }
      final guests = List<String>.from(data['guestIds'] ?? const <dynamic>[])
        ..where((value) => value.trim().isNotEmpty)
        .toList();

      if (members.contains(safeUserId)) {
        return;
      }

      members.add(safeUserId);
      guests.removeWhere((value) => value.trim() == safeUserId);

      transaction.update(ref, {
        'memberIds': members,
        'guestIds': guests,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }).timeout(_messageWriteTimeout);
  }

  Future<bool> joinChannel({
    required String channelId,
    required String userId,
  }) async {
    final safeUserId = userId.trim();
    if (safeUserId.isEmpty) return false;

    final currentUser = _auth.currentUser;
    if (currentUser == null || currentUser.uid != safeUserId) return false;

    try {
      await addMember(channelId: channelId, userId: safeUserId);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> leaveChannel({
    required String channelId,
    required String userId,
  }) async {
    final safeUserId = userId.trim();
    if (safeUserId.isEmpty) return false;

    final currentUser = _auth.currentUser;
    if (currentUser == null || currentUser.uid != safeUserId) return false;

    final ref = _firestore.collection('channels').doc(channelId);

    try {
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(ref);
        if (!snapshot.exists) return;

        final data = snapshot.data() ?? {};
        final channelAdminId = (data['adminId'] as String? ?? '').trim();
        if (channelAdminId == safeUserId) {
          return;
        }

        final members = <String>[];
        for (final value in List<dynamic>.from(data['memberIds'] ?? const <dynamic>[])) {
          if (value is String && value.trim().isNotEmpty && value.trim() != safeUserId) {
            members.add(value.trim());
          }
        }

        final guests = <String>[];
        for (final value in List<dynamic>.from(data['guestIds'] ?? const <dynamic>[])) {
          if (value is String && value.trim().isNotEmpty && value.trim() != safeUserId) {
            guests.add(value.trim());
          }
        }

        transaction.update(ref, {
          'memberIds': members,
          'guestIds': guests,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }).timeout(_messageWriteTimeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  static const List<String> adminPermissionKeys = [
    'canPost',
    'canEditPosts',
    'canDeletePosts',
    'canManageMembers',
    'canAddMembers',
    'canRemoveMembers',
    'canPinPosts',
    'canManageContent',
  ];

  static Map<String, bool> defaultAdminPermissions() {
    return {
      for (final key in adminPermissionKeys) key: true,
    };
  }

  Future<Map<String, bool>> getAdminPermissions({
    required String channelId,
    required String userId,
  }) async {
    final doc = await _firestore.collection('channels').doc(channelId).get();
    if (!doc.exists) return {};

    final channel = Channel.fromFirestore(doc);
    final permissions = channel.adminPermissions[userId.trim()];
    if (permissions == null || permissions.isEmpty) {
      return userId.trim() == channel.adminId ? defaultAdminPermissions() : {};
    }
    return permissions;
  }

  Future<void> setAdminPermissions({
    required String channelId,
    required String ownerId,
    required String adminUserId,
    required Map<String, bool> permissions,
  }) async {
    final safeOwnerId = ownerId.trim();
    final safeAdminUserId = adminUserId.trim();
    if (safeOwnerId.isEmpty || safeAdminUserId.isEmpty) return;

    final ref = _firestore.collection('channels').doc(channelId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) return;

      final data = snapshot.data() ?? {};
      final currentOwnerId = (data['adminId'] as String? ?? '').trim();
      if (currentOwnerId != safeOwnerId) {
        throw Exception('مالك القناة فقط يمكنه تعديل صلاحيات المشرفين');
      }

      final moderators = <String>[];
      for (final value in List<dynamic>.from(data['moderators'] ?? const <dynamic>[])) {
        if (value is String && value.trim().isNotEmpty) {
          moderators.add(value.trim());
        }
      }

      if (!moderators.contains(safeAdminUserId)) {
        throw Exception('المستخدم المحدد ليس مشرفًا');
      }

      final normalizedPermissions = <String, bool>{};
      for (final key in adminPermissionKeys) {
        normalizedPermissions[key] = permissions[key] == true;
      }

      final currentPermissions = Map<String, Map<String, bool>>.from(
        (data['adminPermissions'] as Map? ?? const {})
            .map((key, value) => MapEntry(key.toString(), Map<String, bool>.from(value as Map? ?? const {}))),
      );

      currentPermissions[safeAdminUserId] = normalizedPermissions;
      transaction.update(ref, {
        'adminPermissions': currentPermissions,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }).timeout(_messageWriteTimeout);
  }

  Future<void> addModerator({
    required String channelId,
    required String userId,
  }) async {
    final safeUserId = userId.trim();
    if (safeUserId.isEmpty) return;

    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('المستخدم غير مسجل دخول');
    }

    final ref = _firestore.collection('channels').doc(channelId);
    final userRef = _firestore.collection('users').doc(safeUserId);

    await _firestore.runTransaction((transaction) async {
      final channelSnapshot = await transaction.get(ref);
      if (!channelSnapshot.exists) return;

      final channelData = channelSnapshot.data() ?? {};
      final ownerId = (channelData['adminId'] as String? ?? '').trim();
      if (ownerId != currentUser.uid) {
        throw Exception('مالك القناة فقط يمكنه إضافة المشرفين');
      }

      final targetUserSnapshot = await transaction.get(userRef);
      if (!targetUserSnapshot.exists) {
        throw Exception('المستخدم المحدد غير موجود');
      }

      if (safeUserId == ownerId) {
        throw Exception('لا يمكن إضافة مالك القناة كـ Admin');
      }

      final moderators = <String>[];
      for (final value in List<dynamic>.from(channelData['moderators'] ?? const <dynamic>[])) {
        if (value is String && value.trim().isNotEmpty) {
          moderators.add(value.trim());
        }
      }

      if (userExistsInList(moderators, safeUserId)) {
        return;
      }

      final members = <String>[];
      for (final value in List<dynamic>.from(channelData['memberIds'] ?? const <dynamic>[])) {
        if (value is String && value.trim().isNotEmpty) {
          members.add(value.trim());
        }
      }

      if (!members.contains(safeUserId)) {
        members.add(safeUserId);
      }

      moderators.add(safeUserId);
      transaction.update(ref, {
        'moderators': moderators,
        'memberIds': members,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }).timeout(_messageWriteTimeout);
  }

  Future<void> removeMember({
    required String channelId,
    required String userId,
  }) async {
    final ref = _firestore.collection('channels').doc(channelId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) return;
      final data = snapshot.data() ?? {};
      final members = List<String>.from(data['memberIds'] ?? []);
      final guests = List<String>.from(data['guestIds'] ?? []);
      final moderators = List<String>.from(data['moderators'] ?? []);
      members.removeWhere((value) => value == userId);
      guests.removeWhere((value) => value == userId);
      moderators.removeWhere((value) => value == userId);
      transaction.update(ref, {
        'memberIds': members,
        'guestIds': guests,
        'moderators': moderators,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> removeModerator({
    required String channelId,
    required String userId,
  }) async {
    final safeUserId = userId.trim();
    if (safeUserId.isEmpty) return;

    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('المستخدم غير مسجل دخول');
    }

    final ref = _firestore.collection('channels').doc(channelId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) return;

      final data = snapshot.data() ?? {};
      final ownerId = (data['adminId'] as String? ?? '').trim();
      if (ownerId != currentUser.uid) {
        throw Exception('مالك القناة فقط يمكنه إزالة المشرفين');
      }

      if (safeUserId == ownerId) {
        throw Exception('لا يمكن إزالة مالك القناة');
      }

      final moderators = <String>[];
      for (final value in List<dynamic>.from(data['moderators'] ?? const <dynamic>[])) {
        if (value is String && value.trim().isNotEmpty && value.trim() != safeUserId) {
          moderators.add(value.trim());
        }
      }

      transaction.update(ref, {
        'moderators': moderators,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }).timeout(_messageWriteTimeout);
  }

  static String _normalizeAccessType(String accessType, bool fallbackPrivate) {
    final normalized = accessType.trim().toLowerCase();
    if (normalized == 'private') return 'private';
    if (normalized == 'guest-only' ||
        normalized == 'guestonly' ||
        normalized == 'guest_only')
      return 'guest-only';
    if (fallbackPrivate) return 'private';
    return 'public';
  }

  Future<Map<String, String>> fetchUsersDisplayNames(
    List<String> userIds,
  ) async {
    final distinctIds = userIds
        .where((id) => id.trim().isNotEmpty)
        .toSet()
        .toList();
    if (distinctIds.isEmpty) return {};

    final snapshot = await _firestore.collection('users').get();
    final result = <String, String>{};
    for (final doc in snapshot.docs) {
      if (distinctIds.contains(doc.id)) {
        final username = (doc.data()['username'] as String?) ?? doc.id;
        result[doc.id] = username;
      }
    }
    return result;
  }

  Future<void> updateChannel({
    required String channelId,
    String? name,
    String? description,
    String? imageUrl,
    bool? isActive,
    String? handle,
    String? category,
    String? coverImageUrl,
  }) async {
    await _ensureAdmin();

    final payload = <String, dynamic>{};
    if (name != null) payload['name'] = name.trim();
    if (description != null) payload['description'] = description.trim();
    if (imageUrl != null) payload['imageUrl'] = imageUrl;
    if (coverImageUrl != null) payload['coverImageUrl'] = coverImageUrl;
    if (handle != null) payload['handle'] = handle.trim();
    if (category != null) payload['category'] = category.trim();
    if (isActive != null) payload['isActive'] = isActive;
    payload['updatedAt'] = FieldValue.serverTimestamp();

    await _firestore.collection('channels').doc(channelId).update(payload);
  }

  Stream<List<Channel>> followedChannels(String userId) {
    final safeUserId = userId.trim();
    if (safeUserId.isEmpty) return Stream.value(const <Channel>[]);

    return _firestore
        .collection('channels')
        .where('followers', arrayContains: safeUserId)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Channel.fromFirestore).toList());
  }

  Future<List<Channel>> searchChannels(String query, {String? category}) async {
    final normalized = query.trim();
    if (normalized.isEmpty && (category == null || category.trim().isEmpty)) {
      return const <Channel>[];
    }

    final snapshot = await _firestore.collection('channels').where('isActive', isEqualTo: true).get();
    final channels = snapshot.docs.map(Channel.fromFirestore).where((channel) {
      final matchesCategory = category == null || category.trim().isEmpty || channel.category.toLowerCase() == category.trim().toLowerCase();
      if (!matchesCategory) return false;
      if (normalized.isEmpty) return true;
      final haystack = '${channel.name} ${channel.description} ${channel.adminName} ${channel.handle} ${channel.category}'.toLowerCase();
      return haystack.contains(normalized.toLowerCase());
    }).toList();

    return channels;
  }

  Future<bool> isFollowingChannel({required String channelId, required String userId}) async {
    final safeChannelId = channelId.trim();
    final safeUserId = userId.trim();
    if (safeChannelId.isEmpty || safeUserId.isEmpty) return false;

    final channel = await getChannel(safeChannelId);
    if (channel == null) return false;
    return channel.followerIds.contains(safeUserId);
  }

  Future<bool> followChannel({required String channelId, required String userId}) async {
    final safeChannelId = channelId.trim();
    final safeUserId = userId.trim();
    if (safeChannelId.isEmpty || safeUserId.isEmpty) return false;

    final ref = _firestore.collection('channels').doc(safeChannelId);
    try {
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(ref);
        if (!snapshot.exists) throw Exception('القناة غير موجودة');

        final data = snapshot.data() ?? <String, dynamic>{};
        final followerIds = <String>[];
        for (final value in List<dynamic>.from(data['followers'] ?? const <dynamic>[])) {
          if (value is String && value.trim().isNotEmpty) followerIds.add(value.trim());
        }
        if (followerIds.contains(safeUserId)) {
          return;
        }

        followerIds.add(safeUserId);
        transaction.update(ref, {
          'followers': followerIds,
          'followersCount': followerIds.length,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }).timeout(_messageWriteTimeout);

      final channel = await getChannel(safeChannelId);
      if (channel != null && channel.adminId != safeUserId) {
        await NotificationService().createNotification(
          senderId: safeUserId,
          receiverId: channel.adminId,
          type: 'channel_follow',
          referenceId: safeChannelId,
          roomId: safeChannelId,
          channelId: safeChannelId,
          postId: '',
        );
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> unfollowChannel({required String channelId, required String userId}) async {
    final safeChannelId = channelId.trim();
    final safeUserId = userId.trim();
    if (safeChannelId.isEmpty || safeUserId.isEmpty) return false;

    final ref = _firestore.collection('channels').doc(safeChannelId);
    try {
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(ref);
        if (!snapshot.exists) throw Exception('القناة غير موجودة');

        final data = snapshot.data() ?? <String, dynamic>{};
        final followerIds = <String>[];
        for (final value in List<dynamic>.from(data['followers'] ?? const <dynamic>[])) {
          if (value is String && value.trim().isNotEmpty && value.trim() != safeUserId) {
            followerIds.add(value.trim());
          }
        }

        transaction.update(ref, {
          'followers': followerIds,
          'followersCount': followerIds.length,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }).timeout(_messageWriteTimeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool hasPermission(
    Channel channel,
    String userId,
    String permissionKey,
  ) {
    final safeUserId = userId.trim();
    if (safeUserId.isEmpty) return false;

    if (channel.adminId == safeUserId) return true;

    final normalizedModerators = channel.moderators
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    if (normalizedModerators.contains(safeUserId)) {
      final explicitPermission = channel.adminPermissions[safeUserId]?[permissionKey];
      if (explicitPermission == false) {
        return false;
      }
      return true;
    }

    final permissions = channel.adminPermissions[safeUserId] ?? const {};
    if (permissions[permissionKey] == true) return true;

    return false;
  }

  static void validateChannelPostPayload({
    required String text,
    required String mediaUrl,
    required String mediaType,
  }) {
    final normalizedText = text.trim();
    final normalizedMediaUrl = mediaUrl.trim();
    final normalizedMediaType = mediaType.trim().toLowerCase();

    if (normalizedText.isEmpty && normalizedMediaUrl.isEmpty) {
      throw Exception('لا يمكن إنشاء منشور فارغ');
    }

    if (normalizedMediaUrl.isNotEmpty) {
      final mediaUri = Uri.tryParse(normalizedMediaUrl);
      if (mediaUri == null ||
          mediaUri.scheme != 'https' ||
          mediaUri.host.isEmpty) {
        throw Exception('رابط الوسائط غير صالح');
      }
    }

    if (normalizedText.isEmpty && normalizedMediaType.isEmpty) {
      throw Exception('نوع المنشور غير صالح');
    }

    final supportedTypes = {
      'text',
      'image',
      'video',
      'audio',
      'file',
      'document',
      'none',
    };
    if (normalizedMediaUrl.isNotEmpty &&
        !supportedTypes.contains(normalizedMediaType)) {
      throw Exception('نوع الوسائط غير مدعوم في القناة');
    }
  }

  static bool isUserViewRecorded({
    required List<dynamic>? viewedBy,
    required String userId,
  }) {
    final safeUserId = userId.trim();
    if (safeUserId.isEmpty) return true;

    for (final value in viewedBy ?? const <dynamic>[]) {
      if (value is String && value.trim() == safeUserId) return true;
      if (value is Map && value['userId'] is String) {
        final mappedUserId = (value['userId'] as String).trim();
        if (mappedUserId == safeUserId) return true;
      }
    }

    return false;
  }

  Future<void> recordMessageView({
    required String channelId,
    required String messageId,
    required String userId,
  }) async {
    final safeUserId = userId.trim();
    final safeMessageId = messageId.trim();
    if (safeUserId.isEmpty || safeMessageId.isEmpty) {
      return;
    }

    final messageRef = _firestore
        .collection('channels')
        .doc(channelId)
        .collection('messages')
        .doc(safeMessageId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(messageRef);
      if (!snapshot.exists) return;

      final data = snapshot.data() ?? <String, dynamic>{};
      final existingViewers = <String>[];
      for (final value in data['viewedBy'] as List<dynamic>? ?? const <dynamic>[]) {
        if (value is String && value.trim().isNotEmpty) {
          existingViewers.add(value.trim());
        } else if (value is Map && value['userId'] is String) {
          final mappedUserId = (value['userId'] as String).trim();
          if (mappedUserId.isNotEmpty) existingViewers.add(mappedUserId);
        }
      }

      if (existingViewers.contains(safeUserId)) {
        return;
      }

      final updatedViewers = [...existingViewers, safeUserId];
      transaction.update(messageRef, {
        'viewedBy': updatedViewers,
        'viewCount': updatedViewers.length,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }).timeout(_messageWriteTimeout);
  }

  Future<void> publishMessage({
    required String channelId,
    required String senderId,
    required String senderName,
    required String text,
    String mediaUrl = '',
    String mediaType = 'text',
    String thumbnailUrl = '',
    String? clientRequestId,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('المستخدم غير مسجل دخول');
    }

    final safeChannelId = channelId.trim();
    if (safeChannelId.isEmpty) {
      throw Exception('معرف القناة غير صالح');
    }

    final requestedSenderId = senderId.trim();
    if (requestedSenderId.isNotEmpty && requestedSenderId != currentUser.uid) {
      throw Exception('هوية المرسل غير صالحة');
    }

    final resolvedSenderId = currentUser.uid;
    final resolvedSenderName = senderName.trim().isNotEmpty
        ? senderName.trim()
        : (currentUser.email ?? 'مستخدم');
    final normalizedText = text.trim();
    final normalizedMediaUrl = mediaUrl.trim();
    final normalizedMediaType = mediaType.trim().isEmpty
        ? (normalizedMediaUrl.isNotEmpty ? 'image' : 'text')
        : mediaType.trim().toLowerCase();

    validateChannelPostPayload(
      text: normalizedText,
      mediaUrl: normalizedMediaUrl,
      mediaType: normalizedMediaType,
    );

    final channelDoc = await _firestore.collection('channels').doc(safeChannelId).get();
    if (!channelDoc.exists) {
      throw Exception('القناة غير موجودة');
    }

    final channel = Channel.fromFirestore(channelDoc);
    final canPublish = hasPermission(channel, resolvedSenderId, 'canPost');
    if (!canPublish) {
      throw Exception('ليس لديك صلاحية نشر منشورات في هذه القناة');
    }

    final messageReference =
        clientRequestId == null || clientRequestId.trim().isEmpty
        ? _firestore
              .collection('channels')
                .doc(safeChannelId)
              .collection('messages')
              .doc()
        : _firestore
              .collection('channels')
                .doc(safeChannelId)
              .collection('messages')
              .doc(clientRequestId.trim());

    final payload = buildMessagePayload(
      channelId: safeChannelId,
      senderId: resolvedSenderId,
      senderName: resolvedSenderName,
      text: normalizedText,
      mediaUrl: normalizedMediaUrl,
      mediaType: normalizedMediaType,
      thumbnailUrl: thumbnailUrl,
      parentMessageId: '',
      reactions: const {},
      replyCount: 0,
      extraData: const {},
    );

    await messageReference.set(payload).timeout(_messageWriteTimeout);

    try {
      final receiverIds = <String>{
        ...channel.memberIds,
        ...channel.moderators,
        ...channel.guestIds,
      }.where((value) => value.trim().isNotEmpty).toList();

      await NotificationService().sendChannelPostNotification(
        channelId: safeChannelId,
        postId: messageReference.id,
        channelName: channel.name,
        senderId: resolvedSenderId,
        senderName: resolvedSenderName,
        receiverIds: receiverIds,
      );
    } catch (_) {
      // Do not let notification delivery failures block channel post creation.
    }
  }

  Future<void> updateMessage({
    required String channelId,
    required String messageId,
    required String text,
    String mediaUrl = '',
    String mediaType = 'text',
    String thumbnailUrl = '',
  }) async {
    await _ensureAdmin();

    if (text.trim().isEmpty && mediaUrl.trim().isEmpty) {
      throw Exception('لا يمكن حفظ منشور فارغ');
    }

    await _firestore
        .collection('channels')
        .doc(channelId)
        .collection('messages')
        .doc(messageId)
        .update({
          'text': text.trim(),
          'mediaUrl': mediaUrl,
          'mediaType': mediaType,
          'thumbnailUrl': thumbnailUrl,
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  Future<void> softDeleteMessage({
    required String channelId,
    required String messageId,
  }) async {
    final messageRef = _firestore
        .collection('channels')
        .doc(channelId)
        .collection('messages')
        .doc(messageId);

    final channelRef = _firestore.collection('channels').doc(channelId);

    await _firestore.runTransaction((transaction) async {
      final messageSnapshot = await transaction.get(messageRef);
      if (!messageSnapshot.exists) return;

      final channelSnapshot = await transaction.get(channelRef);
      if (channelSnapshot.exists) {
        final pinnedMessageId = (channelSnapshot.data()?['pinnedMessageId'] as String? ?? '').trim();
        if (pinnedMessageId == messageId.trim()) {
          transaction.update(channelRef, {
            'pinnedMessageId': '',
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }

      transaction.update(messageRef, {
        'isDeleted': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }).timeout(_messageWriteTimeout);
  }

  // --- دالة التفاعل مع الرسائل (Reactions) ---
  Future<void> toggleReaction({
    required String channelId,
    required String messageId,
    required String emoji,
    required String userId,
  }) async {
    final docRef = _firestore
        .collection('channels')
        .doc(channelId)
        .collection('messages')
        .doc(messageId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists) return;

      final data = snapshot.data()!;
      final reactions = Map<String, dynamic>.from(data['reactions'] ?? {});
      final usersWhoReacted = List<String>.from(reactions[emoji] ?? []);

      if (usersWhoReacted.contains(userId)) {
        usersWhoReacted.remove(userId);
        if (usersWhoReacted.isEmpty) {
          reactions.remove(emoji);
        } else {
          reactions[emoji] = usersWhoReacted;
        }
      } else {
        usersWhoReacted.add(userId);
        reactions[emoji] = usersWhoReacted;
      }

      transaction.update(docRef, {'reactions': reactions});
    });
  }

  // --- دوال التعليقات (Threaded Replies) ---
  Stream<List<ChannelMessage>> commentsStream(
    String channelId,
    String parentMessageId,
  ) {
    return _firestore
        .collection('channels')
        .doc(channelId)
        .collection('messages')
        .where('isDeleted', isEqualTo: false)
        .where('parentMessageId', isEqualTo: parentMessageId)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => ChannelMessage.fromFirestore(doc, channelId))
              .toList();
        });
  }

  Future<void> publishComment({
    required String channelId,
    required String parentMessageId,
    required String senderId,
    required String senderName,
    required String text,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('المستخدم غير مسجل دخول');
    if (text.trim().isEmpty) throw Exception('لا يمكن إرسال تعليق فارغ');

    final resolvedSenderId = senderId.trim().isNotEmpty ? senderId.trim() : currentUser.uid;
    final resolvedSenderName = senderName.trim().isNotEmpty
        ? senderName.trim()
        : (currentUser.email ?? 'مستخدم');

    final batch = _firestore.batch();

    final commentRef = _firestore
        .collection('channels')
        .doc(channelId)
        .collection('messages')
        .doc();
    batch.set(
      commentRef,
      buildMessagePayload(
        channelId: channelId,
        senderId: resolvedSenderId,
        senderName: resolvedSenderName,
        text: text,
        parentMessageId: parentMessageId,
        reactions: const {},
        replyCount: 0,
        extraData: const {},
      ),
    );

    final parentRef = _firestore
        .collection('channels')
        .doc(channelId)
        .collection('messages')
        .doc(parentMessageId);
    batch.update(parentRef, {
      'replyCount': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  // --- دوال الرسائل المثبتة (Pinned Messages) ---
  Future<void> pinMessage({
    required String channelId,
    required String messageId,
    String? currentUserId,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('المستخدم غير مسجل دخول');

    final effectiveUserId = (currentUserId ?? currentUser.uid).trim();
    if (effectiveUserId.isEmpty) throw Exception('معرّف المستخدم غير صالح');

    final channelDoc = await _firestore.collection('channels').doc(channelId).get();
    if (!channelDoc.exists) return;

    final channel = Channel.fromFirestore(channelDoc);
    final isOwner = channel.adminId == effectiveUserId;
    final permissions = channel.adminPermissions[effectiveUserId] ?? const {};
    final canPin = isOwner || permissions['canPinPosts'] == true;
    if (!canPin) {
      throw Exception('ليس لديك صلاحية تثبيت المنشورات');
    }

    final messageRef = _firestore
        .collection('channels')
        .doc(channelId)
        .collection('messages')
        .doc(messageId);
    final messageSnapshot = await messageRef.get();
    if (!messageSnapshot.exists) throw Exception('المنشور المطلوب غير موجود');
    final messageData = messageSnapshot.data() ?? <String, dynamic>{};
    if (messageData['isDeleted'] == true) {
      throw Exception('لا يمكن تثبيت منشور محذوف');
    }

    if ((channel.pinnedMessageId).trim() == messageId.trim()) return;

    await _firestore.collection('channels').doc(channelId).update({
      'pinnedMessageId': messageId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> unpinMessage({required String channelId, String? currentUserId}) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('المستخدم غير مسجل دخول');

    final effectiveUserId = (currentUserId ?? currentUser.uid).trim();
    if (effectiveUserId.isEmpty) throw Exception('معرّف المستخدم غير صالح');

    final channelDoc = await _firestore.collection('channels').doc(channelId).get();
    if (!channelDoc.exists) return;

    final channel = Channel.fromFirestore(channelDoc);
    final isOwner = channel.adminId == effectiveUserId;
    final permissions = channel.adminPermissions[effectiveUserId] ?? const {};
    final canPin = isOwner || permissions['canPinPosts'] == true;
    if (!canPin) {
      throw Exception('ليس لديك صلاحية إلغاء تثبيت المنشورات');
    }

    if ((channel.pinnedMessageId).trim().isEmpty) return;

    await _firestore.collection('channels').doc(channelId).update({
      'pinnedMessageId': '',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<ChannelMessage?> getMessage({
    required String channelId,
    required String messageId,
  }) async {
    final doc = await _firestore
        .collection('channels')
        .doc(channelId)
        .collection('messages')
        .doc(messageId)
        .get();
    if (!doc.exists) return null;
    final message = ChannelMessage.fromFirestore(doc, channelId);
    if (message.isDeleted) return null;
    return message;
  }

  // --- دوال الاستطلاعات (Polls) ---
  Future<void> publishPoll({
    required String channelId,
    required String senderId,
    required String senderName,
    required String question,
    required List<String> options,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('المستخدم غير مسجل دخول');

    final pollOptions = options
        .asMap()
        .entries
        .map(
          (e) => {
            'id': e.key.toString(),
            'text': e.value.trim(),
            'votes': <String>[],
          },
        )
        .toList();

    final resolvedSenderId = senderId.trim().isNotEmpty ? senderId.trim() : currentUser.uid;
    final resolvedSenderName = senderName.trim().isNotEmpty
        ? senderName.trim()
        : (currentUser.email ?? 'مستخدم');

    await _firestore
        .collection('channels')
        .doc(channelId)
        .collection('messages')
        .add(
          buildMessagePayload(
            channelId: channelId,
            senderId: resolvedSenderId,
            senderName: resolvedSenderName,
            text: '📊 استطلاع رأي: $question',
            extraData: {
              'isPoll': true,
              'pollQuestion': question,
              'pollOptions': pollOptions,
            },
          ),
        );

    await _firestore.collection('channels').doc(channelId).update({
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> voteOnPoll({
    required String channelId,
    required String messageId,
    required String optionId,
    required String userId,
  }) async {
    final docRef = _firestore
        .collection('channels')
        .doc(channelId)
        .collection('messages')
        .doc(messageId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists) return;

      final data = snapshot.data()!;
      final extraData = Map<String, dynamic>.from(data['extraData'] ?? {});

      if (extraData['isPoll'] != true) return;

      List<dynamic> options = List.from(extraData['pollOptions'] ?? []);

      for (var opt in options) {
        List<String> votes = List<String>.from(opt['votes'] ?? []);
        votes.remove(userId);
        opt['votes'] = votes;
      }

      for (var opt in options) {
        if (opt['id'] == optionId) {
          List<String> votes = List<String>.from(opt['votes'] ?? []);
          votes.add(userId);
          opt['votes'] = votes;
          break;
        }
      }

      extraData['pollOptions'] = options;
      transaction.update(docRef, {'extraData': extraData});
    });
  }
}
