// Web implementation using dart:html and platform view registry
import 'dart:ui' as ui;
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:flutter/material.dart';

class WebVideoPlayer extends StatefulWidget {
  final String url;
  final bool autoPlay;
  final bool loop;
  final bool muted;
  final String viewId;

  const WebVideoPlayer({Key? key, required this.url, this.autoPlay = true, this.loop = true, this.muted = true, required this.viewId}) : super(key: key);

  @override
  State<WebVideoPlayer> createState() => _WebVideoPlayerState();
}

class _WebVideoPlayerState extends State<WebVideoPlayer> {
  static final Set<String> _registeredViewTypes = <String>{};
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'web-video-${widget.viewId}';

    if (!_registeredViewTypes.contains(_viewType)) {
      _registeredViewTypes.add(_viewType);

      // ignore: undefined_prefixed_name
      ui.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
        final video = html.VideoElement()
          ..src = widget.url
          ..autoplay = widget.autoPlay
          ..loop = widget.loop
          ..muted = widget.muted
          ..controls = false
          ..preload = 'auto'
          ..style.border = '0';

        // Use setAttribute to ensure compatibility across dart:html bindings
        video.setAttribute('playsinline', '');
        video.setAttribute('crossorigin', 'anonymous');

        video.onError.listen((_) {
          // ignore: avoid_print
          print('WebVideoPlayer: video error for ${widget.url} - errorCode=${video.error?.code}');
        });

        return video;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
