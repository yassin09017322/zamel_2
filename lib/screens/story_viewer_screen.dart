import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../models/story.dart';
import '../providers/auth_provider.dart';
import '../services/story_service.dart';
import 'profile_screen.dart';

String _buildStoryVideoUrl(String url) {
  if (url.isEmpty) return url;
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.path.contains('/upload/')) return url;

  final path = uri.path.replaceFirst('/upload/', '/upload/q_auto,f_mp4,vc_h264,ac_aac,');
  return uri.replace(path: path).toString();
}

class StoryViewerScreen extends StatefulWidget {
  final List<Story> stories;
  final int initialIndex;
  final bool isOwner;
  final void Function(String userId)? onHideStoryUser;

  const StoryViewerScreen({
    super.key,
    required this.stories,
    this.initialIndex = 0,
    this.isOwner = false,
    this.onHideStoryUser,
  });

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen> with SingleTickerProviderStateMixin {
  late final PageController _pageController;
  late int _currentIndex;
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _showControls = false;
  bool _isPaused = false;
  String? _profileImageUrl;
  String _profileName = '';
  late final AnimationController _progressController;
  final TextEditingController _replyController = TextEditingController();
  final List<String> _quickReactions = ['❤️', '🔥', '👏', '🎉'];
  final StoryService _storyService = StoryService();
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _storyDocSub;
  List<Map<String, dynamic>>? _liveViewers;
  List<Map<String, dynamic>>? _liveReactions;
  

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _progressController = AnimationController(vsync: this, duration: const Duration(seconds: 5));
    unawaited(_recordView());
    _subscribeToCurrentStoryDoc();
    _progressController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _goToNextStory();
      }
    });
    _loadCurrentStory();
  }

  Future<void> _loadProfileInfoForCurrentStory() async {
    final story = widget.stories[_currentIndex];
    if (story.userId.isEmpty) return;

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(story.userId).get();
      if (!mounted || !doc.exists) {
        if (mounted) {
          setState(() {
            _profileName = story.username;
            _profileImageUrl = null;
          });
        }
        return;
      }

      final data = doc.data();
      final photoUrl = (data?['photoURL'] as String?)?.trim();
      final username = (data?['username'] as String?)?.trim();

      if (mounted) {
        setState(() {
          _profileImageUrl = photoUrl != null && photoUrl.isNotEmpty ? photoUrl : null;
          _profileName = username != null && username.isNotEmpty ? username : story.username;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _profileName = story.username;
          _profileImageUrl = null;
        });
      }
    }
  }

  @override
  void dispose() {
    _storyDocSub?.cancel();
    _progressController.dispose();
    _replyController.dispose();
    _videoController?.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentStory() async {
    final story = widget.stories[_currentIndex];
    if (story.mediaType == 'video') {
      _videoController?.dispose();
      _videoController = VideoPlayerController.network(_buildStoryVideoUrl(story.imageUrl));
      try {
        await _videoController!.initialize();
        _videoController!
          ..setLooping(true)
          ..play();
        if (mounted) {
          setState(() => _isVideoInitialized = true);
        }
      } catch (error) {
        debugPrint('Story video initialization failed: $error');
        if (mounted) {
          setState(() => _isVideoInitialized = false);
        }
      }
    } else {
      _videoController?.dispose();
      _videoController = null;
      _isVideoInitialized = false;
    }

    if (mounted) {
      _progressController.reset();
      _progressController.forward();
      _isPaused = false;
      setState(() {});
    }

    unawaited(_loadProfileInfoForCurrentStory());
    _subscribeToCurrentStoryDoc();
    unawaited(_recordView());
  }

  void _subscribeToCurrentStoryDoc() {
    _storyDocSub?.cancel();
    final story = widget.stories[_currentIndex];
    if (story.id.isEmpty) return;
    try {
      _storyDocSub = FirebaseFirestore.instance.collection('stories').doc(story.id).snapshots().listen((doc) {
        if (!mounted) return;
        final data = doc.data();
        setState(() {
          _liveViewers = (data?['viewers'] as List<dynamic>?)?.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList() ?? [];
          _liveReactions = (data?['reactions'] as List<dynamic>?)?.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList() ?? [];
        });
      });
    } catch (_) {}
  }

  Future<void> _recordView() async {
    final story = widget.stories[_currentIndex];
    final auth = Provider.of<AuthProvider>(context, listen: false).currentUser;
    if (auth == null) return;
    await _storyService.addViewer(storyId: story.id, userId: auth.id, username: auth.username);
  }

  Future<void> _sendReaction(String emoji) async {
    final story = widget.stories[_currentIndex];
    final auth = Provider.of<AuthProvider>(context, listen: false).currentUser;
    if (auth == null) return;
    await _storyService.addReaction(storyId: story.id, userId: auth.id, username: auth.username, emoji: emoji);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم إرسال $emoji')));
    }
  }

  Future<void> _sendReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty) return;
    final story = widget.stories[_currentIndex];
    final auth = Provider.of<AuthProvider>(context, listen: false).currentUser;
    if (auth == null) return;
    await _storyService.addReply(storyId: story.id, userId: auth.id, username: auth.username, text: text);
    if (mounted) {
      _replyController.clear();
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال الرسالة')));
    }
  }

  void _goToNextStory() {
    if (_currentIndex < widget.stories.length - 1) {
      setState(() => _currentIndex += 1);
      _pageController.animateToPage(_currentIndex, duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
      _loadCurrentStory();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _goToPreviousStory() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex -= 1);
      _pageController.animateToPage(_currentIndex, duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
      _loadCurrentStory();
    }
  }

  void _togglePause() {
    if (_isPaused) {
      _progressController.forward();
    } else {
      _progressController.stop();
    }
    setState(() => _isPaused = !_isPaused);
  }

  Future<void> _openCurrentProfile() async {
    final story = widget.stories[_currentIndex];
    if (story.userId.isEmpty) return;

    if (_videoController != null && _videoController!.value.isInitialized && _videoController!.value.isPlaying) {
      await _videoController!.pause();
    }
    if (_progressController.isAnimating) {
      _progressController.stop();
    }

    if (mounted) {
      setState(() => _isPaused = true);
    }

    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(userId: story.userId)));

    if (mounted) {
      setState(() => _isPaused = false);
      if (_videoController != null && _videoController!.value.isInitialized && !_videoController!.value.isPlaying) {
        unawaited(_videoController!.play());
      }
      if (_progressController.isAnimating == false) {
        _progressController.forward(from: _progressController.value);
      }
    }
  }

  Future<void> _handleShare() async {
    final story = widget.stories[_currentIndex];
    await Share.share('شاهد هذه القصة: ${story.imageUrl}');
  }

  Future<void> _handleDelete() async {
    final story = widget.stories[_currentIndex];
    await _storyService.deleteStory(story.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final story = widget.stories[_currentIndex];
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            GestureDetector(
              onTapUp: (details) {
                final screenWidth = MediaQuery.of(context).size.width;
                final dx = details.localPosition.dx;
                if (dx < screenWidth * 0.25) {
                  _goToPreviousStory();
                } else if (dx > screenWidth * 0.75) {
                  _goToNextStory();
                } else {
                  setState(() => _showControls = !_showControls);
                }
              },
              onLongPress: _togglePause,
              child: PageView.builder(
                controller: _pageController,
                itemCount: widget.stories.length,
                onPageChanged: (index) {
                  setState(() => _currentIndex = index);
                  _loadCurrentStory();
                },
                itemBuilder: (context, index) {
                  final item = widget.stories[index];
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: item.mediaType == 'video'
                            ? (_isVideoInitialized && index == _currentIndex ? _buildVideoPlayer() : const Center(child: CircularProgressIndicator(color: Colors.white)))
                            : Image.network(item.imageUrl, fit: BoxFit.cover, width: double.infinity),
                      ),
                      Positioned(
                        top: 12,
                        left: 12,
                        right: 12,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onTap: _openCurrentProfile,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundColor: Colors.white24,
                                      backgroundImage: _profileImageUrl != null ? NetworkImage(_profileImageUrl!) : null,
                                      child: _profileImageUrl == null
                                          ? Text(
                                              (_profileName.isNotEmpty ? _profileName[0] : 'م').toUpperCase(),
                                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                            )
                                          : null,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _profileName.isNotEmpty ? _profileName : item.username,
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(width: 6),
                                    const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 14),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: List.generate(widget.stories.length, (i) {
                                final active = i == index;
                                return Expanded(
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 2),
                                    height: 3,
                                    decoration: BoxDecoration(
                                      color: active ? Colors.white : Colors.white38,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        top: 16,
                        right: 16,
                        child: Row(
                          children: [
                            if (widget.isOwner)
                              PopupMenuButton<String>(
                                color: Colors.white,
                                onSelected: (value) async {
                                  if (value == 'delete') {
                                    await _handleDelete();
                                  } else if (value == 'share') {
                                    await _handleShare();
                                  } else if (value == 'viewers') {
                                    // Show viewers list modal
                                    final viewers = _liveViewers ?? widget.stories[_currentIndex].viewers;
                                    await showModalBottomSheet(
                                      context: context,
                                      isScrollControlled: true,
                                      builder: (ctx) => SafeArea(
                                        child: Padding(
                                          padding: const EdgeInsets.all(12.0),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Container(width: 44, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(999))),
                                              const SizedBox(height: 12),
                                              Text('مشاهدو القصة', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                                              const SizedBox(height: 12),
                                              if (viewers.isEmpty)
                                                const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Text('لا يوجد مشاهدون بعد'))
                                              else
                                                SizedBox(
                                                  height: MediaQuery.of(ctx).size.height * 0.56,
                                                  child: ListView.separated(
                                                    shrinkWrap: true,
                                                    itemCount: viewers.length,
                                                    separatorBuilder: (_, __) => const Divider(height: 1),
                                                    itemBuilder: (context, i) {
                                                      final v = Map<String, dynamic>.from(viewers[i]);
                                                      return ListTile(
                                                        leading: CircleAvatar(child: Text((v['username'] as String?)?.substring(0, 1).toUpperCase() ?? '?')),
                                                        title: Text(v['username'] ?? 'مستخدم'),
                                                        subtitle: v['timestamp'] != null ? Text(v['timestamp'].toString()) : null,
                                                      );
                                                    },
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                },
                                itemBuilder: (context) => const [
                                  PopupMenuItem(value: 'delete', child: Text('حذف القصة')),
                                  PopupMenuItem(value: 'share', child: Text('مشاركة القصة')),
                                  PopupMenuItem(value: 'viewers', child: Text('عرض المشاهدين')),
                                  PopupMenuItem(value: 'add', child: Text('إضافة قصة جديدة')),
                                ],
                              ),
                            if (!widget.isOwner)
                              PopupMenuButton<String>(
                                color: Colors.white,
                                onSelected: (value) async {
                                  if (value == 'share') {
                                    await _handleShare();
                                  } else if (value == 'hide') {
                                    widget.onHideStoryUser?.call(story.userId);
                                    if (mounted) {
                                      Navigator.of(context).pop();
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إخفاء قصص هذا المستخدم')));
                                    }
                                  }
                                },
                                itemBuilder: (context) => const [
                                  PopupMenuItem(value: 'share', child: Text('مشاركة القصة')),
                                  PopupMenuItem(value: 'hide', child: Text('إخفاء قصص هذا المستخدم')),
                                ],
                              ),
                          ],
                        ),
                      ),
                      Positioned(
                        top: 16,
                        left: 16,
                        child: Row(
                          children: [
                            GestureDetector(
                              onTap: () async {
                                // show viewers list
                                final viewers = _liveViewers ?? widget.stories[_currentIndex].viewers;
                                await showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  builder: (ctx) => SafeArea(
                                    child: Padding(
                                      padding: const EdgeInsets.all(12.0),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(width: 44, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(999))),
                                          const SizedBox(height: 12),
                                          Text('مشاهدو القصة', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                                          const SizedBox(height: 12),
                                          if (viewers.isEmpty)
                                            const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Text('لا يوجد مشاهدون بعد'))
                                          else
                                            SizedBox(
                                              height: MediaQuery.of(ctx).size.height * 0.56,
                                              child: ListView.separated(
                                                shrinkWrap: true,
                                                itemCount: viewers.length,
                                                separatorBuilder: (_, __) => const Divider(height: 1),
                                                itemBuilder: (context, i) {
                                                  final v = Map<String, dynamic>.from(viewers[i]);
                                                  return ListTile(
                                                    leading: CircleAvatar(child: Text((v['username'] as String?)?.substring(0, 1).toUpperCase() ?? '?')),
                                                    title: Text(v['username'] ?? 'مستخدم'),
                                                    subtitle: v['timestamp'] != null ? Text(v['timestamp'].toString()) : null,
                                                  );
                                                },
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                                child: Row(
                                  children: [
                                    const Icon(Icons.visibility, color: Colors.white, size: 16),
                                    const SizedBox(width: 6),
                                    Text('${_liveViewers?.length ?? story.viewers.length}', style: const TextStyle(color: Colors.white)),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () async {
                                // show reactions list
                                final reactions = _liveReactions ?? widget.stories[_currentIndex].reactions;
                                await showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  builder: (ctx) => SafeArea(
                                    child: Padding(
                                      padding: const EdgeInsets.all(12.0),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(width: 44, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(999))),
                                          const SizedBox(height: 12),
                                          Text('تفاعلات القصة', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                                          const SizedBox(height: 12),
                                          if (reactions.isEmpty)
                                            const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Text('لا توجد تفاعلات بعد'))
                                          else
                                            Flexible(
                                              child: ListView.separated(
                                                shrinkWrap: true,
                                                itemCount: reactions.length,
                                                separatorBuilder: (_, __) => const Divider(height: 1),
                                                itemBuilder: (context, i) {
                                                  final r = Map<String, dynamic>.from(reactions[i]);
                                                  return ListTile(
                                                    leading: CircleAvatar(child: Text((r['username'] as String?)?.substring(0, 1).toUpperCase() ?? '?')),
                                                    title: Text(r['username'] ?? 'مستخدم'),
                                                    subtitle: Text(r['emoji'] ?? ''),
                                                    trailing: r['timestamp'] != null ? Text((r['timestamp'] as String).split('T').first) : null,
                                                  );
                                                },
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                                child: Row(
                                  children: [
                                    const Icon(Icons.emoji_emotions, color: Colors.white, size: 16),
                                    const SizedBox(width: 6),
                                    Text('${_liveReactions?.length ?? story.reactions.length}', style: const TextStyle(color: Colors.white)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        bottom: 110,
                        left: 16,
                        right: 16,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(story.username, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              children: _quickReactions.map((emoji) => GestureDetector(
                                onTap: () => _sendReaction(emoji),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(18)),
                                  child: Text(emoji, style: const TextStyle(fontSize: 20)),
                                ),
                              )).toList(),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                          color: Colors.black54,
                          child: Column(
                            children: [
                              if (_showControls)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: TextField(
                                    controller: _replyController,
                                    style: const TextStyle(color: Colors.white),
                                    decoration: InputDecoration(
                                      hintText: 'اكتب رسالة أو اسأل سؤالاً',
                                      hintStyle: const TextStyle(color: Colors.white70),
                                      filled: true,
                                      fillColor: Colors.white12,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                                      suffixIcon: IconButton(
                                        icon: const Icon(Icons.send, color: Colors.white),
                                        onPressed: _sendReply,
                                      ),
                                    ),
                                  ),
                                ),
                              Row(
                                children: [
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () => setState(() => _showControls = !_showControls),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 10),
                                        decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(18)),
                                        child: const Center(child: Text('تفاعل', style: TextStyle(color: Colors.white))),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () => setState(() => _showControls = true),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 10),
                                        decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(18)),
                                        child: const Center(child: Text('اسألني سؤالاً', style: TextStyle(color: Colors.white))),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Positioned(
              top: 60,
              left: 0,
              right: 0,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _showControls
                    ? Container(
                        key: const ValueKey('controls'),
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(16)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white), onPressed: _goToPreviousStory),
                            IconButton(icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause, color: Colors.white), onPressed: _togglePause),
                            IconButton(icon: const Icon(Icons.arrow_forward_ios, color: Colors.white), onPressed: _goToNextStory),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(key: ValueKey('empty')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPlayer() {
    if (!_isVideoInitialized || _videoController == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    return Stack(
      alignment: Alignment.center,
      children: [
        AspectRatio(aspectRatio: _videoController!.value.aspectRatio, child: VideoPlayer(_videoController!)),
        if (_showControls)
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.black54,
            child: IconButton(
              icon: Icon(_videoController!.value.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 32),
              onPressed: _toggleVideoPlayback,
            ),
          ),
      ],
    );
  }

  void _toggleVideoPlayback() {
    if (_videoController == null) return;
    setState(() {
      if (_videoController!.value.isPlaying) {
        _videoController!.pause();
      } else {
        _videoController!.play();
      }
    });
  }
}

