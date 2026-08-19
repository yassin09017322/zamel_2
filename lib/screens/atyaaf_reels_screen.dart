import 'dart:async';
import 'dart:io'; // تم إضافته لحل مشكلة File

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../models/atyaaf_video.dart';
import '../providers/atyaaf_provider.dart';
import '../providers/auth_provider.dart';
import '../services/atyaaf_reel_upload_service.dart';
import '../services/atyaaf_service.dart';

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
  final Map<String, int> _reactionCounts = <String, int>{};
  final Map<String, int> _shareCounts = <String, int>{};
  final Map<String, int> _saveCounts = <String, int>{};
  final Map<String, String> _selectedReactionEmojis = <String, String>{};
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
      // تم التعديل هنا جذرياً: منع التداخل من جذور النظام
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
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
          await entry.value.setVolume(1.0); // تأكيد رفع الصوت للفيديو الحالي
          await entry.value.play();
          try {
            final video = provider.videos[entry.key];
            if (!_countedViewIds.contains(video.id)) {
              _countedViewIds.add(video.id);
              unawaited(_service.incrementViews(videoId: video.id));
            }
          } catch (_) {}
        } else {
          await entry.value.setVolume(0.0); // كتم لحظي لمنع التداخل أثناء الإيقاف
          await entry.value.pause();
        }
      }
    }
  }

  int _getReactionCount(AtyaafVideo video) {
    return _reactionCounts[video.id] ?? video.likesCount;
  }

  int _getShareCount(AtyaafVideo video) {
    return _shareCounts[video.id] ?? 0;
  }

  int _getSaveCount(AtyaafVideo video) {
    return _saveCounts[video.id] ?? 0;
  }

  String? _getSelectedReactionEmoji(AtyaafVideo video) {
    return _selectedReactionEmojis[video.id];
  }

  void _applyReaction(String videoId, String emoji) {
    setState(() {
      _reactionCounts[videoId] = (_reactionCounts[videoId] ?? 0) + 1;
      _selectedReactionEmojis[videoId] = emoji;
    });
  }

  void _incrementShareCount(String videoId) {
    setState(() {
      _shareCounts[videoId] = (_shareCounts[videoId] ?? 0) + 1;
    });
  }

  void _updateSaveCount(String videoId, bool added) {
    setState(() {
      final current = _saveCounts[videoId] ?? 0;
      _saveCounts[videoId] = added ? current + 1 : (current > 0 ? current - 1 : 0);
    });
  }

  Future<void> _showReactionOptions(BuildContext context, AtyaafVideo video) async {
    final chosenEmoji = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF3B1E88), Color(0xFF7C4DFF)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 20, offset: const Offset(0, -8)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 60,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.white54,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('اختر رد فعل', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 8),
                const Text('انقر على الإيموجي المفضل لديك لتفاعل رائع', style: TextStyle(fontSize: 14, color: Colors.white70), textAlign: TextAlign.center),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  alignment: WrapAlignment.center,
                  children: [
                    _buildEmojiReactionButton(context, '😍', 'حب'),
                    _buildEmojiReactionButton(context, '😂', 'ضحك'),
                    _buildEmojiReactionButton(context, '😮', 'مفاجأة'),
                    _buildEmojiReactionButton(context, '🔥', 'نار'),
                    _buildEmojiReactionButton(context, '💖', 'قلوب'),
                    _buildEmojiReactionButton(context, '🎉', 'احتفال'),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('عدد التفاعلات: ${_getReactionCount(video)}', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );

    if (chosenEmoji != null) {
      _applyReaction(video.id, chosenEmoji);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم التفاعل بـ $chosenEmoji')));
      }
    }
  }

  Widget _buildEmojiReactionButton(BuildContext context, String emoji, String label) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => Navigator.pop(context, emoji),
      child: Container(
        width: 90,
        height: 90,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 12, offset: const Offset(0, 6)),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 34)),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
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
        username: currentUser.username, 
        caption: captionController.text.trim(),
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _uploadProgress = progress);
        },
      );

      if (!mounted) return;
      await _reloadVideos();
      if (!mounted) return;
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

  Future<void> _showShareOptions(BuildContext context, AtyaafVideo video) async {
    final shareText = _buildShareText(video);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Wrap(
              runSpacing: 8,
              children: [
                const Center(
                  child: Text('مشاركة الريل', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 12),
                _buildShareOption(
                  icon: Icons.chat,
                  label: 'واتساب',
                  onTap: () async {
                    Navigator.pop(context);
                    await _shareViaWhatsApp(video);
                  },
                ),
                _buildShareOption(
                  icon: Icons.facebook,
                  label: 'فيسبوك',
                  onTap: () async {
                    Navigator.pop(context);
                    await _shareViaFacebook(video);
                  },
                ),
                _buildShareOption(
                  icon: Icons.alternate_email,
                  label: 'إكس / تويتر',
                  onTap: () async {
                    Navigator.pop(context);
                    await _shareViaTwitter(video);
                  },
                ),
                _buildShareOption(
                  icon: Icons.camera_alt,
                  label: 'إنستجرام',
                  onTap: () async {
                    Navigator.pop(context);
                    await _shareViaInstagram(video);
                  },
                ),
                _buildShareOption(
                  icon: Icons.music_note,
                  label: 'تيك توك',
                  onTap: () async {
                    Navigator.pop(context);
                    await _shareViaTikTok(video);
                  },
                ),
                _buildShareOption(
                  icon: Icons.copy,
                  label: 'نسخ الرابط',
                  onTap: () async {
                    Navigator.pop(context);
                    await Clipboard.setData(ClipboardData(text: video.videoUrl));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ الرابط إلى الحافظة')));
                    }
                  },
                ),
                _buildShareOption(
                  icon: Icons.share,
                  label: 'المزيد من التطبيقات',
                  onTap: () async {
                    Navigator.pop(context);
                    // ignore: deprecated_member_use
                    await Share.share(shareText, subject: _buildShareSubject(video));
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildShareOption({required IconData icon, required String label, required VoidCallback onTap}) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFFE94057)),
      title: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      trailing: const Icon(Icons.keyboard_arrow_left),
      onTap: onTap,
    );
  }

  String _buildShareText(AtyaafVideo video) {
    final title = video.caption.isNotEmpty ? video.caption : video.title;
    return '$title\n${video.videoUrl}\n\nتحميل تطبيق زامل لمزيد من المحتوى.';
  }

  String _buildShareSubject(AtyaafVideo video) {
    return 'شارك مقطع أطياف من زامل';
  }

  Future<bool> _openUrl(Uri uri) async {
    try {
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (error) {
      debugPrint('Unable to open URL $uri: $error');
    }
    return false;
  }

  Future<void> _shareViaWhatsApp(AtyaafVideo video) async {
    final encoded = Uri.encodeComponent(_buildShareText(video));
    final whatsappUri = Uri.parse('https://wa.me/?text=$encoded');
    if (!await _openUrl(whatsappUri)) {
      // ignore: deprecated_member_use
      await Share.share(_buildShareText(video), subject: _buildShareSubject(video));
    }
  }

  Future<void> _shareViaFacebook(AtyaafVideo video) async {
    final encodedUrl = Uri.encodeComponent(video.videoUrl);
    final encodedQuote = Uri.encodeComponent(video.caption.isNotEmpty ? video.caption : video.title);
    final facebookUri = Uri.parse('https://www.facebook.com/sharer/sharer.php?u=$encodedUrl&quote=$encodedQuote');
    if (!await _openUrl(facebookUri)) {
      // ignore: deprecated_member_use
      await Share.share(_buildShareText(video), subject: _buildShareSubject(video));
    }
  }

  Future<void> _shareViaTwitter(AtyaafVideo video) async {
    final encoded = Uri.encodeComponent(_buildShareText(video));
    final twitterUri = Uri.parse('https://twitter.com/intent/tweet?text=$encoded');
    if (!await _openUrl(twitterUri)) {
      // ignore: deprecated_member_use
      await Share.share(_buildShareText(video), subject: _buildShareSubject(video));
    }
  }

  Future<void> _shareViaInstagram(AtyaafVideo video) async {
    const instagramScheme = 'instagram://app';
    final instagramUri = Uri.parse(instagramScheme);
    if (!await _openUrl(instagramUri)) {
      // ignore: deprecated_member_use
      await Share.share(_buildShareText(video), subject: _buildShareSubject(video));
    }
  }

  Future<void> _shareViaTikTok(AtyaafVideo video) async {
    // ignore: deprecated_member_use
    await Share.share(_buildShareText(video), subject: _buildShareSubject(video));
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
                            mainAxisSize: MainAxisSize.min,
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
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -5))],
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
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.05)),
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
                reactionCount: _getReactionCount(video),
                shareCount: _getShareCount(video),
                saveCount: _getSaveCount(video),
                selectedReactionEmoji: _getSelectedReactionEmoji(video),
                onReact: () => _showReactionOptions(context, video),
                onSave: () async {
                  if (authProvider.currentUser == null) return;
                  final wasSaved = provider.isSaved(video.id);
                  await provider.toggleSave(userId: authProvider.currentUser!.id, video: video);
                  await provider.syncSavedVideos(authProvider.currentUser!.id);
                  _updateSaveCount(video.id, !wasSaved);
                },
                onRelatedContent: () async {
                  await provider.openRelatedContent(context, video.relatedContentRef);
                },
                onComment: () => _showCommentsSheet(context, video),
                onShare: () {
                  _incrementShareCount(video.id);
                  _showShareOptions(context, video);
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
                          color: Colors.black.withValues(alpha: 0.5),
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

// تحويل הוويدجت لـ StatefulWidget لمراقبة حالة التشغيل وعرض/إخفاء الفقاعة لحظياً
class _AtyaafVideoCard extends StatefulWidget {
  final AtyaafVideo video;
  final VideoPlayerController? controller;
  final String? initError;
  final bool isPlaying;
  final bool isSaved;
  final int reactionCount;
  final int shareCount;
  final int saveCount;
  final String? selectedReactionEmoji;
  final VoidCallback onReact;
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
    required this.reactionCount,
    required this.shareCount,
    required this.saveCount,
    required this.selectedReactionEmoji,
    required this.onReact,
    required this.onSave,
    required this.onRelatedContent,
    required this.onComment,
    required this.onShare,
    required this.isOwner,
    required this.onDelete,
  });

  @override
  State<_AtyaafVideoCard> createState() => _AtyaafVideoCardState();
}

class _AtyaafVideoCardState extends State<_AtyaafVideoCard> {
  VoidCallback? _listener;

  @override
  void initState() {
    super.initState();
    _setupListener();
  }

  @override
  void didUpdateWidget(covariant _AtyaafVideoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (_listener != null) {
        oldWidget.controller?.removeListener(_listener!);
      }
      _setupListener();
    }
  }

  void _setupListener() {
    _listener = () {
      if (mounted) {
        setState(() {}); // هذا يضمن ظهور واختفاء الفقاعة في نفس اللحظة
      }
    };
    widget.controller?.addListener(_listener!);
  }

  @override
  void dispose() {
    if (_listener != null) {
      widget.controller?.removeListener(_listener!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.initError != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text('عذراً، فشل تحميل الفيديو: ${widget.initError}', style: const TextStyle(color: Colors.redAccent), textAlign: TextAlign.center),
              ),
            )
          else if (widget.controller != null && widget.controller!.value.isInitialized)
            Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  onTap: () {
                    if (widget.controller!.value.isPlaying) {
                      widget.controller!.pause();
                    } else {
                      widget.controller!.play();
                    }
                  },
                  child: SizedBox.expand(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: widget.controller!.value.size.width,
                        height: widget.controller!.value.size.height,
                        child: VideoPlayer(widget.controller!),
                      ),
                    ),
                  ),
                ),
                if (!widget.controller!.value.isPlaying)
                  Positioned.fill(
                    child: Center(
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.play_arrow, color: Colors.white, size: 40),
                      ),
                    ),
                  ),
                // --- الإضافة الجديدة هنا: شريط التقدم (Progress Bar) من دون مسح أي شيء آخر ---
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: VideoProgressIndicator(
                    widget.controller!,
                    allowScrubbing: true,
                    colors: const VideoProgressColors(
                      playedColor: Color(0xFFE94057),
                      bufferedColor: Colors.white24,
                      backgroundColor: Colors.transparent,
                    ),
                  ),
                ),
                // -------------------------------------------------------------------------
              ],
            )
          else
            const Center(child: CircularProgressIndicator(color: Color(0xFFE94057))),
          
          Positioned(
            right: 16,
            bottom: 100,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildActionButtonWithCount(
                  icon: Icons.emoji_emotions_outlined,
                  label: 'تفاعل',
                  count: widget.reactionCount,
                  extraLabel: widget.selectedReactionEmoji,
                  onTap: widget.onReact,
                ),
                const SizedBox(height: 16),
                _buildActionButtonWithCount(
                  icon: widget.isSaved ? Icons.bookmark : Icons.bookmark_border,
                  label: 'حفظ',
                  count: widget.saveCount,
                  active: widget.isSaved,
                  onTap: widget.onSave,
                ),
                const SizedBox(height: 16),
                _buildActionButton(Icons.comment, widget.onComment),
                const SizedBox(height: 16),
                _buildActionButtonWithCount(
                  icon: Icons.share,
                  label: 'مشاركة',
                  count: widget.shareCount,
                  onTap: widget.onShare,
                ),
                if (widget.isOwner) ...[
                  const SizedBox(height: 16),
                  _buildActionButton(Icons.delete, widget.onDelete, color: Colors.redAccent),
                ],
              ],
            ),
          ),
          Positioned(
            left: 16,
            bottom: 40,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('@${widget.video.username}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                // ignore: unnecessary_null_comparison, unnecessary_non_null_assertion
                if (widget.video.caption != null && widget.video.caption!.isNotEmpty)
                  SizedBox(
                    width: MediaQuery.of(context).size.width * 0.6,
                    child: Text(widget.video.caption!, style: const TextStyle(color: Colors.white), maxLines: 2, overflow: TextOverflow.ellipsis),
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 32),
        ],
      ),
    );
  }

  Widget _buildActionButtonWithCount({
    required IconData icon,
    required String label,
    required int count,
    required VoidCallback onTap,
    String? extraLabel,
    bool active = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: active ? const Color(0xFFE94057) : Colors.black.withValues(alpha: 0.55),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
          const SizedBox(height: 4),
          Text('$count', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          if (extraLabel != null)
            Text(extraLabel, style: const TextStyle(color: Colors.amber, fontSize: 12)),
        ],
      ),
    );
  }
}
