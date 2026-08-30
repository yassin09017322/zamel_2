import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/comment.dart';

class CommentService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static const Duration _writeTimeout = Duration(seconds: 30);

  static Map<String, dynamic> buildCommentPayload({
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
  }) {
    final resolvedUserId = userId.trim().isNotEmpty ? userId.trim() : '';
    final resolvedUsername = username.trim().isNotEmpty ? username.trim() : 'مستخدم';
    final normalizedText = text.trim();
    final normalizedAudioUrl = (audioUrl ?? '').trim();

    return {
      'postId': postId.trim(),
      'userId': resolvedUserId,
      'username': resolvedUsername,
      'text': normalizedText,
      'audioUrl': normalizedAudioUrl,
      'publicId': publicId ?? '',
      'type': type ?? 'text',
      'duration': duration ?? 0,
      'mediaIndex': mediaIndex,
      'replyToCommentId': replyToCommentId ?? '',
      'replyToUserId': replyToUserId ?? '',
      'replyToUsername': replyToUsername ?? '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'timestamp': FieldValue.serverTimestamp(),
    };
  }

  Stream<List<Comment>> commentsStream(String postId, {int? mediaIndex}) {
    Query<Map<String, dynamic>> query = _firestore
        .collection('posts')
        .doc(postId)
        .collection('comments');

    if (mediaIndex != null) {
      query = query.where('mediaIndex', isEqualTo: mediaIndex);
    }

    return query.snapshots().map((snapshot) {
      final comments = snapshot.docs
          .map((doc) => Comment.fromFirestore(doc))
          .toList();
      comments.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return comments;
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
    final authenticatedUserId = currentUser?.uid ?? '';
    final requestedUserId = userId.trim();
    if (authenticatedUserId.isEmpty) {
      throw Exception('يجب تسجيل الدخول لإرسال تعليق');
    }
    if (requestedUserId.isNotEmpty && requestedUserId != authenticatedUserId) {
      throw Exception('هوية صاحب التعليق غير صالحة');
    }
    final effectiveUserId = authenticatedUserId;
    final effectiveUsername = username.trim().isNotEmpty
        ? username.trim()
        : (currentUser?.displayName ?? currentUser?.email ?? 'مستخدم');

    if (postId.trim().isEmpty) {
      throw Exception('معرف المنشور غير صالح');
    }
    if (effectiveUserId.isEmpty) {
      throw Exception('هوية صاحب التعليق غير صالحة');
    }

    final normalizedText = text.trim();
    final normalizedAudioUrl = (audioUrl ?? '').trim();

    if (normalizedText.isEmpty && normalizedAudioUrl.isEmpty) {
      throw Exception('لا يمكن إرسال تعليق فارغ');
    }
    if (normalizedAudioUrl.isNotEmpty) {
      final audioUri = Uri.tryParse(normalizedAudioUrl);
      if (audioUri == null ||
          audioUri.scheme != 'https' ||
          audioUri.host.isEmpty) {
        throw Exception('رابط الصوت غير صالح');
      }
    }

    final postReference = _firestore.collection('posts').doc(postId.trim());
    final parentCommentId = (replyToCommentId ?? '').trim();
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

            if (parentCommentId.isNotEmpty) {
              final parentSnapshot = await transaction.get(
                postReference.collection('comments').doc(parentCommentId),
              );
              if (!parentSnapshot.exists) {
                throw Exception('التعليق الأب غير موجود');
              }
            }

            final existingComment = await transaction.get(commentReference);
            if (existingComment.exists) {
              final existingData =
                  existingComment.data() ?? <String, dynamic>{};
              if (existingData['userId'] == effectiveUserId) {
                return;
              }
              throw Exception('معرف طلب التعليق مستخدم مسبقًا');
            }

            transaction.set(
              commentReference,
              buildCommentPayload(
                postId: postId,
                userId: effectiveUserId,
                username: effectiveUsername,
                text: text,
                audioUrl: normalizedAudioUrl,
                publicId: publicId,
                type: type,
                duration: duration,
                mediaIndex: mediaIndex,
                replyToCommentId: replyToCommentId,
                replyToUserId: replyToUserId,
                replyToUsername: replyToUsername,
              ),
            );
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
