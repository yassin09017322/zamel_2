import 'package:zamel_appp/src/platform_file.dart';

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
    } else {
      final dynamic file = File(widget.mediaPath);
      _videoController = VideoPlayerController.file(file);
    }

    await _videoController!.initialize();
    _videoController!
      ..setLooping(true)
      ..setVolume(0)
      ..play();

    if (mounted) {
      setState(() => _isInitialized = true);
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
          child: const Center(child: CircularProgressIndicator()),
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

    final dynamic file = File(widget.mediaPath);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.file(file, fit: BoxFit.cover),
    );
  }
}
