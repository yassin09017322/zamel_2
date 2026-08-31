// To cache video files using flutter_cache_manager and play them with VideoPlayerController,
// follow these steps:
// 1. Add flutter_cache_manager and video_player to pubspec.yaml.
// 2. Use DefaultCacheManager().getSingleFile(url) to download and cache the video.
// 3. Create a VideoPlayerController.file(cachedFile) and initialize it.
// 4. Dispose the controller when the widget is disposed.
//
// Example workflow:
// final file = await DefaultCacheManager().getSingleFile(videoUrl);
// _controller = VideoPlayerController.file(file);
// await _controller.initialize();
// _controller.play();
//
// This ensures the video is saved locally and re-used from cache instead of re-downloading.
