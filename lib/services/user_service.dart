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
