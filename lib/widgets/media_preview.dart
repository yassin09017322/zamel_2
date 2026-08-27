import 'package:zamel_appp/src/platform_file.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class MediaPreview extends StatefulWidget {
  final String mediaPath;
  final String mediaType;
  final bool enableAudio;
  final bool showControls;

  const MediaPreview({
    super.key,
    required this.mediaPath,
    required this.mediaType,
    this.enableAudio = false,
    this.showControls = false,
  });

  @override
  State<MediaPreview> createState() => _MediaPreviewState();
}

class _MediaPreviewState extends State<MediaPreview> {
  VideoPlayerController? _videoController;
  bool _isInitialized = false;
  Object? _initializationError;

  @override
  void didUpdateWidget(covariant MediaPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaPath != widget.mediaPath ||
        oldWidget.mediaType != widget.mediaType) {
      _disposeVideoController();
      if (widget.mediaType == 'video') _initializeVideo();
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.mediaType == 'video') {
      _initializeVideo();
    }
  }

  Future<void> _initializeVideo() async {
    if (widget.mediaPath.isEmpty) return;

    final controller = widget.mediaPath.startsWith('http')
        ? VideoPlayerController.networkUrl(Uri.parse(widget.mediaPath))
        : !kIsWeb
        ? VideoPlayerController.file(File(widget.mediaPath) as dynamic)
        : null;
    if (controller == null) return;
    _videoController = controller;

    try {
      await controller.initialize();
      if (!mounted || _videoController != controller) {
        await controller.dispose();
        return;
      }
      await controller.setLooping(false);
      await controller.setVolume(widget.enableAudio ? 1.0 : 0.0);
      await controller.play();
    } catch (error) {
      if (_videoController != controller) {
        await controller.dispose();
        return;
      }
      _initializationError = error;
      await controller.dispose();
      _videoController = null;
    }

    if (mounted) {
      setState(() => _isInitialized = _initializationError == null);
    }
  }

  @override
  void dispose() {
    _disposeVideoController();
    super.dispose();
  }

  void _disposeVideoController() {
    final controller = _videoController;
    _videoController = null;
    _isInitialized = false;
    _initializationError = null;
    controller?.dispose();
  }

  String _formatDuration(Duration value) {
    final totalSeconds = value.inSeconds.clamp(0, 864000);
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mediaType == 'video') {
      if (!_isInitialized) {
        return Container(
          height: 220,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.black12,
          ),
          child: Center(
            child: _initializationError == null
                ? const CircularProgressIndicator()
                : const Icon(
                    Icons.broken_image,
                    color: Colors.white70,
                    size: 40,
                  ),
          ),
        );
      }
      final controller = _videoController!;
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              GestureDetector(
                onTap: () async {
                  if (controller.value.isPlaying) {
                    await controller.pause();
                  } else {
                    await controller.play();
                  }
                },
                child: VideoPlayer(controller),
              ),
              if (widget.showControls)
                Container(
                  color: Colors.black54,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: controller,
                    builder: (context, value, child) {
                      final duration = value.duration;
                      final position = value.position;
                      final remaining = duration - position;
                      final maximum = duration.inMilliseconds.toDouble();
                      final current = position.inMilliseconds
                          .clamp(0, duration.inMilliseconds)
                          .toDouble();
                      return Row(
                        children: [
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            color: Colors.white,
                            icon: Icon(
                              value.isPlaying ? Icons.pause : Icons.play_arrow,
                            ),
                            onPressed: () async {
                              if (value.isPlaying) {
                                await controller.pause();
                              } else {
                                await controller.play();
                              }
                            },
                          ),
                          Expanded(
                            child: Slider(
                              value: maximum > 0 ? current : 0,
                              min: 0,
                              max: maximum > 0 ? maximum : 1,
                              onChanged: maximum <= 0
                                  ? null
                                  : (newValue) => controller.seekTo(
                                      Duration(milliseconds: newValue.round()),
                                    ),
                            ),
                          ),
                          Text(
                            _formatDuration(
                              remaining.isNegative ? Duration.zero : remaining,
                            ),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
            ],
          ),
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
          child: const Center(
            child: Text('لا يمكن معاينة الملف محلياً على الويب'),
          ),
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
