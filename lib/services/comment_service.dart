import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/comment.dart';
import 'notification_service.dart';

class CommentPage {
  final List<Comment> comments;
  final DocumentSnapshot<Map<String, dynamic>>? cursor;
  final bool hasMore;

  const CommentPage({
    required this.comments,
    required this.cursor,
    required this.hasMore,
  });
}

class CommentService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static const int pageSize = 20;
  static const Duration _writeTimeout = Duration(seconds: 30);

  CollectionReference<Map<String, dynamic>> _comments(String postId) =>
      _firestore.collection('posts').doc(postId.trim()).collection('comments');

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
    String? rootCommentId,
    String? userPhotoUrl,
  }) {
    return {
      'postId': postId.trim(),
      'userId': userId.trim(),
      'username': username.trim().isNotEmpty ? username.trim() : 'مستخدم',
      'userPhotoUrl': userPhotoUrl ?? '',
      'text': text.trim(),
      'audioUrl': (audioUrl ?? '').trim(),
      'publicId': publicId ?? '',
      'type': type ?? 'text',
      'duration': duration ?? 0,
      'mediaIndex': mediaIndex,
      'replyToCommentId': replyToCommentId ?? '',
      'replyToUserId': replyToUserId ?? '',
      'replyToUsername': replyToUsername ?? '',
      'rootCommentId': rootCommentId ?? '',
      'likesCount': 0,
      'repliesCount': 0,
      'isEdited': false,
      'isDeleted': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'timestamp': FieldValue.serverTimestamp(),
    };
  }

  Query<Map<String, dynamic>> _orderedQuery(
    String postId, {
    String? parentCommentId,
    DocumentSnapshot<Map<String, dynamic>>? cursor,
  }) {
    var query = _comments(postId)
        .where('replyToCommentId', isEqualTo: parentCommentId ?? '')
        .orderBy('createdAt', descending: true)
        .limit(pageSize);
    if (cursor != null) query = query.startAfterDocument(cursor);
    return query;
  }

  Future<CommentPage> fetchPage(
    String postId, {
    String? parentCommentId,
    DocumentSnapshot<Map<String, dynamic>>? cursor,
  }) async {
    if (postId.trim().isEmpty) {
      return const CommentPage(comments: [], cursor: null, hasMore: false);
    }
    final snapshot = await _orderedQuery(
      postId,
      parentCommentId: parentCommentId,
      cursor: cursor,
    ).get().timeout(_writeTimeout);
    final comments = snapshot.docs
        .map(Comment.fromFirestore)
        .where((comment) => !comment.isDeleted || comment.repliesCount > 0)
        .toList();
    return CommentPage(
      comments: comments,
      cursor: snapshot.docs.isEmpty ? cursor : snapshot.docs.last,
      hasMore: snapshot.docs.length == pageSize,
    );
  }

  Stream<List<Comment>> commentsStream(String postId, {int? mediaIndex}) {
    var query = _comments(postId)
        .where('replyToCommentId', isEqualTo: '')
        .orderBy('createdAt', descending: true)
        .limit(pageSize);
    if (mediaIndex != null) {
      query = query.where('mediaIndex', isEqualTo: mediaIndex);
    }
    return query.snapshots().map(
      (snapshot) => snapshot.docs
          .map(Comment.fromFirestore)
          .where((comment) => !comment.isDeleted || comment.repliesCount > 0)
          .toList(),
    );
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
    String? userPhotoUrl,
  }) async {
    final currentUser = _auth.currentUser;
    final authenticatedUserId = currentUser?.uid ?? '';
    if (authenticatedUserId.isEmpty) {
      throw Exception('يجب تسجيل الدخول لإرسال تعليق');
    }
    if (userId.trim().isNotEmpty && userId.trim() != authenticatedUserId) {
      throw Exception('هوية صاحب التعليق غير صالحة');
    }
    final normalizedPostId = postId.trim();
    final normalizedText = text.trim();
    final normalizedAudioUrl = (audioUrl ?? '').trim();
    if (normalizedPostId.isEmpty) throw Exception('معرف المنشور غير صالح');
    if (normalizedText.isEmpty && normalizedAudioUrl.isEmpty) {
      throw Exception('لا يمكن إرسال تعليق فارغ');
    }
    if (normalizedAudioUrl.isNotEmpty) {
      final uri = Uri.tryParse(normalizedAudioUrl);
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
        throw Exception('رابط الوسائط غير صالح');
      }
    }

    final postRef = _firestore.collection('posts').doc(normalizedPostId);
    final parentId = (replyToCommentId ?? '').trim();
    final commentRef = clientRequestId?.trim().isNotEmpty == true
        ? _comments(normalizedPostId).doc(clientRequestId!.trim())
        : _comments(normalizedPostId).doc();
    String ownerId = '';
    String? notificationType;
    String? notificationReference;

    try {
      await _firestore
          .runTransaction((transaction) async {
            final postSnapshot = await transaction.get(postRef);
            if (!postSnapshot.exists) throw Exception('المنشور غير موجود');
            final postData = postSnapshot.data() ?? <String, dynamic>{};
            ownerId = postData['userId'] as String? ?? '';

            DocumentSnapshot<Map<String, dynamic>>? parentSnapshot;
            if (parentId.isNotEmpty) {
              parentSnapshot = await transaction.get(
                _comments(normalizedPostId).doc(parentId),
              );
              if (!parentSnapshot.exists)
                throw Exception('التعليق الأب غير موجود');
              notificationType = 'reply';
              notificationReference = parentId;
            } else {
              notificationType = 'comment';
              notificationReference = commentRef.id;
            }

            final existing = await transaction.get(commentRef);
            if (existing.exists) {
              final existingUserId =
                  existing.data()?['userId'] as String? ?? '';
              if (existingUserId == authenticatedUserId) return;
              throw Exception('معرف طلب التعليق مستخدم مسبقًا');
            }

            final rootId = parentId.isEmpty
                ? commentRef.id
                : (parentSnapshot?.data()?['rootCommentId'] as String? ??
                      parentId);
            transaction.set(
              commentRef,
              buildCommentPayload(
                postId: normalizedPostId,
                userId: authenticatedUserId,
                username: username,
                userPhotoUrl: userPhotoUrl,
                text: normalizedText,
                audioUrl: normalizedAudioUrl,
                publicId: publicId,
                type: type,
                duration: duration,
                mediaIndex: mediaIndex,
                replyToCommentId: parentId,
                replyToUserId: replyToUserId,
                replyToUsername: replyToUsername,
                rootCommentId: rootId,
              ),
            );
            transaction.update(postRef, {
              'commentsCount': FieldValue.increment(1),
            });
            if (parentId.isNotEmpty) {
              transaction.update(_comments(normalizedPostId).doc(parentId), {
                'repliesCount': FieldValue.increment(1),
              });
            }
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

    final receiverId = parentId.isNotEmpty ? (replyToUserId ?? '') : ownerId;
    if (receiverId.isNotEmpty && receiverId != authenticatedUserId) {
      try {
        await NotificationService().createNotification(
          senderId: authenticatedUserId,
          receiverId: receiverId,
          type: notificationType ?? 'comment',
          referenceId: normalizedPostId,
          postId: normalizedPostId,
          commentId: notificationReference ?? commentRef.id,
          parentCommentId: parentId,
          actorName: username,
          title: username,
          body: parentId.isNotEmpty ? 'رد على تعليقك' : 'علّق على منشورك',
          actorUserId: authenticatedUserId,
          notificationKey: 'post_comment:${commentRef.id}:$receiverId',
        );
      } catch (error) {
        debugPrint('Comment notification failed: $error');
      }
    }
  }

  Future<void> updateComment({
    required String postId,
    required String commentId,
    required String text,
  }) async {
    final uid = _auth.currentUser?.uid ?? '';
    final normalizedText = text.trim();
    if (uid.isEmpty) throw Exception('يجب تسجيل الدخول لتعديل التعليق');
    if (normalizedText.isEmpty) throw Exception('لا يمكن حفظ تعليق فارغ');
    final ref = _comments(postId).doc(commentId);
    final snapshot = await ref.get();
    if (!snapshot.exists || snapshot.data()?['userId'] != uid) {
      throw Exception('لا تملك صلاحية تعديل هذا التعليق');
    }
    await ref
        .update({
          'text': normalizedText,
          'updatedAt': FieldValue.serverTimestamp(),
          'isEdited': true,
        })
        .timeout(_writeTimeout);
  }

  Future<void> deleteComment({
    required String postId,
    required String commentId,
  }) async {
    final uid = _auth.currentUser?.uid ?? '';
    if (uid.isEmpty) throw Exception('يجب تسجيل الدخول لحذف التعليق');
    final postRef = _firestore.collection('posts').doc(postId);
    final ref = _comments(postId).doc(commentId);
    await _firestore
        .runTransaction((transaction) async {
          final commentSnapshot = await transaction.get(ref);
          if (!commentSnapshot.exists ||
              commentSnapshot.data()?['userId'] != uid) {
            throw Exception('لا تملك صلاحية حذف هذا التعليق');
          }
          final data = commentSnapshot.data() ?? <String, dynamic>{};
          if (data['isDeleted'] == true) return;
          final parentId = data['replyToCommentId'] as String? ?? '';
          final postSnapshot = await transaction.get(postRef);
          final currentPostCount =
              (postSnapshot.data()?['commentsCount'] as num?)?.toInt() ?? 0;
          final currentReplyCount = parentId.isEmpty
              ? 0
              : ((await transaction.get(
                              _comments(postId).doc(parentId),
                            )).data()?['repliesCount']
                            as num?)
                        ?.toInt() ??
                    0;
          transaction.update(ref, {
            'isDeleted': true,
            'text': '',
            'audioUrl': '',
            'updatedAt': FieldValue.serverTimestamp(),
          });
          transaction.update(postRef, {
            'commentsCount': currentPostCount > 0 ? currentPostCount - 1 : 0,
          });
          if (parentId.isNotEmpty) {
            transaction.update(_comments(postId).doc(parentId), {
              'repliesCount': currentReplyCount > 0 ? currentReplyCount - 1 : 0,
            });
          }
        })
        .timeout(_writeTimeout);
  }

  Future<void> toggleLike({
    required String postId,
    required String commentId,
  }) async {
    final uid = _auth.currentUser?.uid ?? '';
    if (uid.isEmpty) throw Exception('يجب تسجيل الدخول للإعجاب');
    final commentRef = _comments(postId).doc(commentId);
    final likeRef = commentRef.collection('likes').doc(uid);
    await _firestore
        .runTransaction((transaction) async {
          final commentSnapshot = await transaction.get(commentRef);
          if (!commentSnapshot.exists) throw Exception('التعليق غير موجود');
          final likeSnapshot = await transaction.get(likeRef);
          final currentCount =
              (commentSnapshot.data()?['likesCount'] as num?)?.toInt() ?? 0;
          if (likeSnapshot.exists) {
            transaction.delete(likeRef);
            transaction.update(commentRef, {
              'likesCount': currentCount > 0 ? FieldValue.increment(-1) : 0,
            });
          } else {
            transaction.set(likeRef, {
              'userId': uid,
              'createdAt': FieldValue.serverTimestamp(),
            });
            transaction.update(commentRef, {
              'likesCount': FieldValue.increment(1),
            });
          }
        })
        .timeout(_writeTimeout);
  }

  Future<bool> isLiked({
    required String postId,
    required String commentId,
  }) async {
    final uid = _auth.currentUser?.uid ?? '';
    if (uid.isEmpty) return false;
    final snapshot = await _comments(
      postId,
    ).doc(commentId).collection('likes').doc(uid).get();
    return snapshot.exists;
  }
}
