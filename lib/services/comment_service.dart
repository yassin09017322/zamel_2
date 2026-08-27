import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/comment.dart';

class CommentService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static const Duration _writeTimeout = Duration(seconds: 30);

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
    String? clientRequestId,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('يجب تسجيل الدخول لإضافة تعليق');
    }
    if (userId.trim() != currentUser.uid) {
      throw Exception('هوية صاحب التعليق غير صالحة');
    }
    if (postId.trim().isEmpty) {
      throw Exception('معرف المنشور غير صالح');
    }
    if (text.trim().isEmpty && (audioUrl ?? '').trim().isEmpty) {
      throw Exception('لا يمكن إرسال تعليق فارغ');
    }
    if ((audioUrl ?? '').trim().isNotEmpty) {
      final audioUri = Uri.tryParse(audioUrl!.trim());
      if (audioUri == null ||
          audioUri.scheme != 'https' ||
          audioUri.host.isEmpty) {
        throw Exception('رابط الصوت غير صالح');
      }
    }

    final postReference = _firestore.collection('posts').doc(postId.trim());
    final commentReference =
        clientRequestId == null || clientRequestId.trim().isEmpty
        ? postReference.collection('comments').doc()
        : postReference.collection('comments').doc(clientRequestId.trim());

    try {
      await _firestore
          .runTransaction((transaction) async {
            final postSnapshot = await transaction.get(postReference);
            if (!postSnapshot.exists) {
              throw Exception('المنشور غير موجود');
            }

            final existingComment = await transaction.get(commentReference);
            if (existingComment.exists) {
              final existingData =
                  existingComment.data() ?? <String, dynamic>{};
              if (existingData['userId'] == currentUser.uid) return;
              throw Exception('معرف طلب التعليق مستخدم مسبقًا');
            }

            transaction.set(commentReference, {
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
            transaction.update(postReference, {
              'commentsCount': FieldValue.increment(1),
            });
          })
          .timeout(_writeTimeout);
    } on FirebaseException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        Exception(
          'فشل حفظ التعليق (${error.code}): ${error.message ?? 'خطأ غير معروف'}',
        ),
        stackTrace,
      );
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        Exception('فشل حفظ التعليق: $error'),
        stackTrace,
      );
    }
  }

  Future<void> addLike({required String postId, required String userId}) async {
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
