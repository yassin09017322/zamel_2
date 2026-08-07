import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../widgets/web_video_player.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/atyaaf_video.dart';
import '../providers/atyaaf_provider.dart';
import '../providers/auth_provider.dart';
import '../services/atyaaf_reel_upload_service.dart';
import '../services/atyaaf_service.dart';
import 'profile_screen.dart';

class AtyaafReelsScreen extends StatefulWidget {
  const AtyaafReelsScreen({super.key});

  @override
  State<AtyaafReelsScreen> createState() => _AtyaafReelsScreenState();
}

class _AtyaafReelsScreenState extends State<AtyaafReelsScreen> {
  late final PageController _pageController;
  final Map<int, VideoPlayerController> _controllers = <int, VideoPlayerController>{};
  final AtyaafService _service = AtyaafService();
  final AtyaafReelUploadService _uploadService = AtyaafReelUploadService();
  final Map<int, String?> _controllerErrors = <int, String?>{};
  int _currentIndex = 0;
  final Set<String> _countedViewIds = <String>{};
  bool _isUploadingReel = false;
  double _uploadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    unawaited(_initializeVideos());
  }

  Future<void> _initializeVideos() async {
    final atyaafProvider = context.read<AtyaafProvider>();

    await atyaafProvider.loadVideos();
    if (!mounted || atyaafProvider.videos.isEmpty) return;

    await _prepareControllersForIndex(0);
    await _playCurrentVideo();
  }

  Future<void> _reloadVideos() async {
    for (final controller in _controllers.values) {
      await controller.pause();
      await controller.dispose();
    }
    _controllers.clear();
    setState(() {
      _currentIndex = 0;
    });
    await _initializeVideos();
  }

  Future<void> _prepareControllersForIndex(int index) async {
    if (!mounted) return;

    final provider = context.read<AtyaafProvider>();
    if (index < 0 || index >= provider.videos.length) return;

    final indexesToKeep = <int>{index, index + 1, index - 1}
        .where((value) => value >= 0 && value < provider.videos.length)
        .toSet();

    final toDispose = _controllers.keys.where((value) => !indexesToKeep.contains(value)).toList();
    for (final value in toDispose) {
      final controller = _controllers.remove(value);
      if (controller != null) {
        await controller.pause();
        await controller.dispose();
      }
    }

    await _initializeControllerForIndex(index);
    await _initializeControllerForIndex(index + 1);
    await _initializeControllerForIndex(index - 1);
  }

  VideoPlayerController _createNetworkController(String url) {
    if (kIsWeb) {
      return VideoPlayerController.networkUrl(Uri.parse(url));
    }

    return VideoPlayerController.networkUrl(
      Uri.parse(url),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
  }

  Future<void> _initializeControllerForIndex(int index) async {
    final provider = context.read<AtyaafProvider>();
    if (index < 0 || index >= provider.videos.length) return;
    if (_controllers.containsKey(index)) return;

    final video = provider.videos[index];
    final primaryUrl = _normalizeVideoUrl(video.videoUrl);
    final fallbackUrl = _service.buildOptimizedVideoUrl(primaryUrl);
    final alternativeUrl = _service.buildFallbackVideoUrl(primaryUrl);
    final hlsUrl = _service.buildOptimizedVideoUrl(primaryUrl, useHls: true);

    VideoPlayerController controller = _createNetworkController(primaryUrl);
    _controllers[index] = controller;
    try {
      await controller.initialize();
      await controller.setLooping(true);
      _controllerErrors.remove(index);
      if (mounted) setState(() {});
    } catch (error) {
      debugPrint('Primary reel URL failed: $error');
      _controllerErrors[index] = error.toString();
      if (mounted) setState(() {});
      await controller.dispose();

      try {
        final fallbackController = _createNetworkController(fallbackUrl);
        _controllers[index] = fallbackController;
        try {
          await fallbackController.initialize();
          await fallbackController.setLooping(true);
          _controllerErrors.remove(index);
          if (mounted) setState(() {});
        } catch (fallbackError) {
          debugPrint('Fallback init failed: $fallbackError');
          _controllerErrors[index] = fallbackError.toString();
          if (mounted) setState(() {});
          await fallbackController.dispose();
          try {
            final alternativeController = _createNetworkController(alternativeUrl);
            _controllers[index] = alternativeController;
            try {
              await alternativeController.initialize();
              await alternativeController.setLooping(true);
              _controllerErrors.remove(index);
              if (mounted) setState(() {});
            } catch (alternativeError) {
              debugPrint('Alternative init failed: $alternativeError');
              _controllerErrors[index] = alternativeError.toString();
              if (mounted) setState(() {});
              await alternativeController.dispose();
            }
          } catch (alternativeError) {
            debugPrint('Alternative reel URL also failed: $alternativeError');
            if (mounted) setState(() {});
          }
        }
      } catch (fallbackError) {
        debugPrint('Fallback reel URL also failed: $fallbackError');
        if (mounted) setState(() {});
        await controller.dispose();
        try {
          final alternativeController = _createNetworkController(hlsUrl);
          _controllers[index] = alternativeController;
          try {
            await alternativeController.initialize();
            await alternativeController.setLooping(true);
            _controllerErrors.remove(index);
            if (mounted) setState(() {});
          } catch (alternativeError) {
            debugPrint('Alternative init failed: $alternativeError');
            _controllerErrors[index] = alternativeError.toString();
            if (mounted) setState(() {});
            await alternativeController.dispose();
          }
        } catch (alternativeError) {
          debugPrint('Alternative reel URL also failed: $alternativeError');
          if (mounted) setState(() {});
        }
      }
    }
  }

  String _normalizeVideoUrl(String url) {
    if (url.isEmpty) return url;
    final uri = Uri.tryParse(url);
    if (uri == null) return url;

    const uploadPrefix = '/video/upload/';
    final prefixIndex = uri.path.indexOf(uploadPrefix);
    if (prefixIndex < 0) return url;

    final afterUpload = uri.path.substring(prefixIndex + uploadPrefix.length);
    final parts = afterUpload.split('/');
    if (parts.length < 2) return url;

    final transformationPart = parts.first;
    final versionPart = parts[1];

    final hasTransformation = RegExp(r'^(q_auto|f_[a-z0-9]+|vc_[a-z0-9]+|ac_[a-z0-9]+|fl_[a-z0-9]+|sp_[a-z0-9]+,?)').hasMatch(transformationPart);
    final hasVersion = RegExp(r'^v\d+$').hasMatch(versionPart);

    if (hasTransformation && hasVersion) {
      final normalizedPath = uri.path.substring(0, prefixIndex + uploadPrefix.length) + parts.sublist(1).join('/');
      return uri.replace(path: normalizedPath).toString();
    }

    return url;
  }

  Future<void> _playCurrentVideo() async {
    if (!mounted) return;
    final provider = context.read<AtyaafProvider>();
    if (provider.videos.isEmpty) return;

    for (final entry in _controllers.entries) {
      final shouldPlay = entry.key == _currentIndex;
      if (entry.value.value.isInitialized) {
        if (shouldPlay) {
          await entry.value.play();
          await entry.value.setVolume(1.0);
          try {
            final video = provider.videos[entry.key];
            if (!_countedViewIds.contains(video.id)) {
              _countedViewIds.add(video.id);
              unawaited(_service.incrementViews(videoId: video.id));
            }
          } catch (_) {}
        } else {
          await entry.value.pause();
        }
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _uploadReel(BuildContext context) async {
    if (_isUploadingReel) return;

    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;

    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يجب تسجيل الدخول أولاً قبل رفع الريل')));
      return;
    }

    final captionController = TextEditingController();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('رفع ريل جديد', textAlign: TextAlign.center),
          content: TextField(
            controller: captionController,
            maxLines: 3,
            textAlign: TextAlign.right,
            decoration: const InputDecoration(
              hintText: 'اكتب وصفاً للريل...',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('اختيار الفيديو'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    final picker = ImagePicker();
    final video = await picker.pickVideo(source: ImageSource.gallery);
    if (video == null) return;

    if (!mounted) return;

    final previewConfirmed = await _showVideoPreviewDialog(video);
    if (previewConfirmed != true) return;

    setState(() {
      _isUploadingReel = true;
      _uploadProgress = 0.0;
    });

    try {
      await _uploadService.uploadAndCreateReel(
        videoFile: video,
        userId: currentUser.id,
        caption: captionController.text.trim(),
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _uploadProgress = progress);
        },
      );

      if (!mounted) return;
      await _reloadVideos();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم رفع الريل بنجاح ✅')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل رفع الريل: $error')));
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingReel = false);
      }
    }
  }

  Future<bool> _showVideoPreviewDialog(XFile videoFile) async {
    final controller = _buildPreviewController(videoFile);
    try {
      await controller.initialize();
    } catch (error) {
      debugPrint('Preview initialization failed: $error');
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('معاينة الفيديو', textAlign: TextAlign.center),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (controller.value.isInitialized)
                  AspectRatio(
                    aspectRatio: controller.value.aspectRatio > 0 ? controller.value.aspectRatio : 16 / 9,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: VideoPlayer(controller),
                    ),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('تعذر معاينة هذا الفيديو الآن، لكن يمكنك المتابعة إلى الرفع.'),
                  ),
                const SizedBox(height: 12),
                const Text('سيتم رفع الفيديو إلى الخادم ثم حفظ الرابط.', textAlign: TextAlign.center),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
            ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('متابعة الرفع')),
          ],
        );
      },
    );

    await controller.pause();
    await controller.dispose();
    return confirmed == true;
  }

  VideoPlayerController _buildPreviewController(XFile videoFile) {
    final parsedUri = Uri.tryParse(videoFile.path);
    if (parsedUri != null && parsedUri.scheme == 'content') {
      return VideoPlayerController.contentUri(parsedUri);
    }

    if (parsedUri != null &&
        (parsedUri.scheme == 'http' ||
            parsedUri.scheme == 'https' ||
            parsedUri.scheme == 'blob')) {
      return VideoPlayerController.networkUrl(parsedUri);
    }

    if (kIsWeb) {
      return VideoPlayerController.networkUrl(Uri.parse(videoFile.path));
    }

    return VideoPlayerController.file(File(videoFile.path));
  }

  Future<void> _showCommentsSheet(BuildContext context, AtyaafVideo video) async {
    final commentController = TextEditingController();
    try {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) {
          bool isTyping = false;

          return StatefulBuilder(
            builder: (context, setModalState) {
              return Directionality(
                textDirection: TextDirection.rtl,
                child: Container(
                  height: MediaQuery.of(context).size.height * 0.65,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
                      const SizedBox(height: 16),
                      const Text('التعليقات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const Divider(),
                      Expanded(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.chat_bubble_outline, size: 50, color: Colors.grey[400]),
                              const SizedBox(height: 10),
                              Text('كن أول من يترك تعليقاً!', style: TextStyle(color: Colors.grey[600])),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        padding: EdgeInsets.only(
                          left: 16, right: 16, top: 12,
                          bottom: MediaQuery.of(context).viewInsets.bottom + 12
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: commentController,
                                onChanged: (val) => setModalState(() => isTyping = val.trim().isNotEmpty),
                                decoration: InputDecoration(
                                  hintText: 'أضف تعليقاً...',
                                  filled: true,
                                  fillColor: Colors.grey[100],
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () {
                                if (isTyping) {
                                  commentController.clear();
                                  setModalState(() => isTyping = false);
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال التعليق')));
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اضغط مطولاً لتسجيل رسالة صوتية 🎤')));
                                }
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isTyping ? const Color(0xFF5B6CFF) : const Color(0xFF2EC7A5),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isTyping ? Icons.send_rounded : Icons.mic,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    } catch (e) {
      debugPrint("Error showing comments: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AtyaafProvider>();
    final authProvider = context.watch<AuthProvider>();

    if (provider.isLoading && provider.videos.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Color(0xFFE94057))),
      );
    }

    if (provider.videos.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.05)),
                child: const Icon(Icons.video_library_rounded, size: 80, color: Color(0xFFE94057)),
              ),
              const SizedBox(height: 24),
              const Text('لا توجد مقاطع أطياف بعد', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text('كن أول من يشارك لحظاته وإبداعاته\nمع مجتمع زامل!', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 16)),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _isUploadingReel ? null : () => _uploadReel(context),
                icon: _isUploadingReel
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.upload_rounded, color: Colors.white),
                label: Text(
                  _isUploadingReel ? 'جاري الرفع...' : 'رفع أول مقطع الآن',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE94057),
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_isUploadingReel)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                value: _uploadProgress.clamp(0.0, 1.0),
                minHeight: 3,
                backgroundColor: Colors.white24,
                color: const Color(0xFFE94057),
              ),
            ),
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            pageSnapping: true,
            physics: const PageScrollPhysics(),
            itemCount: provider.videos.length,
            onPageChanged: (index) async {
              setState(() => _currentIndex = index);
              await _prepareControllersForIndex(index);
              await _playCurrentVideo();
            },
            itemBuilder: (context, index) {
              final video = provider.videos[index];
              final controller = _controllers[index];

              return _AtyaafVideoCard(
                key: ValueKey(video.id),
                video: video,
                controller: controller,
                initError: _controllerErrors[index],
                isPlaying: _currentIndex == index,
                isSaved: provider.isSaved(video.id),
                onSave: () async {
                  if (authProvider.currentUser == null) return;
                  await provider.toggleSave(userId: authProvider.currentUser!.id, video: video);
                  await provider.syncSavedVideos(authProvider.currentUser!.id);
                },
                onRelatedContent: () async {
                  await provider.openRelatedContent(context, video.relatedContentRef);
                },
                onComment: () => _showCommentsSheet(context, video),
                onShare: () {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('جاري المشاركة... 🔗'), duration: Duration(seconds: 1)));
                },
                isOwner: authProvider.currentUser?.id == video.userId,
                onDelete: () async {
                  if (authProvider.currentUser == null) return;
                  await _service.deleteReel(reelId: video.id);
                  await _reloadVideos();
                },
              );
            },
          ),
          
          SafeArea(
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'أطياف', 
                      style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, shadows: [Shadow(color: Colors.black54, blurRadius: 10)])
                    ),
                    GestureDetector(
                      onTap: _isUploadingReel ? null : () => _uploadReel(context),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.add, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AtyaafVideoCard extends StatelessWidget {
  final AtyaafVideo video;
  final VideoPlayerController? controller;
  final String? initError;
  final bool isPlaying;
  final bool isSaved;
  final VoidCallback onSave;
  final VoidCallback onRelatedContent;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final bool isOwner;
  final VoidCallback onDelete;

  const _AtyaafVideoCard({
    super.key,
    required this.video,
    required this.controller,
    required this.initError,
    required this.isPlaying,
    required this.isSaved,
    required this.onSave,
    required this.onRelatedContent,
    required this.onComment,
    required this.onShare,
    required this.isOwner,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (initError != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text('عذراً، فشل تحميل الفيديو: $initError', style: const TextStyle(color: Colors.redAccent), textAlign: TextAlign.center),
              ),
            )
          else if (controller != null && controller!.value.isInitialized)
            GestureDetector(
              onTap: () {
                if (controller!.value.isPlaying) {
                  controller!.pause();
                } else {
                  controller!.play();
                }
              },
              child: SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: controller!.value.size.width,
                    height: controller!.value.size.height,
                    child: VideoPlayer(controller!),
                  ),
                ),
              ),
            )
          else
            const Center(child: CircularProgressIndicator(color: Color(0xFFE94057))),
          
          Positioned(
            right: 16,
            bottom: 100,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _buildActionButton(isSaved ? Icons.bookmark : Icons.bookmark_border, onSave, color: isSaved ? const Color(0xFFE94057) : Colors.white),
                const SizedBox(height: 16),
                _buildActionButton(Icons.comment, onComment),
                const SizedBox(height: 16),
                _buildActionButton(Icons.share, onShare),
                if (isOwner) ...[
                  const SizedBox(height: 16),
                  _buildActionButton(Icons.delete, onDelete, color: Colors.redAccent),
                ],
              ],
            ),
          ),
          Positioned(
            left: 16,
            bottom: 40,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('@${video.username}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                if (video.caption != null && video.caption!.isNotEmpty)
                  SizedBox(
                    width: MediaQuery.of(context).size.width * 0.6,
                    child: Text(video.caption!, style: const TextStyle(color: Colors.white), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, VoidCallback onTap, {Color color = Colors.white}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
        ],
      ),
    );
  }
}
