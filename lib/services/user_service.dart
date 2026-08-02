import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import 'notification_service.dart';

class UserService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<AppUser>> usersStream({String query = ''}) {
    final stream = _firestore.collection('users').snapshots();
    if (query.isEmpty) {
      return stream.map((snapshot) {
        return snapshot.docs.map((doc) => AppUser.fromFirestore(doc.data(), doc.id)).toList();
      });
    }
    final lowerQuery = query.toLowerCase();
    return stream.map((snapshot) {
      return snapshot.docs
          .map((doc) => AppUser.fromFirestore(doc.data(), doc.id))
          .where((user) {
            return user.username.toLowerCase().contains(lowerQuery) || user.email.toLowerCase().contains(lowerQuery);
          })
          .toList();
    });
  }

  Stream<List<AppUser>> searchUsers(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return Stream.value(<AppUser>[]);
    }

    final startAt = normalized;
    final endAt = '$normalized\uf8ff';
    final queryRef = _firestore.collection('users').orderBy('username').startAt([startAt]).endAt([endAt]);

    return queryRef.snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => AppUser.fromFirestore(doc.data(), doc.id))
          .where((user) => user.username.toLowerCase().contains(normalized))
          .toList();
    });
  }

  Future<List<AppUser>> usersByIds(List<String> ids) async {
    if (ids.isEmpty) {
      return <AppUser>[];
    }

    final results = <AppUser>[];
    for (var offset = 0; offset < ids.length; offset += 10) {
      final chunk = ids.sublist(offset, offset + 10 > ids.length ? ids.length : offset + 10);
      final snapshot = await _firestore.collection('users').where(FieldPath.documentId, whereIn: chunk).get();
      results.addAll(snapshot.docs.map((doc) => AppUser.fromFirestore(doc.data(), doc.id)));
    }

    final idOrder = {for (var i = 0; i < ids.length; i++) ids[i]: i};
    results.sort((a, b) => (idOrder[a.id] ?? 0).compareTo(idOrder[b.id] ?? 0));
    return results;
  }

  Stream<AppUser?> userStream(String userId) {
    return _firestore.collection('users').doc(userId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return AppUser.fromFirestore(doc.data(), doc.id);
    });
  }

  Future<void> followUser({
    required String currentUserId,
    required String targetUserId,
    required String currentUsername,
  }) async {
    if (currentUserId == targetUserId) return;
    final batch = _firestore.batch();
    final currentRef = _firestore.collection('users').doc(currentUserId);
    final targetRef = _firestore.collection('users').doc(targetUserId);
    batch.update(currentRef, {
      'following': FieldValue.arrayUnion([targetUserId]),
      'followingCount': FieldValue.increment(1),
    });
    batch.update(targetRef, {
      'followers': FieldValue.arrayUnion([currentUserId]),
      'followersCount': FieldValue.increment(1),
    });
    await batch.commit();

    await NotificationService().createNotification(
      senderId: currentUserId,
      receiverId: targetUserId,
      type: 'follow',
      referenceId: currentUserId,
    );
  }

  Future<void> unfollowUser({
    required String currentUserId,
    required String targetUserId,
  }) async {
    if (currentUserId == targetUserId) return;
    final batch = _firestore.batch();
    final currentRef = _firestore.collection('users').doc(currentUserId);
    final targetRef = _firestore.collection('users').doc(targetUserId);
    batch.update(currentRef, {
      'following': FieldValue.arrayRemove([targetUserId]),
      'followingCount': FieldValue.increment(-1),
    });
    batch.update(targetRef, {
      'followers': FieldValue.arrayRemove([currentUserId]),
      'followersCount': FieldValue.increment(-1),
    });
    await batch.commit();
  }
}
