import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../models/atyaaf_video.dart';

class AtyaafService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _collection => _firestore.collection('atyaf_reels');

  Future<List<AtyaafVideo>> fetchVideos({int limit = 10}) async {
    final snapshot = await _collection
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();

    return snapshot.docs.map(AtyaafVideo.fromFirestore).toList();
  }

  Future<String> addReel({
    required String userId,
    required String caption,
    required String videoUrl,
    required String publicId,
  }) async {
    final docRef = await _collection.add({
      'videoUrl': videoUrl,
      'publicId': publicId,
      'userId': userId,
      'caption': caption,
      'createdAt': FieldValue.serverTimestamp(),
      'likes': 0,
      'likesCount': 0,
      'views': 0,
      'viewsCount': 0,
      'title': caption.isNotEmpty ? caption : 'Atyaaf',
      'description': caption,
      'relatedContentRef': 'home',
    });

    return docRef.id;
  }

  Future<void> incrementViews({required String videoId}) async {
    try {
      await _collection.doc(videoId).update({
        'views': FieldValue.increment(1),
        'viewsCount': FieldValue.increment(1),
      });
    } catch (e) {
      // ignore errors for now
    }
  }

  Future<void> deleteReel({required String reelId, required String publicId}) async {
    await _collection.doc(reelId).delete();

    if (publicId.isNotEmpty) {
      try {
        await deleteVideoFromCloudinary(publicId);
      } catch (error) {
        debugPrint('Failed to delete Cloudinary asset: $error');
      }
    }
  }

  Future<void> deleteVideoFromCloudinary(String publicId) async {
    final projectId = Firebase.app().options.projectId;
    final functionUrl = 'https://us-central1-$projectId.cloudfunctions.net/deleteCloudinaryAsset';

    final response = await http.post(
      Uri.parse(functionUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'publicId': publicId, 'resourceType': 'video'}),
    );

    if (response.statusCode >= 400) {
      throw Exception('Cloud Function delete failed: ${response.statusCode} ${response.body}');
    }
  }

  Future<void> saveVideoForUser({
    required String userId,
    required String videoId,
    required String title,
  }) async {
    await _firestore.collection('users').doc(userId).collection('savedAtyaaf').doc(videoId).set({
      'videoId': videoId,
      'title': title,
      'savedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> removeSavedVideo({required String userId, required String videoId}) async {
    await _firestore.collection('users').doc(userId).collection('savedAtyaaf').doc(videoId).delete();
  }

  Future<bool> isVideoSaved({required String userId, required String videoId}) async {
    final snapshot = await _firestore.collection('users').doc(userId).collection('savedAtyaaf').doc(videoId).get();
    return snapshot.exists;
  }

  String buildOptimizedVideoUrl(String url, {bool useHls = false}) {
    if (url.isEmpty) return url;

    final uri = Uri.tryParse(url);
    if (uri == null) return url;

    if (!uri.path.contains('/video/upload/')) return url;

    final transformation = useHls
        ? 'q_auto,f_m3u8,vc_h264,ac_aac,fl_hls'
        : 'q_auto,f_mp4,vc_h264,ac_aac,sp_auto';

    var path = uri.path.replaceFirst('/video/upload/', '/video/upload/$transformation,');
    if (useHls) {
      path = path.replaceFirst(RegExp(r'\.[^/]+$'), '.m3u8');
    }

    return uri.replace(path: path).toString();
  }

  String buildFallbackVideoUrl(String url) {
    if (url.isEmpty) return url;

    final uri = Uri.tryParse(url);
    if (uri == null) return url;

    if (!uri.path.contains('/video/upload/')) return url;

    final path = uri.path.replaceFirst('/video/upload/', '/video/upload/q_auto,f_webm,vc_vp9,ac_none,');
    return uri.replace(path: path).toString();
  }

  String buildOptimizedThumbnailUrl(String url) {
    if (url.isEmpty) return url;

    final uri = Uri.tryParse(url);
    if (uri == null) return url;

    if (!uri.path.contains('/video/upload/')) return url;

    final path = uri.path.replaceFirst('/video/upload/', '/video/upload/q_auto,f_auto,w_600,ar_16:9,c_fill,');
    return uri.replace(path: path).toString();
  }
}
