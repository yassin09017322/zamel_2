import 'package:zamel_appp/src/platform_file.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class MediaPreview extends StatefulWidget {
  final String mediaPath;
  final String mediaType;

  const MediaPreview({super.key, required this.mediaPath, required this.mediaType});

  @override
  State<MediaPreview> createState() => _MediaPreviewState();
}

class _MediaPreviewState extends State<MediaPreview> {
  VideoPlayerController? _videoController;
  bool _isInitialized = false;
  Object? _initializationError;

  @override
  void initState() {
    super.initState();
    if (widget.mediaType == 'video') {
      _initializeVideo();
    }
  }

  Future<void> _initializeVideo() async {
    if (widget.mediaPath.isEmpty) return;

    if (widget.mediaPath.startsWith('http')) {
      _videoController = VideoPlayerController.network(widget.mediaPath);
    } else if (!kIsWeb) {
      final dynamic file = File(widget.mediaPath);
      _videoController = VideoPlayerController.file(file);
    } else {
      return;
    }

    try {
      await _videoController!.initialize();
      await _videoController!.setLooping(true);
      await _videoController!.setVolume(0);
      await _videoController!.play();
    } catch (error) {
      _initializationError = error;
      await _videoController?.dispose();
      _videoController = null;
    }

    if (mounted) {
      setState(() => _isInitialized = _initializationError == null);
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mediaType == 'video') {
      if (!_isInitialized) {
        return Container(
          height: 220,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: Colors.black12),
          child: Center(
            child: _initializationError == null
                ? const CircularProgressIndicator()
                : const Icon(Icons.broken_image, color: Colors.white70, size: 40),
          ),
        );
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: AspectRatio(
          aspectRatio: _videoController!.value.aspectRatio,
          child: VideoPlayer(_videoController!),
        ),
      );
    }

    if (widget.mediaPath.startsWith('http')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.network(widget.mediaPath, fit: BoxFit.cover),
      );
    }

    if (kIsWeb) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          color: Colors.black12,
          height: 220,
          child: const Center(child: Text('لا يمكن معاينة الملف محلياً على الويب')),
        ),
      );
    }

    final dynamic file = File(widget.mediaPath);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.file(file, fit: BoxFit.cover),
    );
  }
}
