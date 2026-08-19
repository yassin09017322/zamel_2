import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../models/atyaaf_video_model.dart';

class AtyaafController extends ChangeNotifier {
  AtyaafController({this.collectionPath = 'atyaaf', this.currentUserId = 'demo-user'});

  final String collectionPath;
  final String currentUserId;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool isLoading = false;
  bool isSaving = false;
  String? errorMessage;
  List<AtyaafVideoModel> videos = [];
  int currentIndex = 0;

  final Map<String, VideoPlayerController> _controllers = {};
  final Set<String> _favoriteIds = {};

  Stream<List<AtyaafVideoModel>> streamVideos() {
    return _firestore.collection(collectionPath).snapshots().map(
      (snapshot) => snapshot.docs.map(AtyaafVideoModel.fromFirestore).toList(),
    );
  }

  Future<void> loadVideos() async {
    if (isLoading) return;

    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final snapshot = await _firestore.collection(collectionPath).get();
      videos = snapshot.docs.map(AtyaafVideoModel.fromFirestore).toList();
      if (videos.isNotEmpty && currentIndex >= videos.length) {
        currentIndex = 0;
      }
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> initializeController(
    AtyaafVideoModel video, {
    bool autoPlay = false,
  }) async {
    if (_controllers.containsKey(video.id)) {
      if (autoPlay) {
        unawaited(_controllers[video.id]!.play());
      }
      return;
    }

    final controller = VideoPlayerController.networkUrl(Uri.parse(video.videoUrl));
    await controller.initialize();
    controller.setLooping(true);
    controller.setVolume(1.0);
    _controllers[video.id] = controller;

    if (autoPlay) {
      unawaited(controller.play());
    }

    notifyListeners();
  }

  Future<void> preloadAdjacentVideos(int index) async {
    if (index + 1 < videos.length) {
      await initializeController(videos[index + 1]);
    }

    if (index - 1 >= 0) {
      await initializeController(videos[index - 1]);
    }
  }

  Future<void> playActiveVideo(String videoId) async {
    _pauseAllExcept(videoId);
    final controller = _controllers[videoId];
    if (controller == null) {
      final video = videos.firstWhere((item) => item.id == videoId);
      await initializeController(video, autoPlay: true);
      return;
    }

    if (!controller.value.isInitialized) {
      final video = videos.firstWhere((item) => item.id == videoId);
      await initializeController(video, autoPlay: true);
      return;
    }

    if (!controller.value.isPlaying) {
      await controller.play();
    }
  }

  Future<void> pauseVideo(String videoId) async {
    final controller = _controllers[videoId];
    if (controller != null && controller.value.isInitialized && controller.value.isPlaying) {
      await controller.pause();
    }
  }

  void _pauseAllExcept(String activeId) {
    for (final entry in _controllers.entries) {
      if (entry.key != activeId && entry.value.value.isPlaying) {
        unawaited(entry.value.pause());
      }
    }
  }

  Future<void> toggleFavorite(String videoId) async {
    isSaving = true;
    notifyListeners();

    try {
      final wishlistRef = _firestore
          .collection('users')
          .doc(currentUserId)
          .collection('wishlist');

      if (_favoriteIds.contains(videoId)) {
        await wishlistRef.doc(videoId).delete();
        _favoriteIds.remove(videoId);
      } else {
        await wishlistRef.doc(videoId).set({
          'videoId': videoId,
          'savedAt': FieldValue.serverTimestamp(),
        });
        _favoriteIds.add(videoId);
      }
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isSaving = false;
      notifyListeners();
    }
  }

  bool isFavorite(String videoId) => _favoriteIds.contains(videoId);

  VideoPlayerController? controllerFor(String videoId) => _controllers[videoId];

  bool isInitialized(String videoId) => _controllers[videoId]?.value.isInitialized ?? false;

  void setCurrentIndex(int index) {
    currentIndex = index;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }
}
