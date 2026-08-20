import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../models/post.dart';

class PostService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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
        if (mediaUrl.trim().isEmpty || seenUrls.contains(mediaUrl)) continue;
        seenUrls.add(mediaUrl);
        normalizedFiles.add({
          'mediaType': mediaTypeValue,
          'url': mediaUrl,
          'publicId': map['publicId'] ?? '',
          'resourceType': map['resourceType'] ?? mediaTypeValue,
        });
      }
    }

    if (normalizedFiles.isEmpty && mediaType != 'none' && mediaData.trim().isNotEmpty) {
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

  static Future<void> publishPost({
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
  }) async {
    try {
      final trimmedText = text.trim();
      final payload = buildMediaPayload(
        mediaType: mediaType,
        mediaData: mediaData,
        mediaFiles: mediaFiles,
      );
      final normalizedMediaFiles = payload['mediaFiles'] as List<dynamic>? ?? const <dynamic>[];

      if (trimmedText.isEmpty && normalizedMediaFiles.isEmpty) {
        throw Exception('لا يمكن نشر منشور فارغ بدون نص أو وسائط');
      }

      List<String> hashtags = [];
      if (trimmedText.isNotEmpty) {
        final regex = RegExp(r'#\w+');
        hashtags = regex.allMatches(trimmedText).map((m) => m.group(0)!.substring(1)).toList();
      }

      await _firestore.collection('posts').add({
        'userId': userId,
        'username': username,
        'text': text,
        'isTemporary': isTemporary,
        'location': location,
        'mediaType': payload['mediaType'],
        'mediaData': payload['mediaData'],
        'mediaFiles': payload['mediaFiles'],
        'categoryId': categoryId,
        'timestamp': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'commentsCount': 0,
        'likes': [],
        'hashtags': hashtags,
        'reactions': {},
        'isVerified': false,
        'privacy': privacy,
      });
    } catch (e) {
      throw Exception('فشل نشر المنشور: $e');
    }
  }

  static Stream<List<Post>> postsStream({String? categoryId}) {
    Query<Map<String, dynamic>> query = _firestore.collection('posts').orderBy('timestamp', descending: true);

    if (categoryId != null && categoryId.isNotEmpty && categoryId != 'all') {
      query = query.where('categoryId', isEqualTo: categoryId);
    }

    return query.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => Post.fromFirestore(doc)).toList();
    });
  }

  static Stream<Post?> postStream(String postId) {
    return _firestore.collection('posts').doc(postId).snapshots().map((snapshot) {
      if (!snapshot.exists) return null;
      return Post.fromFirestore(snapshot);
    });
  }

  static Future<void> toggleLike({required String postId, required String userId}) async {
    try {
      final docRef = _firestore.collection('posts').doc(postId);
      final docSnap = await docRef.get();
      if (docSnap.exists) {
        final List<dynamic> likes = docSnap.data()?['likes'] ?? [];
        if (likes.contains(userId)) {
          await docRef.update({'likes': FieldValue.arrayRemove([userId])});
        } else {
          await docRef.update({'likes': FieldValue.arrayUnion([userId])});
        }
      }
    } catch (e) {
      throw Exception('فشل تحديث الإعجاب: $e');
    }
  }

  static Future<void> addLike({required String postId, required String userId}) async {
    await _firestore.collection('posts').doc(postId).update({
      'likes': FieldValue.arrayUnion([userId])
    });
  }

  static Future<void> removeLike({required String postId, required String userId}) async {
    await _firestore.collection('posts').doc(postId).update({
      'likes': FieldValue.arrayRemove([userId])
    });
  }

  // 🔥 تم تسريع التفاعل هنا باستخدام الـ Dot Notation مع حماية إضافية
  static Future<void> addReaction({required String postId, required String userId, required String reactionType}) async {
    try {
      // يحاول التحديث المباشر للمستخدم المحدد (أسرع طريقة)
      await _firestore.collection('posts').doc(postId).update({
        'reactions.$userId': reactionType
      });
    } catch (e) {
      // لو الحقل الأساسي reactions مش موجود في الداتا بيز (للمنشورات القديمة)، هينشئه من الصفر
      await _firestore.collection('posts').doc(postId).set({
        'reactions': {userId: reactionType}
      }, SetOptions(merge: true));
    }
  }

  static Future<void> updateReaction({required String postId, required String userId, required String reactionType}) async {
    await addReaction(postId: postId, userId: userId, reactionType: reactionType);
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

  static Future<void> updateCommentsCount({required String postId, required int incrementBy}) async {
    try {
      final docRef = _firestore.collection('posts').doc(postId);
      await docRef.update({'commentsCount': FieldValue.increment(incrementBy)});
    } catch (e) {
      throw Exception('فشل تحديث عداد التعليقات: $e');
    }
  }

  static Future<void> addPoints(String userId, int pointsToAdd) async {
    try {
      final userQuery = await _firestore.collection('users').where('id', isEqualTo: userId).limit(1).get();
      if (userQuery.docs.isNotEmpty) {
        final docRef = userQuery.docs.first.reference;
        final currentPoints = userQuery.docs.first.data()['points'] ?? 0;
        await docRef.update({'points': currentPoints + pointsToAdd});
      }
    } catch (_) {}
  }
}
