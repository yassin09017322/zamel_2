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
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('المستخدم غير مسجل دخول');
    }

    await _ensureAdmin();

    final userDoc = await _firestore.collection('users').doc(currentUser.uid).get();
    final adminName = (userDoc.data()?['username'] as String?) ?? currentUser.email ?? 'admin';

    final ref = await _firestore.collection('channels').add({
      'name': name.trim(),
      'description': description.trim(),
      'adminId': currentUser.uid,
      'adminName': adminName,
      'imageUrl': imageUrl,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return ref.id;
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

    await _ensureAdmin();

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
          'senderName': senderName.isNotEmpty ? senderName : (currentUser.email ?? 'admin'),
          'text': text.trim(),
          'mediaUrl': mediaUrl,
          'mediaType': mediaType,
          'thumbnailUrl': thumbnailUrl,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'isDeleted': false,
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
}
