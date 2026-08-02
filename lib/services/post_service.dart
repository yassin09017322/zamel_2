import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../models/post.dart';

class PostService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Future<void> publishPost({
    required String userId,
    required String username,
    required String text,
    required bool isTemporary,
    required String location,
    required String mediaType,
    required String mediaData,
    String privacy = 'public',
    String? publicId,
    String resourceType = 'auto',
  }) async {
    try {
      List<String> hashtags = [];
      if (text.isNotEmpty) {
        final regex = RegExp(r'#\w+');
        hashtags = regex.allMatches(text).map((m) => m.group(0)!.substring(1)).toList();
      }

      final mediaFiles = <Map<String, dynamic>>[];
      if (mediaType != 'none' && mediaData.isNotEmpty) {
        mediaFiles.add({
          'mediaType': mediaType,
          'url': mediaData,
          'publicId': publicId ?? '',
          'resourceType': resourceType,
        });
      }

      await _firestore.collection('posts').add({
        'userId': userId,
        'username': username,
        'text': text,
        'isTemporary': isTemporary,
        'location': location,
        'mediaType': mediaType,
        'mediaData': mediaData,
        'publicId': publicId ?? '',
        'mediaFiles': mediaFiles,
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

  static Stream<List<Post>> postsStream() {
    return _firestore
        .collection('posts')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => Post.fromFirestore(doc)).toList());
  }

  static Stream<Post?> postStream(String postId) {
    return _firestore.collection('posts').doc(postId).snapshots().map((snapshot) {
      if (!snapshot.exists) return null;
      return Post.fromFirestore(snapshot);
    });
  }

  // تم تصحيح كل الدوال هنا لتستقبل المتغيرات بأسماءها (Named Parameters)
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

  static Future<void> addReaction({required String postId, required String userId, required String reactionType}) async {
    await _firestore.collection('posts').doc(postId).set({
      'reactions': {userId: reactionType}
    }, SetOptions(merge: true));
  }

  static Future<void> updateReaction({required String postId, required String userId, required String reactionType}) async {
    await addReaction(postId: postId, userId: userId, reactionType: reactionType);
  }

  static Future<void> deletePost({required String postId, List<String>? publicIds}) async {
    try {
      final docRef = _firestore.collection('posts').doc(postId);
      final snapshot = await docRef.get();
      if (!snapshot.exists) {
        return;
      }

      final data = snapshot.data() ?? <String, dynamic>{};
      final fallbackPublicId = data['publicId'] as String? ?? '';
      final resolvedPublicIds = <String>[];
      if (publicIds != null) {
        resolvedPublicIds.addAll(publicIds.where((id) => id.isNotEmpty));
      }

      if (resolvedPublicIds.isEmpty) {
        if (data['mediaFiles'] is List) {
          for (final rawItem in data['mediaFiles'] as List<dynamic>) {
            if (rawItem is Map<String, dynamic>) {
              final filePublicId = rawItem['publicId'] as String? ?? '';
              if (filePublicId.isNotEmpty) {
                resolvedPublicIds.add(filePublicId);
              }
            } else if (rawItem is Map) {
              final filePublicId = rawItem['publicId']?.toString() ?? '';
              if (filePublicId.isNotEmpty) {
                resolvedPublicIds.add(filePublicId);
              }
            }
          }
        }
        if (resolvedPublicIds.isEmpty && fallbackPublicId.isNotEmpty) {
          resolvedPublicIds.add(fallbackPublicId);
        }
      }

      await docRef.delete();

      for (final id in resolvedPublicIds) {
        if (id.isEmpty) continue;
        try {
          await deleteCloudinaryAsset(id);
        } catch (error) {
          debugPrint('Failed to delete Cloudinary asset: $error');
        }
      }
    } catch (e) {
      throw Exception('فشل حذف المنشور: $e');
    }
  }

  static Future<void> deleteCloudinaryAsset(String publicId) async {
    final projectId = Firebase.app().options.projectId;
    final functionUrl = 'https://us-central1-$projectId.cloudfunctions.net/deleteCloudinaryAsset';

    final response = await http.post(
      Uri.parse(functionUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'publicId': publicId, 'resourceType': 'auto'}),
    );

    if (response.statusCode >= 400) {
      throw Exception('Cloud Function delete failed: ${response.statusCode} ${response.body}');
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