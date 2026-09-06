import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../models/post.dart';
import '../services/category_service.dart';
import '../providers/settings_provider.dart';
import 'notification_service.dart';

class PostInteractionState {
  final bool isSaved;
  final bool isHidden;
  final bool notificationsEnabled;
  final bool seesFewerSimilarPosts;

  const PostInteractionState({
    this.isSaved = false,
    this.isHidden = false,
    this.notificationsEnabled = false,
    this.seesFewerSimilarPosts = false,
  });
}

class PostService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const Duration _publishTimeout = Duration(seconds: 45);

  static Map<String, dynamic> buildMediaPayload({
    required String mediaType,
    required String mediaData,
    List<Map<String, dynamic>>? mediaFiles,
  }) {
    final normalizedFiles = <Map<String, dynamic>>[];
    final seenUrls = <String>{};

    if (mediaFiles != null) {
      for (final item in mediaFiles) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final mediaTypeValue = (map['mediaType'] ?? 'image').toString();
        final mediaUrl = (map['url'] ?? '').toString();
        if (mediaUrl.trim().isEmpty) {
          throw Exception('الوسائط تحتوي على URL فارغ');
        }
        final uri = Uri.tryParse(mediaUrl.trim());
        if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
          throw Exception('الوسائط تحتوي على URL غير صالح');
        }
        if (seenUrls.contains(mediaUrl)) continue;
        seenUrls.add(mediaUrl);
        normalizedFiles.add({
          'mediaType': mediaTypeValue,
          'url': mediaUrl,
          'publicId': map['publicId'] ?? '',
          'resourceType': map['resourceType'] ?? mediaTypeValue,
        });
      }
    }

    if (normalizedFiles.isEmpty &&
        mediaType != 'none' &&
        mediaData.trim().isNotEmpty) {
      final uri = Uri.tryParse(mediaData.trim());
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
        throw Exception('الوسائط تحتوي على URL غير صالح');
      }
      normalizedFiles.add({
        'mediaType': mediaType,
        'url': mediaData,
        'publicId': '',
        'resourceType': mediaType == 'video' ? 'video' : 'image',
      });
    }

    final primaryType = normalizedFiles.isNotEmpty
        ? (normalizedFiles.first['mediaType'] ?? mediaType).toString()
        : (mediaType == 'none' ? 'none' : mediaType);
    final primaryData = normalizedFiles.isNotEmpty
        ? (normalizedFiles.first['url'] ?? mediaData).toString()
        : mediaData;

    return {
      'mediaType': primaryType,
      'mediaData': primaryData,
      'mediaFiles': normalizedFiles,
    };
  }

  static Future<String> publishPost({
    required String userId,
    required String username,
    required String text,
    required bool isTemporary,
    required String location,
    required String mediaType,
    required String mediaData,
    required String categoryId,
    List<Map<String, dynamic>>? mediaFiles,
    String privacy = 'public',
    String? clientRequestId,
  }) async {
    try {
      final trimmedText = text.trim();
      final normalizedCategoryId = categoryId.trim();
      if (normalizedCategoryId.isEmpty) {
        throw Exception('لا يمكن نشر منشور بدون تصنيف صالح');
      }
      final payload = buildMediaPayload(
        mediaType: mediaType,
        mediaData: mediaData,
        mediaFiles: mediaFiles,
      );
      final normalizedMediaFiles =
          payload['mediaFiles'] as List<dynamic>? ?? const <dynamic>[];

      if (trimmedText.isEmpty && normalizedMediaFiles.isEmpty) {
        throw Exception('لا يمكن نشر منشور فارغ بدون نص أو وسائط');
      }

      List<String> hashtags = [];
      if (trimmedText.isNotEmpty) {
        final regex = RegExp(r'#\w+');
        hashtags = regex
            .allMatches(trimmedText)
            .map((m) => m.group(0)!.substring(1))
            .toList();
      }

      final postDocument =
          clientRequestId == null || clientRequestId.trim().isEmpty
          ? _firestore.collection('posts').doc()
          : _firestore.collection('posts').doc(clientRequestId);
      await postDocument
          .set({
            'userId': userId,
            'username': username,
            'text': text,
            'isTemporary': isTemporary,
            'location': location,
            'mediaType': payload['mediaType'],
            'mediaData': payload['mediaData'],
            'mediaFiles': payload['mediaFiles'],
            'categoryId': normalizedCategoryId,
            'timestamp': FieldValue.serverTimestamp(),
            'createdAt': FieldValue.serverTimestamp(),
            'commentsCount': 0,
            'likes': [],
            'hashtags': hashtags,
            'reactions': {},
            'isVerified': false,
            'privacy': privacy,
          })
          .timeout(_publishTimeout);
          return postDocument.id;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        Exception('فشل نشر المنشور: $error'),
        stackTrace,
      );
    }
  }

  static Stream<List<Post>> postsStream({String? categoryId}) async* {
    Query<Map<String, dynamic>> query = _firestore
        .collection('posts')
        .orderBy('timestamp', descending: true);

    final normalizedCategoryId = categoryId?.trim();
    if (normalizedCategoryId != null &&
        normalizedCategoryId.isNotEmpty &&
        normalizedCategoryId != 'all') {
      final categories = await CategoryService.fetchCategories();
      final resolvedCategoryId = SettingsProvider.resolveCategoryIdForFeedMode(
        normalizedCategoryId,
        categories.map((category) => category.id),
      );
      if (resolvedCategoryId == null || resolvedCategoryId.trim().isEmpty) {
        yield const <Post>[];
        return;
      }
      query = query.where('categoryId', isEqualTo: resolvedCategoryId);
    }

    yield* query.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => Post.fromFirestore(doc)).toList();
    });
  }

  static Stream<Post?> postStream(String postId) {
    return _firestore.collection('posts').doc(postId).snapshots().map((
      snapshot,
    ) {
      if (!snapshot.exists) return null;
      return Post.fromFirestore(snapshot);
    });
  }

  static Future<PostInteractionState> getInteractionState({
    required String userId,
    required Post post,
  }) async {
    final snapshot = await _firestore.collection('users').doc(userId).get();
    final data = snapshot.data();
    if (data == null) return const PostInteractionState();

    final savedPostIds = _stringList(data['savedPostIds']);
    final hiddenPostIds = _stringList(data['hiddenPostIds']);
    final notificationPostIds = _stringList(data['postNotificationIds']);
    final reducedCategoryIds = _stringList(data['reducedPostCategoryIds']);
    return PostInteractionState(
      isSaved: savedPostIds.contains(post.id),
      isHidden: hiddenPostIds.contains(post.id),
      notificationsEnabled: notificationPostIds.contains(post.id),
      seesFewerSimilarPosts:
          post.categoryId != null &&
          reducedCategoryIds.contains(post.categoryId),
    );
  }

  static Future<void> setSavedPost({
    required String userId,
    required String postId,
    required bool saved,
  }) async {
    await _setUserPostListValue(
      userId: userId,
      field: 'savedPostIds',
      value: postId,
      enabled: saved,
    );
  }

  static Future<void> setHiddenPost({
    required String userId,
    required String postId,
    required bool hidden,
  }) async {
    await _setUserPostListValue(
      userId: userId,
      field: 'hiddenPostIds',
      value: postId,
      enabled: hidden,
    );
  }

  static Future<void> setPostNotifications({
    required String userId,
    required String postId,
    required bool enabled,
  }) async {
    await _setUserPostListValue(
      userId: userId,
      field: 'postNotificationIds',
      value: postId,
      enabled: enabled,
    );
  }

  static Future<void> setFewerSimilarPosts({
    required String userId,
    required String categoryId,
    required bool enabled,
  }) async {
    final normalizedCategoryId = categoryId.trim();
    if (normalizedCategoryId.isEmpty) {
      throw ArgumentError.value(categoryId, 'categoryId', 'must not be empty');
    }
    await _setUserPostListValue(
      userId: userId,
      field: 'reducedPostCategoryIds',
      value: normalizedCategoryId,
      enabled: enabled,
    );
  }

  static Future<void> updatePostPrivacy({
    required String postId,
    required String privacy,
  }) async {
    const supportedPrivacy = {'public', 'friends', 'private'};
    if (!supportedPrivacy.contains(privacy)) {
      throw ArgumentError.value(privacy, 'privacy', 'is not supported');
    }
    await _firestore.collection('posts').doc(postId).update({
      'privacy': privacy,
    });
  }

  static Future<void> updatePostText({
    required String postId,
    required String text,
  }) async {
    final normalizedPostId = postId.trim();
    final normalizedText = text.trim();
    if (normalizedPostId.isEmpty || normalizedText.isEmpty) {
      throw ArgumentError('postId and text must not be empty');
    }
    await _firestore.collection('posts').doc(normalizedPostId).update({
      'text': normalizedText,
    });
  }

  static Future<void> _setUserPostListValue({
    required String userId,
    required String field,
    required String value,
    required bool enabled,
  }) async {
    final normalizedUserId = userId.trim();
    final normalizedValue = value.trim();
    if (normalizedUserId.isEmpty || normalizedValue.isEmpty) {
      throw ArgumentError('userId and value must not be empty');
    }
    await _firestore.collection('users').doc(normalizedUserId).set(
      <String, Object?>{
        field: enabled
            ? FieldValue.arrayUnion([normalizedValue])
            : FieldValue.arrayRemove([normalizedValue]),
      },
      SetOptions(merge: true),
    );
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) return const <String>[];
    return value
        .whereType<String>()
        .where((item) => item.trim().isNotEmpty)
        .toList();
  }

  static Future<void> toggleLike({
    required String postId,
    required String userId,
  }) async {
    try {
      final docRef = _firestore.collection('posts').doc(postId);
      final docSnap = await docRef.get();
      if (docSnap.exists) {
        final List<dynamic> likes = docSnap.data()?['likes'] ?? [];
        if (likes.contains(userId)) {
          await docRef.update({
            'likes': FieldValue.arrayRemove([userId]),
          });
        } else {
          await docRef.update({
            'likes': FieldValue.arrayUnion([userId]),
          });
          await _notifyPostOwner(
            postId: postId,
            postData: docSnap.data() ?? const <String, dynamic>{},
            actorId: userId,
          );
        }
      }
    } catch (e) {
      throw Exception('فشل تحديث الإعجاب: $e');
    }
  }

  static Future<void> addLike({
    required String postId,
    required String userId,
  }) async {
    final postRef = _firestore.collection('posts').doc(postId);
    final snapshot = await postRef.get();
    await postRef.update({
      'likes': FieldValue.arrayUnion([userId]),
    });
    await _notifyPostOwner(
      postId: postId,
      postData: snapshot.data() ?? const <String, dynamic>{},
      actorId: userId,
    );
  }

  static Future<void> removeLike({
    required String postId,
    required String userId,
  }) async {
    await _firestore.collection('posts').doc(postId).update({
      'likes': FieldValue.arrayRemove([userId]),
    });
  }

  static Future<void> _notifyPostOwner({
    required String postId,
    required Map<String, dynamic> postData,
    required String actorId,
  }) async {
    final ownerId = (postData['userId'] as String? ?? '').trim();
    if (ownerId.isEmpty || ownerId == actorId.trim()) return;
    try {
      final actor = await _firestore.collection('users').doc(actorId).get();
      final actorName = actor.data()?['username'] as String? ?? 'مستخدم';
      await NotificationService().createNotification(
        senderId: actorId,
        receiverId: ownerId,
        type: 'like',
        referenceId: postId,
        postId: postId,
        actorName: actorName,
        title: actorName,
        body: 'أعجب بمنشورك',
        notificationKey: 'post_like:$postId:$actorId',
      );
    } catch (error) {
      debugPrint('Post like notification failed: $error');
    }
  }

  // 🔥 تم تسريع التفاعل هنا باستخدام الـ Dot Notation مع حماية إضافية
  static Future<void> addReaction({
    required String postId,
    required String userId,
    required String reactionType,
  }) async {
    try {
      // يحاول التحديث المباشر للمستخدم المحدد (أسرع طريقة)
      await _firestore.collection('posts').doc(postId).update({
        'reactions.$userId': reactionType,
      });
    } catch (e) {
      // لو الحقل الأساسي reactions مش موجود في الداتا بيز (للمنشورات القديمة)، هينشئه من الصفر
      await _firestore.collection('posts').doc(postId).set({
        'reactions': {userId: reactionType},
      }, SetOptions(merge: true));
    }
  }

  static Future<void> updateReaction({
    required String postId,
    required String userId,
    required String reactionType,
  }) async {
    await addReaction(
      postId: postId,
      userId: userId,
      reactionType: reactionType,
    );
  }

  static Future<void> deletePost({required String postId}) async {
    try {
      final docRef = _firestore.collection('posts').doc(postId);
      final snapshot = await docRef.get();
      if (!snapshot.exists) {
        return;
      }

      await docRef.delete();
    } catch (e) {
      throw Exception('فشل حذف المنشور: $e');
    }
  }

  static Future<void> updateCommentsCount({
    required String postId,
    required int incrementBy,
  }) async {
    try {
      final docRef = _firestore.collection('posts').doc(postId);
      await docRef.update({'commentsCount': FieldValue.increment(incrementBy)});
    } catch (e) {
      throw Exception('فشل تحديث عداد التعليقات: $e');
    }
  }

  static Future<void> addPoints(String userId, int pointsToAdd) async {
    try {
      final userQuery = await _firestore
          .collection('users')
          .where('id', isEqualTo: userId)
          .limit(1)
          .get();
      if (userQuery.docs.isNotEmpty) {
        final docRef = userQuery.docs.first.reference;
        final currentPoints = userQuery.docs.first.data()['points'] ?? 0;
        await docRef.update({'points': currentPoints + pointsToAdd});
      }
    } catch (_) {}
  }
}
