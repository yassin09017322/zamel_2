import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class MainFeedVideoPlayer extends StatefulWidget {
  final String url;

  const MainFeedVideoPlayer({super.key, required this.url});

  @override
  State<MainFeedVideoPlayer> createState() => _MainFeedVideoPlayerState();
}

class _MainFeedVideoPlayerState extends State<MainFeedVideoPlayer> {
  static const _controlsDuration = Duration(seconds: 3);
  static const _visibilityThreshold = 0.01;
  static _MainFeedVideoPlayerState? _audiblePlayer;
  static Future<void> _audioTransition = Future<void>.value();

  final GlobalKey _videoKey = GlobalKey();
  VideoPlayerController? _controller;
  ScrollableState? _scrollableState;
  ScrollPosition? _scrollPosition;
  Timer? _controlsTimer;
  bool _showControls = false;
  bool _muted = false;
  bool _isVisible = false;
  Object? _initializationError;

  @override
  void initState() {
    super.initState();
    _initializeController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextScrollable = _findOuterScrollable();
    final nextPosition = nextScrollable?.position;
    if (_scrollPosition == nextPosition && _scrollableState == nextScrollable) {
      return;
    }
    _scrollPosition?.removeListener(_handleScroll);
    _scrollableState = nextScrollable;
    _scrollPosition = nextPosition;
    _scrollPosition?.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateVisibility());
  }

  @override
  void didUpdateWidget(covariant MainFeedVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _disposeController();
      _muted = false;
      _isVisible = false;
      _initializationError = null;
      _initializeController();
    }
  }

  Future<void> _initializeController() async {
    final uri = Uri.tryParse(widget.url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      _initializationError = const FormatException('Invalid video URL');
      if (mounted) setState(() {});
      return;
    }

    final controller = VideoPlayerController.networkUrl(uri);
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted || _controller != controller) {
        await controller.dispose();
        return;
      }
      await controller.setLooping(false);
      await controller.setVolume(0);
      await controller.play();
      if (mounted) setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateVisibility());
    } catch (error) {
      if (_controller == controller) {
        _initializationError = error;
        await controller.dispose();
        _controller = null;
        if (mounted) setState(() {});
      } else {
        await controller.dispose();
      }
    }
  }

  @override
  void dispose() {
    _scrollPosition?.removeListener(_handleScroll);
    _controlsTimer?.cancel();
    if (identical(_audiblePlayer, this)) _audiblePlayer = null;
    _disposeController();
    super.dispose();
  }

  void _disposeController() {
    final controller = _controller;
    _controller = null;
    controller?.dispose();
  }

  void _handleScroll() => _updateVisibility();

  ScrollableState? _findOuterScrollable() {
    ScrollableState? outerScrollable;
    context.visitAncestorElements((element) {
      if (element is StatefulElement && element.state is ScrollableState) {
        outerScrollable = element.state as ScrollableState;
      }
      return true;
    });
    return outerScrollable;
  }

  void _updateVisibility() {
    if (!mounted) return;
    final renderObject = _videoKey.currentContext?.findRenderObject();
    final viewport = _scrollableState?.context.findRenderObject();
    if (renderObject is! RenderBox || viewport is! RenderBox || !renderObject.hasSize) {
      return;
    }

    final videoTopLeft = renderObject.localToGlobal(Offset.zero);
    final videoBottomRight = renderObject.localToGlobal(
      renderObject.size.bottomRight(Offset.zero),
    );
    final viewportTopLeft = viewport.localToGlobal(Offset.zero);
    final viewportBottomRight = viewport.localToGlobal(
      viewport.size.bottomRight(Offset.zero),
    );
    final visibleWidth = (videoBottomRight.dx.clamp(
              viewportTopLeft.dx,
              viewportBottomRight.dx,
            ) -
            videoTopLeft.dx.clamp(
              viewportTopLeft.dx,
              viewportBottomRight.dx,
            ))
        .clamp(0.0, renderObject.size.width);
    final visibleHeight = (videoBottomRight.dy.clamp(
              viewportTopLeft.dy,
              viewportBottomRight.dy,
            ) -
            videoTopLeft.dy.clamp(
              viewportTopLeft.dy,
              viewportBottomRight.dy,
            ))
        .clamp(0.0, renderObject.size.height);
    final visibleFraction = renderObject.size.width <= 0 ||
            renderObject.size.height <= 0
        ? 0.0
        : (visibleWidth * visibleHeight) /
            (renderObject.size.width * renderObject.size.height);
    final visible = visibleFraction > _visibilityThreshold;
    if (_isVisible == visible) return;
    _isVisible = visible;
    if (!visible) {
      _muteImmediately();
    } else if (!_muted) {
      unawaited(_claimAudio());
    }
  }

  void _muteImmediately() {
    _muted = true;
    if (identical(_audiblePlayer, this)) _audiblePlayer = null;
    _queueVolumeChange(0);
  }

  Future<void> _claimAudio() {
    _audioTransition = _audioTransition.then((_) async {
      if (!mounted || !_isVisible || _muted) return;
      final previousPlayer = _audiblePlayer;
      if (previousPlayer != null && !identical(previousPlayer, this)) {
        previousPlayer._muteImmediately();
      }
      _audiblePlayer = this;
      await _setVolume(1);
    });
    return _audioTransition;
  }

  void _queueVolumeChange(double volume) {
    _audioTransition = _audioTransition.then((_) => _setVolume(volume));
  }

  Future<void> _setVolume(double volume) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      await controller.setVolume(volume);
    } catch (_) {}
  }

  Future<void> _togglePlayback() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleMute() async {
    final controller = _controller;
    if (controller == null || !_isVisible) return;
    final nextMuted = !_muted;
    _muted = nextMuted;
    if (!nextMuted) {
      await _claimAudio();
    } else {
      _queueVolumeChange(0);
    }
    if (mounted) setState(() {});
  }

  void _showTemporaryControls() {
    _controlsTimer?.cancel();
    if (mounted) setState(() => _showControls = true);
    _controlsTimer = Timer(_controlsDuration, () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  String _formatDuration(Duration duration) {
    final seconds = duration.inSeconds.clamp(0, 864000);
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return SizedBox(
        height: 220,
        child: Center(
          child: _initializationError == null
              ? const CircularProgressIndicator()
              : const Icon(Icons.broken_image, size: 40),
        ),
      );
    }

    return ClipRRect(
      key: _videoKey,
      borderRadius: BorderRadius.circular(18),
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            GestureDetector(
              onTap: _showTemporaryControls,
              child: VideoPlayer(controller),
            ),
            if (_showControls)
              Container(
                color: Colors.black54,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: controller,
                  builder: (context, value, child) {
                    final maximum = value.duration.inMilliseconds.toDouble();
                    final current = value.position.inMilliseconds
                        .clamp(0, value.duration.inMilliseconds)
                        .toDouble();
                    return Row(
                      children: [
                        IconButton(
                          color: Colors.white,
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            value.isPlaying ? Icons.pause : Icons.play_arrow,
                          ),
                          onPressed: _togglePlayback,
                        ),
                        IconButton(
                          color: Colors.white,
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            _muted ? Icons.volume_off : Icons.volume_up,
                          ),
                          onPressed: _toggleMute,
                        ),
                        Expanded(
                          child: Slider(
                            value: maximum > 0 ? current : 0,
                            min: 0,
                            max: maximum > 0 ? maximum : 1,
                            onChanged: maximum <= 0
                                ? null
                                : (value) => controller.seekTo(
                                      Duration(milliseconds: value.round()),
                                    ),
                          ),
                        ),
                        Text(
                          _formatDuration(value.duration - value.position),
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
}
