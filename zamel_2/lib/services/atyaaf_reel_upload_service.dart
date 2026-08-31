import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';

import 'media_service.dart';

class AtyaafReelUploadService {
  AtyaafReelUploadService({MediaService? mediaService}) : _mediaService = mediaService ?? MediaService();

  final MediaService _mediaService;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collectionPath = 'atyaf_reels';

  Future<String> uploadAndCreateReel({
    required XFile videoFile,
    required String userId,
    required String username,
    required String caption,
    required void Function(double progress) onProgress,
  }) async {
    if (userId.trim().isEmpty) {
      throw Exception('User must be authenticated before creating a reel');
    }

    if (videoFile.path.isEmpty) {
      throw Exception('Selected video path is empty');
    }

    onProgress(0.1);

    final uploadResult = await _mediaService.uploadXFileWithResult(videoFile, isVideo: true);

    if (!uploadResult.success || (uploadResult.url ?? '').trim().isEmpty) {
      throw Exception(uploadResult.error ?? 'Video upload did not produce a valid URL');
    }

    onProgress(0.75);

    final docRef = await _firestore.collection(_collectionPath).add({
      'userId': userId,
      'username': username,
      'caption': caption,
      'videoUrl': uploadResult.url,
      'thumbnailUrl': '',
      'title': caption.isNotEmpty ? caption : 'Atyaaf',
      'description': caption,
      'relatedContentRef': 'home',
      'fileName': uploadResult.fileName ?? videoFile.name,
      'size': uploadResult.size ?? 0,
      'createdAt': FieldValue.serverTimestamp(),
      'likes': 0,
      'views': 0,
    });

    onProgress(1.0);
    return docRef.id;
  }
}
