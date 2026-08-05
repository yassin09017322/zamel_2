import 'dart:async';
import 'package:zamel_appp/src/platform_file.dart';

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
import '../services/atyaaf_service.dart';
import '../services/media_service.dart';
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
  final Map<int, String?> _controllerErrors = <int, String?>{};
  int _currentIndex = 0;
  final Set<String> _countedViewIds = <String>{};

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
      return VideoPlayerController.network(url);
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
      // clear any previous error
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

    // Handle Cloudinary URLs (for backward compatibility with existing media)
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
          // increment views once per session for this video
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

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: Color(0xFFE94057))),
    );

    try {
      final mediaService = MediaService();
      final String uploadedUrl;

      if (kIsWeb) {
        uploadedUrl = await mediaService.uploadBytes(
          await video.readAsBytes(),
          video.name,
          isVideo: true,
        );
      } else {
        uploadedUrl = await mediaService.uploadFile(
          File(video.path),
          isVideo: true,
        );
      }

      final storedVideoUrl = uploadedUrl;

      await _service.addReel(
        userId: currentUser.id,
        caption: captionController.text.trim(),
        videoUrl: storedVideoUrl,
      );

      if (!mounted) return;
      Navigator.pop(context);
      await _reloadVideos();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم رفع الريل بنجاح ✅')));
    } catch (error) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل رفع الريل: $error')));
      }
    }
  }

  void _showCommentsSheet(BuildContext context, AtyaafVideo video) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final commentController = TextEditingController();
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
                onPressed: () => _uploadReel(context),
                icon: const Icon(Icons.upload_rounded, color: Colors.white),
                label: const Text('رفع أول مقطع الآن', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                      onTap: () => _uploadReel(context),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: Colors.black.withOpacity(0.4), shape: BoxShape.circle, border: Border.all(color: Colors.white38, width: 1)),
                        child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 26),
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

class _AtyaafVideoCard extends StatefulWidget {
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
    Key? key,
    required this.video,
    required this.controller,
    this.initError,
    required this.isPlaying,
    required this.isSaved,
    required this.onSave,
    required this.onRelatedContent,
    required this.onComment,
    required this.onShare,
    required this.isOwner,
    required this.onDelete,
  }) : super(key: key);

  @override
  State<_AtyaafVideoCard> createState() => _AtyaafVideoCardState();
}

class _AtyaafVideoCardState extends State<_AtyaafVideoCard> {
  String? _myReaction;
  bool _showPlaybackFeedback = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _viewsSub;
  late int _viewsLocal;

  static const Map<String, Map<String, dynamic>> _zamelReactions = {
    'like': {'emoji': '👍', 'label': 'أوافق', 'color': Color(0xFF5B6CFF)},
    'love': {'emoji': '❤️', 'label': 'أبدعت', 'color': Color(0xFFE94057)},
    'haha': {'emoji': '😂', 'label': 'ضحكتني', 'color': Color(0xFFF2C94C)},
    'spot_on': {'emoji': '🎯', 'label': 'في الصميم', 'color': Color(0xFF2EC7A5)},
    'support': {'emoji': '🤝', 'label': 'دعم', 'color': Color(0xFF8A2387)},
  };

  Future<void> _togglePlayback() async {
    final controller = widget.controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }

    if (!mounted) return;
    setState(() {
      _showPlaybackFeedback = true;
    });

    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) {
      setState(() {
        _showPlaybackFeedback = false;
      });
    }
  }

  void _showZamelReactions(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, anim1, anim2) {
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.only(right: 60, bottom: 80),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.8),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white24),
            ),
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _zamelReactions.entries.map((entry) {
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() => _myReaction = entry.key);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        children: [
                          Text(entry.value['emoji'], style: const TextStyle(fontSize: 28)),
                          const SizedBox(height: 4),
                          Text(
                            entry.value['label'], 
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: entry.value['color'])
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim1, anim2, child) {
        return Transform.scale(scale: anim1.value, child: Opacity(opacity: anim1.value, child: child));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = AtyaafService();
    final thumbnailUrl = widget.video.thumbnailUrl.isNotEmpty
        ? service.buildOptimizedThumbnailUrl(widget.video.thumbnailUrl)
        : service.buildOptimizedThumbnailUrl(widget.video.videoUrl);

    final reactionData = _myReaction != null ? _zamelReactions[_myReaction] : null;

    return Stack(
      children: [
        Positioned.fill(
            child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: widget.controller != null && widget.controller!.value.isInitialized
                ? FittedBox(
                    key: ValueKey('video-${widget.video.id}'),
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: widget.controller!.value.size.width > 0 ? widget.controller!.value.size.width : 1,
                      height: widget.controller!.value.size.height > 0 ? widget.controller!.value.size.height : 1,
                      child: VideoPlayer(widget.controller!),
                    ),
                  )
                : (kIsWeb && widget.initError != null && widget.initError!.isNotEmpty)
                    ? WebVideoPlayer(url: service.buildOptimizedVideoUrl(widget.video.videoUrl), viewId: widget.video.id)
                    : Stack(
                        children: [
                          CachedNetworkImage(
                        key: ValueKey('thumb-${widget.video.id}'),
                        imageUrl: thumbnailUrl,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        placeholder: (context, url) => const Center(child: CircularProgressIndicator(color: Color(0xFFE94057))),
                        errorWidget: (context, url, error) => const Icon(Icons.broken_image, color: Colors.grey, size: 50),
                          ),
                          if (widget.initError != null && widget.initError!.isNotEmpty)
                            Positioned.fill(
                              child: Container(
                                color: Colors.black54,
                                alignment: Alignment.center,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.error_outline, color: Colors.white, size: 48),
                                    const SizedBox(height: 8),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                      child: Text(
                                        'فشل تهيئة الفيديو (تحقق من رابط الفيديو أو إعدادات CORS)',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(color: Colors.white),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
          ),
        ),
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _togglePlayback,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: _showPlaybackFeedback ? 1.0 : 0.0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.45),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24, width: 1),
                  ),
                  child: Icon(
                    widget.controller != null && widget.controller!.value.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black.withOpacity(0.8), Colors.transparent, Colors.black.withOpacity(0.2)],
              ),
            ),
          ),
        ),
        Positioned(
          top: 92,
          left: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.34),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Row(
              children: [
                Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 16),
                SizedBox(width: 6),
                Text('أطياف', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
        Directionality(
          textDirection: TextDirection.rtl,
          child: Positioned(
            left: 16,
            right: 88,
            bottom: 24,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.28),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () {
                      if (widget.video.userId.isEmpty) return;
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(userId: widget.video.userId)));
                    },
                    child: Row(
                      children: [
                        const CircleAvatar(radius: 18, backgroundColor: Color(0xFF5B6CFF), child: Icon(Icons.person, color: Colors.white, size: 20)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.video.title.isNotEmpty ? widget.video.title : 'مستخدم زامل',
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.video.description.isNotEmpty ? widget.video.description : 'محتوى قصير ومفيد',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (widget.isOwner)
          Positioned(
            top: 92,
            right: 12,
            child: GestureDetector(
              onTap: widget.onDelete,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.45),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 24),
              ),
            ),
          ),
        Positioned(
          right: 12,
          bottom: 24,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onLongPress: () => _showZamelReactions(context),
                onTap: () {
                  setState(() => _myReaction = _myReaction == null ? 'like' : null);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    children: [
                      Text(reactionData?['emoji'] ?? '🤍', style: const TextStyle(fontSize: 30)),
                      const SizedBox(height: 4),
                      Text(
                        reactionData?['label'] ?? 'إعجاب',
                        style: TextStyle(color: reactionData?['color'] ?? Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _buildInteractionBtn(Icons.chat_bubble_rounded, 'تعليق', widget.onComment),
              const SizedBox(height: 14),
              _buildInteractionBtn(widget.isSaved ? Icons.bookmark : Icons.bookmark_border, 'حفظ', widget.onSave, iconColor: widget.isSaved ? const Color(0xFFE94057) : Colors.white),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: _onSharePressed,
                child: Column(
                  children: [
                    Icon(Icons.share_rounded, color: Colors.white, size: 32),
                    const SizedBox(height: 6),
                    const Text('مشاركة', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, shadows: [Shadow(color: Colors.black, blurRadius: 4)])),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (widget.video.relatedContentRef.isNotEmpty) ...[
                const SizedBox(height: 14),
                _buildInteractionBtn(Icons.open_in_new_rounded, 'محتوى', widget.onRelatedContent),
              ],
            ],
          ),
        ),
        Positioned(
          left: 16,
          bottom: 24,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              children: [
                const Icon(Icons.remove_red_eye_outlined, color: Colors.white, size: 16),
                const SizedBox(width: 6),
                Text('$_viewsLocal مشاهد', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
        if (!widget.isPlaying)
          const Positioned.fill(
            child: Center(
              child: Icon(Icons.play_arrow_rounded, color: Colors.white70, size: 80),
            ),
          ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _viewsLocal = widget.video.viewsCount;
    _viewsSub = FirebaseFirestore.instance.collection('atyaf_reels').doc(widget.video.id).snapshots().listen((snap) {
      final data = snap.data();
      if (data == null) return;
      final v = data['views'] ?? data['viewsCount'];
      if (v is int) {
        if (mounted) setState(() => _viewsLocal = v);
      }
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _viewsSub?.cancel();
    super.dispose();
  }

  Future<void> _onSharePressed() async {
    widget.onShare();
    await _showShareOptions();
  }

  Future<void> _shareText(String text, String subject) async {
    try {
      await Share.share(text, subject: subject);
    } catch (error) {
      debugPrint('Share failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذرت المشاركة، حاول مرة أخرى')));
      }
    }
  }

  Future<void> _showShareOptions() async {
    final url = widget.video.videoUrl;
    final title = widget.video.title.isNotEmpty ? widget.video.title : 'أطياف';
    final text = '$title\n$url';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('نسخ الرابط'),
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: url));
                  Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ الرابط')));
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.message, color: Color(0xFF25D366)),
                title: const Text('WhatsApp / الرسائل'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _shareText(text, title);
                },
              ),
              ListTile(
                leading: const Icon(Icons.thumb_up, color: Color(0xFF1877F2)),
                title: const Text('Facebook'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _shareText(text, title);
                },
              ),
              ListTile(
                leading: const Icon(Icons.send, color: Color(0xFF26A5E4)),
                title: const Text('Telegram'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _shareText(text, title);
                },
              ),
              ListTile(
                leading: const Icon(Icons.alternate_email, color: Colors.black),
                title: const Text('X / Twitter'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _shareText(text, title);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Color(0xFFC13584)),
                title: const Text('Instagram'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _shareText(text, title);
                },
              ),
              ListTile(
                leading: const Icon(Icons.music_note, color: Colors.black),
                title: const Text('TikTok'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _shareText(text, title);
                },
              ),
              ListTile(
                leading: const Icon(Icons.more_horiz),
                title: const Text('مشاركة عبر النظام'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _shareText(text, title);
                },
              ),
            ],
          ),
        );
      },
    );
  }



  Widget _buildInteractionBtn(IconData icon, String label, VoidCallback onTap, {Color iconColor = Colors.white}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 32),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, shadows: const [Shadow(color: Colors.black, blurRadius: 4)])),
        ],
      ),
    );
  }
}
