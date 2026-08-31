import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';

import '../models/group.dart';
import '../models/group_post.dart';
import 'media_service.dart';

class GroupService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static const Duration _writeTimeout = Duration(seconds: 30);
  final Map<String, Future<void>> _groupSettingsWriteLocks = <String, Future<void>>{};

  CollectionReference<Map<String, dynamic>> get _groups => _firestore.collection('groups');

  User get _currentUser {
    final user = _auth.currentUser;
    if (user == null) throw Exception('يجب تسجيل الدخول أولاً');
    return user;
  }

  static List<String> _normalizeUserList(dynamic value) {
    final seen = <String>{};
    final result = <String>[];
    if (value is! List) return result;
    for (final item in value) {
      if (item is String) {
        final normalized = item.trim();
        if (normalized.isEmpty || seen.contains(normalized)) continue;
        seen.add(normalized);
        result.add(normalized);
      }
    }
    return result;
  }

  static bool _isGroupOwner(String ownerId, String userId) {
    return ownerId.trim() == userId.trim() && userId.trim().isNotEmpty;
  }

  static bool _isGroupModerator(Group group, String userId) {
    final safeUserId = userId.trim();
    return safeUserId.isNotEmpty && group.moderators.any((id) => id.trim() == safeUserId);
  }

  static bool _isGroupMember(Group group, String userId) {
    final safeUserId = userId.trim();
    return safeUserId.isNotEmpty && group.memberIds.any((id) => id.trim() == safeUserId);
  }

  Future<void> _requireExistingUser(String userId) async {
    final trimmed = userId.trim();
    if (trimmed.isEmpty) throw Exception('معرف المستخدم غير صالح');
    final userDoc = await _firestore.collection('users').doc(trimmed).get();
    if (!userDoc.exists) throw Exception('المستخدم غير موجود في النظام');
  }

  Future<bool> canAccessGroup(String groupId, String userId) async {
    final snapshot = await _groups.doc(groupId).get();
    if (!snapshot.exists) return false;
    final group = Group.fromFirestore(snapshot);
    if (!group.isPrivate) return true;
    if (_isGroupOwner(group.ownerId, userId)) return true;
    return _isGroupMember(group, userId);
  }

  Stream<List<Group>> discoverGroups(String userId) {
    return _groups.orderBy('createdAt', descending: true).snapshots().map((snapshot) {
      return snapshot.docs.map(Group.fromFirestore).where((group) {
        if (!group.isPrivate) return true;
        if (_isGroupOwner(group.ownerId, userId)) return true;
        return _isGroupMember(group, userId);
      }).toList();
    });
  }

  Stream<List<Group>> myGroups(String userId) {
    return _groups.where('memberIds', arrayContains: userId).snapshots().map((snapshot) {
      return snapshot.docs.map(Group.fromFirestore).toList();
    });
  }

  Stream<Group?> groupStream(String groupId, {String? userId}) {
    return _groups.doc(groupId).snapshots().map((snapshot) {
      if (!snapshot.exists) return null;
      final group = Group.fromFirestore(snapshot);
      final requesterId = userId?.trim() ?? '';
      if (group.isPrivate && requesterId.isNotEmpty) {
        if (_isGroupOwner(group.ownerId, requesterId) || _isGroupMember(group, requesterId)) {
          return group;
        }
        return null;
      }
      return group;
    });
  }

  Stream<List<GroupPost>> postsStream(String groupId) {
    return _groups.doc(groupId).collection('posts').orderBy('createdAt', descending: true).snapshots().map((snapshot) {
      return snapshot.docs.map(GroupPost.fromFirestore).toList();
    });
  }

  Stream<List<String>> memberIdsStream(String groupId) {
    return _groups.doc(groupId).snapshots().map((snapshot) {
      if (!snapshot.exists) return const <String>[];
      final data = snapshot.data() ?? <String, dynamic>{};
      return _normalizeUserList(data['memberIds']);
    });
  }

  Stream<List<String>> moderatorsStream(String groupId) {
    return _groups.doc(groupId).snapshots().map((snapshot) {
      if (!snapshot.exists) return const <String>[];
      final data = snapshot.data() ?? <String, dynamic>{};
      return _normalizeUserList(data['moderators']);
    });
  }

  Future<bool> canManageGroupAdmins(String groupId, String userId) async {
    final snapshot = await _groups.doc(groupId).get();
    if (!snapshot.exists) return false;
    final data = snapshot.data() ?? <String, dynamic>{};
    final ownerId = (data['ownerId'] as String? ?? '').trim();
    return userId.trim() == ownerId;
  }

  Future<bool> canManageMembers(String groupId, String userId) async {
    final snapshot = await _groups.doc(groupId).get();
    if (!snapshot.exists) return false;
    final data = snapshot.data() ?? <String, dynamic>{};
    final ownerId = (data['ownerId'] as String? ?? '').trim();
    final moderators = _normalizeUserList(data['moderators']);
    return userId.trim() == ownerId || moderators.contains(userId.trim());
  }

  Future<bool> canManageGroupSettings(String groupId, String userId, {bool includePrivateSetting = false}) async {
    final snapshot = await _groups.doc(groupId).get();
    if (!snapshot.exists) return false;
    final data = snapshot.data() ?? <String, dynamic>{};
    final ownerId = (data['ownerId'] as String? ?? '').trim();
    final moderators = _normalizeUserList(data['moderators']);
    final isOwner = userId.trim() == ownerId;
    final isModerator = moderators.contains(userId.trim());
    if (isOwner) return true;
    if (includePrivateSetting) return false;
    return isModerator;
  }

  Future<String> createGroup({required String name, required String description, required bool isPrivate}) async {
    final user = _currentUser;
    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    final ownerName = userDoc.data()?['username'] as String? ?? user.displayName ?? user.email ?? 'مستخدم';
    final trimmedName = name.trim();
    final trimmedDescription = description.trim();
    if (trimmedName.isEmpty) throw Exception('اسم المجموعة مطلوب');

    final groupRef = _groups.doc();
    final payload = {
      'name': trimmedName,
      'description': trimmedDescription,
      'imageUrl': '',
      'ownerId': user.uid,
      'ownerName': ownerName,
      'isPrivate': isPrivate,
      'memberIds': [user.uid],
      'moderators': <String>[],
      'memberCount': 1,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await _firestore.runTransaction((transaction) async {
      transaction.set(groupRef, payload);
      transaction.set(groupRef.collection('members').doc(user.uid), {
        'userId': user.uid,
        'role': 'owner',
        'joinedAt': FieldValue.serverTimestamp(),
      });
    }).timeout(_writeTimeout);
    return groupRef.id;
  }

  Future<void> joinGroup(String groupId) async {
    final user = _currentUser;
    final groupRef = _groups.doc(groupId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(groupRef);
      final data = snapshot.data();
      if (data == null) throw Exception('المجموعة غير موجودة');

      final currentMembers = _normalizeUserList(data['memberIds']);
      final normalizedUserId = user.uid.trim();
      if (normalizedUserId.isEmpty) throw Exception('معرف المستخدم غير صالح');

      if (currentMembers.contains(normalizedUserId)) {
        transaction.set(groupRef.collection('members').doc(normalizedUserId), {
          'userId': normalizedUserId,
          'role': 'member',
          'joinedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return;
      }

      if (data['ownerId'] == normalizedUserId) return;

      if (data['isPrivate'] == true) {
        transaction.set(groupRef.collection('joinRequests').doc(normalizedUserId), {
          'userId': normalizedUserId,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return;
      }

      currentMembers.add(normalizedUserId);
      transaction.set(groupRef.collection('members').doc(normalizedUserId), {
        'userId': normalizedUserId,
        'role': 'member',
        'joinedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      transaction.update(groupRef, {
        'memberIds': _normalizeUserList(currentMembers),
        'memberCount': _normalizeUserList(currentMembers).length,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }).timeout(_writeTimeout);
  }

  Future<void> promoteMemberToAdmin({
    required String groupId,
    required String targetUserId,
  }) async {
    final actor = _currentUser;
    final groupRef = _groups.doc(groupId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(groupRef);
      if (!snapshot.exists) throw Exception('المجموعة غير موجودة');

      final data = snapshot.data() ?? <String, dynamic>{};
      final ownerId = (data['ownerId'] as String? ?? '').trim();
      if (actor.uid != ownerId) {
        throw Exception('مالك المجموعة فقط يمكنه ترقية الأعضاء إلى مشرفين');
      }

      final targetId = targetUserId.trim();
      if (targetId.isEmpty) throw Exception('معرف المستخدم غير صالح');
      if (targetId == ownerId) throw Exception('لا يمكن ترقية مالك المجموعة');
      await _requireExistingUser(targetId);

      final members = _normalizeUserList(data['memberIds']);
      if (!members.contains(targetId)) {
        throw Exception('المستخدم ليس عضوًا في هذه المجموعة');
      }

      final moderators = _normalizeUserList(data['moderators']);
      if (moderators.contains(targetId)) {
        transaction.set(groupRef.collection('members').doc(targetId), {
          'userId': targetId,
          'role': 'admin',
          'joinedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return;
      }

      moderators.add(targetId);
      transaction.set(groupRef.collection('members').doc(targetId), {
        'userId': targetId,
        'role': 'admin',
        'joinedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      transaction.update(groupRef, {
        'moderators': _normalizeUserList(moderators),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }).timeout(_writeTimeout);
  }

  Future<void> demoteAdmin({
    required String groupId,
    required String targetUserId,
  }) async {
    final actor = _currentUser;
    final groupRef = _groups.doc(groupId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(groupRef);
      if (!snapshot.exists) throw Exception('المجموعة غير موجودة');

      final data = snapshot.data() ?? <String, dynamic>{};
      final ownerId = (data['ownerId'] as String? ?? '').trim();
      if (actor.uid != ownerId) {
        throw Exception('مالك المجموعة فقط يمكنه إلغاء صلاحيات المشرفين');
      }

      final targetId = targetUserId.trim();
      if (targetId.isEmpty) throw Exception('معرف المستخدم غير صالح');
      if (targetId == ownerId) throw Exception('لا يمكن إلغاء صلاحيات مالك المجموعة');

      final moderators = _normalizeUserList(data['moderators']);
      if (!moderators.remove(targetId)) {
        transaction.set(groupRef.collection('members').doc(targetId), {
          'userId': targetId,
          'role': 'member',
          'joinedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return;
      }

      transaction.set(groupRef.collection('members').doc(targetId), {
        'userId': targetId,
        'role': 'member',
        'joinedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      transaction.update(groupRef, {
        'moderators': moderators,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }).timeout(_writeTimeout);
  }

  Future<void> removeAdmin({
    required String groupId,
    required String targetUserId,
  }) async {
    await demoteAdmin(groupId: groupId, targetUserId: targetUserId);
  }

  Future<void> addMember({
    required String groupId,
    required String userId,
  }) async {
    final actor = _currentUser;
    final groupRef = _groups.doc(groupId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(groupRef);
      if (!snapshot.exists) throw Exception('المجموعة غير موجودة');

      final data = snapshot.data() ?? <String, dynamic>{};
      final ownerId = (data['ownerId'] as String? ?? '').trim();
      final moderators = _normalizeUserList(data['moderators']);
      final isOwner = actor.uid == ownerId;
      final isModerator = moderators.contains(actor.uid);

      if (!isOwner && !isModerator) {
        throw Exception('ليس لديك صلاحية إضافة أعضاء إلى هذه المجموعة');
      }

      final targetUserId = userId.trim();
      if (targetUserId.isEmpty) throw Exception('معرف المستخدم غير صالح');
      if (targetUserId == ownerId) throw Exception('لا يمكن إضافة مالك المجموعة كعضو');
      await _requireExistingUser(targetUserId);

      final members = _normalizeUserList(data['memberIds']);
      if (members.contains(targetUserId)) {
        transaction.set(groupRef.collection('members').doc(targetUserId), {
          'userId': targetUserId,
          'role': 'member',
          'joinedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return;
      }

      members.add(targetUserId);
      transaction.set(groupRef.collection('members').doc(targetUserId), {
        'userId': targetUserId,
        'role': 'member',
        'joinedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      transaction.update(groupRef, {
        'memberIds': _normalizeUserList(members),
        'memberCount': _normalizeUserList(members).length,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }).timeout(_writeTimeout);
  }

  Future<void> removeMember({
    required String groupId,
    required String userId,
  }) async {
    final actor = _currentUser;
    final groupRef = _groups.doc(groupId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(groupRef);
      if (!snapshot.exists) throw Exception('المجموعة غير موجودة');

      final data = snapshot.data() ?? <String, dynamic>{};
      final ownerId = (data['ownerId'] as String? ?? '').trim();
      final moderators = _normalizeUserList(data['moderators']);
      final isOwner = actor.uid == ownerId;
      final isModerator = moderators.contains(actor.uid);

      if (!isOwner && !isModerator) {
        throw Exception('ليس لديك صلاحية إزالة أعضاء من هذه المجموعة');
      }

      final targetUserId = userId.trim();
      if (targetUserId.isEmpty) throw Exception('معرف المستخدم غير صالح');
      if (targetUserId == ownerId) throw Exception('لا يمكن إزالة مالك المجموعة');

      final members = _normalizeUserList(data['memberIds']);
      final groupModerators = _normalizeUserList(data['moderators']);
      final wasMember = members.remove(targetUserId);
      final wasModerator = groupModerators.remove(targetUserId);

      transaction.delete(groupRef.collection('members').doc(targetUserId));
      transaction.update(groupRef, {
        'memberIds': _normalizeUserList(members),
        'moderators': _normalizeUserList(groupModerators),
        'memberCount': _normalizeUserList(members).length,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!wasMember && !wasModerator) {
        return;
      }
    }).timeout(_writeTimeout);
  }

  Future<void> leaveGroup(String groupId) async {
    final user = _currentUser;
    final groupRef = _groups.doc(groupId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(groupRef);
      final data = snapshot.data();
      if (data == null) throw Exception('المجموعة غير موجودة');
      if (data['ownerId'] == user.uid) throw Exception('لا يمكن لمالك المجموعة مغادرتها');

      final members = _normalizeUserList(data['memberIds']);
      final normalizedUserId = user.uid.trim();
      if (normalizedUserId.isEmpty) throw Exception('معرف المستخدم غير صالح');

      if (!members.remove(normalizedUserId)) return;

      final moderators = _normalizeUserList(data['moderators']);
      if (moderators.contains(normalizedUserId)) {
        moderators.remove(normalizedUserId);
      }

      transaction.delete(groupRef.collection('members').doc(normalizedUserId));
      transaction.update(groupRef, {
        'memberIds': _normalizeUserList(members),
        'moderators': _normalizeUserList(moderators),
        'memberCount': _normalizeUserList(members).length,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }).timeout(_writeTimeout);
  }

  Future<void> _runSerializedGroupSettingsWrite(
    String groupId,
    Future<void> Function() operation,
  ) {
    final key = groupId.trim();
    if (key.isEmpty) {
      throw Exception('معرف المجموعة غير صالح');
    }

    final previous = _groupSettingsWriteLocks[key];
    if (previous != null) {
      return previous
          .then((_) => _runSerializedGroupSettingsWrite(key, operation))
          .catchError((_) => _runSerializedGroupSettingsWrite(key, operation));
    }

    final future = operation().whenComplete(() {
      _groupSettingsWriteLocks.remove(key);
    });
    _groupSettingsWriteLocks[key] = future;
    return future;
  }

  Future<void> updateGroupSettings({
    required String groupId,
    String? name,
    String? description,
    String? imageUrl,
    bool? isPrivate,
  }) async {
    final user = _currentUser;
    final safeGroupId = groupId.trim();
    if (safeGroupId.isEmpty) {
      throw Exception('معرف المجموعة غير صالح');
    }

    await _runSerializedGroupSettingsWrite(safeGroupId, () async {
      final groupRef = _groups.doc(safeGroupId);
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(groupRef);
        if (!snapshot.exists) throw Exception('المجموعة غير موجودة');

        final data = snapshot.data() ?? <String, dynamic>{};
        final ownerId = (data['ownerId'] as String? ?? '').trim();
        final moderators = _normalizeUserList(data['moderators']);
        final isOwner = user.uid == ownerId;
        final isModerator = moderators.contains(user.uid);
        final privacyChangeRequested = isPrivate != null;

        if (!isOwner && !(isModerator && !privacyChangeRequested)) {
          throw Exception('ليس لديك صلاحية تعديل إعدادات هذه المجموعة');
        }

        final payload = <String, dynamic>{
          'updatedAt': FieldValue.serverTimestamp(),
        };

        if (name != null) {
          final trimmedName = name.trim();
          if (trimmedName.isEmpty) throw Exception('اسم المجموعة مطلوب');
          payload['name'] = trimmedName;
        }

        if (description != null) {
          payload['description'] = description.trim();
        }

        if (imageUrl != null) {
          payload['imageUrl'] = imageUrl.trim();
        }

        if (isPrivate != null) {
          if (!isOwner) {
            throw Exception('مالك المجموعة فقط يمكنه تعديل خصوصية المجموعة');
          }
          payload['isPrivate'] = isPrivate;
        }

        if (payload.length == 1) return;
        transaction.update(groupRef, payload);
      }).timeout(_writeTimeout);
    });
  }

  Future<void> setGroupPrivacy({
    required String groupId,
    required bool isPrivate,
  }) async {
    await updateGroupSettings(groupId: groupId, isPrivate: isPrivate);
  }

  Future<String> createPost({
    required String groupId,
    required String text,
    String mediaUrl = '',
    String mediaType = 'none',
  }) async {
    final user = _currentUser;
    final safeGroupId = groupId.trim();
    if (safeGroupId.isEmpty) throw Exception('معرف المجموعة مطلوب');

    await _requireMember(safeGroupId, user.uid);

    final normalizedText = text.trim();
    final normalizedMediaUrl = mediaUrl.trim();
    final normalizedMediaType = mediaType.trim();

    if (normalizedText.isEmpty && normalizedMediaUrl.isEmpty) {
      throw Exception('لا يمكن نشر محتوى فارغ');
    }

    if (normalizedMediaUrl.isNotEmpty && normalizedMediaType.isEmpty) {
      throw Exception('نوع الوسائط مطلوب عند وجود رابط وسائط');
    }

    if (normalizedMediaUrl.isNotEmpty) {
      final mediaUri = Uri.tryParse(normalizedMediaUrl);
      if (mediaUri == null || mediaUri.scheme != 'https' || mediaUri.host.isEmpty) {
        throw Exception('رابط الوسائط غير صالح');
      }
      if (normalizedMediaType != 'image' && normalizedMediaType != 'video') {
        throw Exception('نوع الوسائط غير مدعوم');
      }
    }

    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    final authorName =
        userDoc.data()?['username'] as String? ??
        user.displayName ??
        user.email ??
        'مستخدم';

    final postRef = _groups.doc(safeGroupId).collection('posts').doc();
    await postRef.set({
      'groupId': safeGroupId,
      'authorId': user.uid,
      'authorName': authorName,
      'text': normalizedText,
      'mediaUrl': normalizedMediaUrl,
      'mediaType': normalizedMediaType.isEmpty ? 'none' : normalizedMediaType,
      'likes': <String>[],
      'commentsCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }).timeout(_writeTimeout);

    return postRef.id;
  }

  Future<String> sendGroupMediaMessage({
    required String groupId,
    required String text,
    String mediaUrl = '',
    String mediaType = 'text',
    String senderId = '',
  }) async {
    final actorId = senderId.trim().isNotEmpty ? senderId.trim() : _currentUser.uid;
    final safeGroupId = groupId.trim();
    if (safeGroupId.isEmpty) throw Exception('معرف المجموعة مطلوب');

    await _requireMember(safeGroupId, actorId);

    final normalizedText = text.trim();
    final normalizedMediaUrl = mediaUrl.trim();
    final normalizedMediaType = mediaType.trim().isEmpty ? 'text' : mediaType.trim();

    if (normalizedText.isEmpty && normalizedMediaUrl.isEmpty) {
      throw Exception('لا يمكن إرسال محتوى فارغ');
    }

    final senderDoc = await _firestore.collection('users').doc(actorId).get();
    final senderName =
        senderDoc.data()?['username'] as String? ??
        _currentUser.displayName ??
        _currentUser.email ??
        'مستخدم';

    final messageRef = _groups.doc(safeGroupId).collection('messages').doc();
    await messageRef.set({
      'groupId': safeGroupId,
      'senderId': actorId,
      'senderName': senderName,
      'text': normalizedText,
      'mediaUrl': normalizedMediaUrl,
      'mediaType': normalizedMediaType,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'isDeleted': false,
      'status': 'sent',
    }).timeout(_writeTimeout);

    return messageRef.id;
  }

  Future<MediaUploadResult> uploadGroupMedia({
    Uint8List? bytes,
    XFile? file,
    required String fileName,
    required bool isVideo,
    Function(UploadProgress)? onProgress,
  }) async {
    if (bytes != null && bytes.isEmpty) {
      return const MediaUploadResult(
        success: false,
        error: 'ملف الوسائط فارغ',
      );
    }

    if (bytes == null && file == null) {
      return const MediaUploadResult(
        success: false,
        error: 'لم يتم اختيار ملف صالح',
      );
    }

    final mediaService = MediaService();
    final result = bytes != null
        ? await mediaService.uploadBytesWithResultAndProgress(
            bytes,
            fileName,
            isVideo: isVideo,
            onProgress: onProgress,
          )
        : await mediaService.uploadXFileWithResult(
            file!,
            isVideo: isVideo,
            onProgress: onProgress,
          );

    if (!result.success || (result.url ?? '').trim().isEmpty) {
      return result;
    }

    return result;
  }

  Future<List<String>> pendingJoinRequests(String groupId) async {
    final safeGroupId = groupId.trim();
    if (safeGroupId.isEmpty) throw Exception('معرف المجموعة مطلوب');

    final snapshot = await _groups.doc(safeGroupId).collection('joinRequests').get();
    return snapshot.docs
        .map((doc) => doc.id.trim())
        .where((userId) => userId.isNotEmpty)
        .toList();
  }

  Future<void> acceptJoinRequest({
    required String groupId,
    required String userId,
  }) async {
    final actor = _currentUser;
    final safeGroupId = groupId.trim();
    final safeUserId = userId.trim();

    if (safeGroupId.isEmpty) throw Exception('معرف المجموعة مطلوب');
    if (safeUserId.isEmpty) throw Exception('معرف المستخدم غير صالح');
    if (!(await canManageMembers(safeGroupId, actor.uid))) {
      throw Exception('ليس لديك صلاحية قبول طلبات الانضمام');
    }

    final groupRef = _groups.doc(safeGroupId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(groupRef);
      if (!snapshot.exists) throw Exception('المجموعة غير موجودة');

      final data = snapshot.data() ?? <String, dynamic>{};
      final memberIds = _normalizeUserList(data['memberIds']);
      if (!memberIds.contains(safeUserId)) {
        memberIds.add(safeUserId);
      }

      transaction.set(
        groupRef.collection('members').doc(safeUserId),
        {
          'userId': safeUserId,
          'role': 'member',
          'joinedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      transaction.delete(groupRef.collection('joinRequests').doc(safeUserId));
      transaction.update(groupRef, {
        'memberIds': _normalizeUserList(memberIds),
        'memberCount': _normalizeUserList(memberIds).length,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }).timeout(_writeTimeout);
  }

  Future<void> rejectJoinRequest({
    required String groupId,
    required String userId,
  }) async {
    final actor = _currentUser;
    final safeGroupId = groupId.trim();
    final safeUserId = userId.trim();

    if (safeGroupId.isEmpty) throw Exception('معرف المجموعة مطلوب');
    if (safeUserId.isEmpty) throw Exception('معرف المستخدم غير صالح');
    if (!(await canManageMembers(safeGroupId, actor.uid))) {
      throw Exception('ليس لديك صلاحية رفض طلبات الانضمام');
    }

    await _groups
        .doc(safeGroupId)
        .collection('joinRequests')
        .doc(safeUserId)
        .delete()
        .timeout(_writeTimeout);
  }

  Future<void> deletePost({
    required String groupId,
    required String postId,
  }) async {
    final user = _currentUser;
    final safeGroupId = groupId.trim();
    final safePostId = postId.trim();

    if (safeGroupId.isEmpty) throw Exception('معرف المجموعة مطلوب');
    if (safePostId.isEmpty) throw Exception('معرف المنشور مطلوب');

    final groupSnapshot = await _groups.doc(safeGroupId).get();
    if (!groupSnapshot.exists) throw Exception('المجموعة غير موجودة');

    final groupData = groupSnapshot.data() ?? <String, dynamic>{};
    final ownerId = (groupData['ownerId'] as String? ?? '').trim();
    final moderators = _normalizeUserList(groupData['moderators']);
    final isOwner = user.uid == ownerId;
    final isModerator = moderators.contains(user.uid);

    final postRef = _groups.doc(safeGroupId).collection('posts').doc(safePostId);
    final postSnapshot = await postRef.get();
    if (!postSnapshot.exists) throw Exception('المنشور غير موجود');

    final postData = postSnapshot.data() ?? <String, dynamic>{};
    final authorId = (postData['authorId'] as String? ?? '').trim();

    if (!isOwner && !isModerator && authorId != user.uid) {
      throw Exception('ليس لديك صلاحية حذف هذا المنشور');
    }

    await postRef.delete().timeout(_writeTimeout);
  }

  Future<void> toggleLike({required String groupId, required String postId}) async {
    final user = _currentUser;
    await _groups.doc(groupId).collection('posts').doc(postId).update({
      'likes': FieldValue.arrayUnion([user.uid]),
    });
  }

  Future<void> addComment({required String groupId, required String postId, required String text}) async {
    final user = _currentUser;
    await _requireMember(groupId, user.uid);
    final postRef = _groups.doc(groupId).collection('posts').doc(postId);
    final commentRef = postRef.collection('comments').doc();
    await _firestore.runTransaction((transaction) async {
      transaction.set(commentRef, {
        'authorId': user.uid,
        'authorName': user.displayName ?? user.email ?? 'مستخدم',
        'text': text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      transaction.update(postRef, {'commentsCount': FieldValue.increment(1)});
    }).timeout(_writeTimeout);
  }

  Future<void> _requireMember(String groupId, String userId) async {
    final snapshot = await _groups.doc(groupId).get();
    if (!snapshot.exists) throw Exception('المجموعة غير موجودة');

    final data = snapshot.data() ?? <String, dynamic>{};
    final ownerId = (data['ownerId'] as String? ?? '').trim();
    final members = _normalizeUserList(data['memberIds']);
    if (ownerId == userId.trim() || members.contains(userId.trim())) {
      return;
    }

    final membershipDoc = await _groups.doc(groupId).collection('members').doc(userId.trim()).get();
    if (membershipDoc.exists) return;

    throw Exception('يجب الانضمام للمجموعة أولاً');
  }
}
