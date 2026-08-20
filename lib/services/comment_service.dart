import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/comment.dart';

class CommentService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<Comment>> commentsStream(String postId, {int? mediaIndex}) {
    Query<Map<String, dynamic>> query = _firestore
        .collection('posts')
        .doc(postId)
        .collection('comments');

    if (mediaIndex != null) {
      query = query.where('mediaIndex', isEqualTo: mediaIndex);
    }

    query = query.orderBy('timestamp', descending: true);

    return query.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => Comment.fromFirestore(doc)).toList();
    });
  }

  Future<void> addComment({
    required String postId,
    required String userId,
    required String username,
    required String text,
    String? audioUrl,
    String? publicId,
    String? type,
    int? duration,
    int mediaIndex = 0,
    String? replyToCommentId,
    String? replyToUserId,
    String? replyToUsername,
  }) async {
    try {
      await _firestore.collection('posts').doc(postId).collection('comments').add({
        'userId': userId,
        'username': username,
        'text': text,
        // 🔥 السر هنا: حماية فايربيس من الـ null عشان التعليقات ماتختفيش
        'audioUrl': audioUrl ?? '',
        'publicId': publicId ?? '',
        'type': type ?? 'text',
        'duration': duration ?? 0,
        'mediaIndex': mediaIndex,
        'replyToCommentId': replyToCommentId ?? '',
        'replyToUserId': replyToUserId ?? '',
        'replyToUsername': replyToUsername ?? '',
        'timestamp': FieldValue.serverTimestamp(),
      });
      
      await _firestore.collection('posts').doc(postId).update({
        'commentsCount': FieldValue.increment(1),
      });
    } catch (e) {
      throw Exception('فشل رفع التعليق: $e');
    }
  }

  Future<void> addLike({
    required String postId,
    required String userId,
  }) async {
    final postRef = _firestore.collection('posts').doc(postId);
    await postRef.update({
      'likes': FieldValue.arrayUnion([userId]),
    });
  }

  Future<void> removeLike({
    required String postId,
    required String userId,
  }) async {
    final postRef = _firestore.collection('posts').doc(postId);
    await postRef.update({
      'likes': FieldValue.arrayRemove([userId]),
    });
  }
}
