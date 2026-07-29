import 'package:flutter/material.dart';

class WebVideoPlayer extends StatelessWidget {
  final String url;
  final bool autoPlay;
  final bool loop;
  final bool muted;
  final String viewId;

  const WebVideoPlayer({Key? key, required this.url, this.autoPlay = true, this.loop = true, this.muted = true, this.viewId = '0'}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Non-web stub: render nothing (parent will fall back to thumbnail)
    return const SizedBox.shrink();
  }
}
