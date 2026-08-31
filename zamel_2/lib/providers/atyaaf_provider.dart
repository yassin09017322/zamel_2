import 'package:flutter/material.dart';
import '../models/atyaaf_video.dart';
import '../screens/feature_ideas_screen.dart';
import '../screens/feed_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/settings_screen.dart';
import '../services/atyaaf_service.dart';

class AtyaafProvider extends ChangeNotifier {
  final AtyaafService _service = AtyaafService();

  List<AtyaafVideo> videos = <AtyaafVideo>[];
  bool isLoading = false;
  String? errorMessage;
  final Set<String> _savedVideoIds = <String>{};

  Future<void> loadVideos() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      videos = await _service.fetchVideos(limit: 12);
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> toggleSave({required String userId, required AtyaafVideo video}) async {
    if (userId.isEmpty) return;

    if (_savedVideoIds.contains(video.id)) {
      await _service.removeSavedVideo(userId: userId, videoId: video.id);
      _savedVideoIds.remove(video.id);
    } else {
      await _service.saveVideoForUser(userId: userId, videoId: video.id, title: video.title);
      _savedVideoIds.add(video.id);
    }
    notifyListeners();
  }

  Future<void> syncSavedVideos(String userId) async {
    if (userId.isEmpty) return;
    _savedVideoIds.clear();
    for (final video in videos) {
      final isSaved = await _service.isVideoSaved(userId: userId, videoId: video.id);
      if (isSaved) {
        _savedVideoIds.add(video.id);
      }
    }
    notifyListeners();
  }

  bool isSaved(String videoId) => _savedVideoIds.contains(videoId);

  Future<void> openRelatedContent(BuildContext context, String relatedContentRef) async {
    final ref = relatedContentRef.trim().toLowerCase();

    switch (ref) {
      case 'ideas':
      case 'featureideas':
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FeatureIdeasScreen()));
        break;
      case 'feed':
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FeedScreen()));
        break;
      case 'profile':
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
        break;
      case 'settings':
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
        break;
      default:
        await Navigator.of(context).pushNamed('/home');
        break;
    }
  }
}
