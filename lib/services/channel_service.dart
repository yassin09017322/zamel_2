import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/channel.dart';
import '../models/channel_message.dart';

class ChannelService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> _ensureAdmin() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('المستخدم غير مسجل دخول');
    }

    final userDoc = await _firestore.collection('users').doc(currentUser.uid).get();
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
          return snapshot.docs.map((doc) => Channel.fromFirestore(doc)).toList();
        });
  }

  Stream<List<ChannelMessage>> messagesStream(String channelId, {int limit = 20}) {
    return _firestore
        .collection('channels')
        .doc(channelId)
        .collection('messages')
        .where('isDeleted', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => ChannelMessage.fromFirestore(doc, channelId))
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

    final userDoc = await _firestore.collection('users').doc(currentUser.uid).get();
    final adminName = (userDoc.data()?['username'] as String?) ?? currentUser.email ?? 'admin';

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

    final userDoc = await _firestore.collection('users').doc(currentUser.uid).get();
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
    if (isAccountsDisabled != null) payload['isAccountsDisabled'] = isAccountsDisabled;
    if (name != null && name.trim().isNotEmpty) payload['name'] = name.trim();
    if (description != null && description.trim().isNotEmpty) payload['description'] = description.trim();
    if (imageUrl != null) payload['imageUrl'] = imageUrl;
    payload['updatedAt'] = FieldValue.serverTimestamp();
    if (payload.isEmpty) return;
    await _firestore.collection('channels').doc(channelId).update(payload);
  }

  Future<void> addMember({required String channelId, required String userId}) async {
    if (userId.trim().isEmpty) return;
    final ref = _firestore.collection('channels').doc(channelId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) return;
      final data = snapshot.data() ?? {};
      final members = List<String>.from(data['memberIds'] ?? []);
      final guests = List<String>.from(data['guestIds'] ?? []);
      final moderators = List<String>.from(data['moderators'] ?? []);
      if (!members.contains(userId)) members.add(userId);
      if (guests.contains(userId)) guests.remove(userId);
      if (!moderators.contains(userId)) {
        transaction.update(ref, {
          'memberIds': members,
          'guestIds': guests,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        transaction.update(ref, {
          'memberIds': members,
          'guestIds': guests,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  Future<void> addModerator({required String channelId, required String userId}) async {
    if (userId.trim().isEmpty) return;
    final ref = _firestore.collection('channels').doc(channelId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) return;
      final data = snapshot.data() ?? {};
      final moderators = List<String>.from(data['moderators'] ?? []);
      final members = List<String>.from(data['memberIds'] ?? []);
      if (!moderators.contains(userId)) moderators.add(userId);
      if (!members.contains(userId)) members.add(userId);
      transaction.update(ref, {
        'moderators': moderators,
        'memberIds': members,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> removeMember({required String channelId, required String userId}) async {
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

  Future<void> removeModerator({required String channelId, required String userId}) async {
    if (userId.trim().isEmpty) return;
    final ref = _firestore.collection('channels').doc(channelId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) return;
      final data = snapshot.data() ?? {};
      final moderators = List<String>.from(data['moderators'] ?? []);
      moderators.removeWhere((value) => value == userId);
      transaction.update(ref, {
        'moderators': moderators,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  static String _normalizeAccessType(String accessType, bool fallbackPrivate) {
    final normalized = accessType.trim().toLowerCase();
    if (normalized == 'private') return 'private';
    if (normalized == 'guest-only' || normalized == 'guestonly' || normalized == 'guest_only') return 'guest-only';
    if (fallbackPrivate) return 'private';
    return 'public';
  }

  Future<Map<String, String>> fetchUsersDisplayNames(List<String> userIds) async {
    final distinctIds = userIds.where((id) => id.trim().isNotEmpty).toSet().toList();
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
  }) async {
    await _ensureAdmin();

    final payload = <String, dynamic>{};
    if (name != null) payload['name'] = name.trim();
    if (description != null) payload['description'] = description.trim();
    if (imageUrl != null) payload['imageUrl'] = imageUrl;
    if (isActive != null) payload['isActive'] = isActive;
    payload['updatedAt'] = FieldValue.serverTimestamp();

    await _firestore.collection('channels').doc(channelId).update(payload);
  }

  Future<void> publishMessage({
    required String channelId,
    required String senderId,
    required String senderName,
    required String text,
    String mediaUrl = '',
    String mediaType = 'text',
    String thumbnailUrl = '',
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('المستخدم غير مسجل دخول');
    }

    // تم تعطيل هذا السطر ليتمكن جميع المستخدمين من النشر داخل القنوات
    // await _ensureAdmin();

    if (text.trim().isEmpty && mediaUrl.trim().isEmpty) {
      throw Exception('لا يمكن إنشاء منشور فارغ');
    }

    await _firestore
        .collection('channels')
        .doc(channelId)
        .collection('messages')
        .add({
          'channelId': channelId,
          'senderId': currentUser.uid,
          'senderName': senderName.isNotEmpty ? senderName : (currentUser.email ?? 'مستخدم'),
          'text': text.trim(),
          'mediaUrl': mediaUrl,
          'mediaType': mediaType,
          'thumbnailUrl': thumbnailUrl,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'isDeleted': false,
          'parentMessageId': '', // تأكيد أنها رسالة أساسية وليست تعليق
        });

    await _firestore.collection('channels').doc(channelId).update({
      'updatedAt': FieldValue.serverTimestamp(),
    });
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
    await _ensureAdmin();

    await _firestore
        .collection('channels')
        .doc(channelId)
        .collection('messages')
        .doc(messageId)
        .update({
          'isDeleted': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });
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
  Stream<List<ChannelMessage>> commentsStream(String channelId, String parentMessageId) {
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

    final batch = _firestore.batch();
    
    final commentRef = _firestore.collection('channels').doc(channelId).collection('messages').doc();
    batch.set(commentRef, {
      'channelId': channelId,
      'senderId': currentUser.uid,
      'senderName': senderName.isNotEmpty ? senderName : (currentUser.email ?? 'مستخدم'),
      'text': text.trim(),
      'mediaUrl': '',
      'mediaType': 'text',
      'thumbnailUrl': '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'isDeleted': false,
      'parentMessageId': parentMessageId, 
      'reactions': {},
      'replyCount': 0,
      'extraData': {},
    });

    final parentRef = _firestore.collection('channels').doc(channelId).collection('messages').doc(parentMessageId);
    batch.update(parentRef, {
      'replyCount': FieldValue.increment(1) 
    });

    await batch.commit();
  }

  // --- دوال الرسائل المثبتة (Pinned Messages) ---
  Future<void> pinMessage({required String channelId, required String messageId}) async {
    await _ensureAdmin(); 
    await _firestore.collection('channels').doc(channelId).update({
      'pinnedMessageId': messageId,
    });
  }

  Future<void> unpinMessage({required String channelId}) async {
    await _ensureAdmin();
    await _firestore.collection('channels').doc(channelId).update({
      'pinnedMessageId': '',
    });
  }

  Future<ChannelMessage?> getMessage({required String channelId, required String messageId}) async {
    final doc = await _firestore.collection('channels').doc(channelId).collection('messages').doc(messageId).get();
    if (!doc.exists) return null;
    return ChannelMessage.fromFirestore(doc, channelId);
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

    final pollOptions = options.asMap().entries.map((e) => {
      'id': e.key.toString(),
      'text': e.value.trim(),
      'votes': <String>[], 
    }).toList();

    await _firestore.collection('channels').doc(channelId).collection('messages').add({
      'channelId': channelId,
      'senderId': currentUser.uid,
      'senderName': senderName.isNotEmpty ? senderName : (currentUser.email ?? 'مستخدم'),
      'text': '📊 استطلاع رأي: $question',
      'mediaUrl': '',
      'mediaType': 'text',
      'thumbnailUrl': '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'isDeleted': false,
      'parentMessageId': '',
      'reactions': {},
      'replyCount': 0,
      'extraData': {
        'isPoll': true,
        'pollQuestion': question,
        'pollOptions': pollOptions,
      },
    });

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
    final docRef = _firestore.collection('channels').doc(channelId).collection('messages').doc(messageId);
    
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
