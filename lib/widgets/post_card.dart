import 'dart:async'; // تم إضافتها لعداد تسجيل الصوت
import 'dart:ui';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/comment.dart';
import '../models/post.dart';
import '../providers/auth_provider.dart';
import '../screens/post_detail_screen.dart';
import '../screens/profile_screen.dart';
import '../services/audio_service.dart';
import '../services/comment_service.dart';
import '../services/local_preferences_service.dart';
import '../services/post_service.dart';

class PostCard extends StatefulWidget {
  final Post post;

  const PostCard({super.key, required this.post});

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> with SingleTickerProviderStateMixin {
  bool _isSaved = false;
  final AudioCommentService _audioCommentService = AudioCommentService();
  String? _activeAudioUrl;
  bool _isAudioPlaying = false;
  Duration _audioPosition = Duration.zero;
  late final StreamSubscription<Duration> _audioPositionSub;
  late final StreamSubscription<PlayerState> _audioStateSub;
  
  static const Map<String, Map<String, dynamic>> _zamelReactions = {
    'like': {'emoji': '👍', 'label': 'أوافق', 'color': Color(0xFF5B6CFF)},
    'love': {'emoji': '❤️', 'label': 'أبدعت', 'color': Color(0xFFE94057)},
    'haha': {'emoji': '😂', 'label': 'ضحكتني', 'color': Color(0xFFF2C94C)},
    'spot_on': {'emoji': '🎯', 'label': 'في الصميم', 'color': Color(0xFF2EC7A5)},
    'support': {'emoji': '🤝', 'label': 'دعم', 'color': Color(0xFF8A2387)},
  };

  @override
  void initState() {
    super.initState();
    _audioPositionSub = _audioCommentService.positionStream.listen((position) {
      if (mounted) {
        setState(() => _audioPosition = position);
      }
    });
    _audioStateSub = _audioCommentService.playerStateStream.listen((state) {
      if (!mounted) return;
      if (state == PlayerState.completed || state == PlayerState.stopped || state == PlayerState.paused) {
        setState(() {
          _isAudioPlaying = false;
          if (state == PlayerState.completed) {
            _audioPosition = Duration.zero;
          }
        });
      } else if (state == PlayerState.playing) {
        setState(() => _isAudioPlaying = true);
      }
    });
    _loadSavedState();
  }

  Future<void> _loadSavedState() async {
    final saved = await LocalPreferencesService.isPostSaved(widget.post.id);
    if (mounted) setState(() => _isSaved = saved);
  }

  Future<void> _toggleSave() async {
    await LocalPreferencesService.toggleSavedPost(widget.post.id);
    if (mounted) setState(() => _isSaved = !_isSaved);
  }

  Future<void> _toggleAudioPlayback(Comment comment) async {
    if (comment.audioUrl.isEmpty) return;

    if (_activeAudioUrl == comment.audioUrl && _isAudioPlaying) {
      await _audioCommentService.pause();
      if (mounted) setState(() => _isAudioPlaying = false);
      return;
    }

    await _audioCommentService.stop();
    await _audioCommentService.play(comment.audioUrl);
    if (mounted) {
      setState(() {
        _activeAudioUrl = comment.audioUrl;
        _audioPosition = Duration.zero;
        _isAudioPlaying = true;
      });
    }
  }

  Future<void> _handleReaction(String userId, String reactionType) async {
    setState(() {
      if (reactionType == 'none') {
        widget.post.reactions.remove(userId);
      } else {
        widget.post.reactions[userId] = reactionType;
      }
    });
    
    try {
      await PostService.addReaction(
        postId: widget.post.id, 
        userId: userId, 
        reactionType: reactionType
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فشل تسجيل التفاعل')));
      }
    }
  }

  void _showZamelReactions(BuildContext context, String userId) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, anim1, anim2) {
        return Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            margin: const EdgeInsets.only(bottom: 120, left: 20, right: 20),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(40),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 10))
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                mainAxisSize: MainAxisSize.min,
                children: _zamelReactions.entries.map((entry) {
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      _handleReaction(userId, entry.key);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(entry.value['emoji'], style: const TextStyle(fontSize: 32)),
                          const SizedBox(height: 4),
                          Text(
                            entry.value['label'], 
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: entry.value['color'])
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
        return Transform.scale(
          scale: anim1.value,
          child: Opacity(opacity: anim1.value, child: child),
        );
      },
    );
  }

  Widget _buildReactionsSummary(String currentUserId) {
    final validReactions = widget.post.reactions.values.where((r) => r != 'none').toList();
    if (validReactions.isEmpty) return const SizedBox.shrink();

    final uniqueEmojis = validReactions
        .map((r) => _zamelReactions[r]?['emoji'])
        .where((e) => e != null)
        .toSet()
        .take(3)
        .toList();

    bool iReacted = widget.post.reactions.containsKey(currentUserId) && widget.post.reactions[currentUserId] != 'none';
    int count = validReactions.length;

    String text = '';
    if (iReacted && count == 1) text = 'أنت تفاعلت';
    else if (iReacted && count > 1) text = 'أنت و ${count - 1} آخرين';
    else text = '$count تفاعل';

    return Row(
      children: [
        Row(
          children: uniqueEmojis.map((e) => Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text(e.toString(), style: const TextStyle(fontSize: 16)),
          )).toList(),
        ),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = context.watch<AuthProvider>().currentUser;
    final String currentUserId = currentUser?.id ?? '';
    
    String? myReaction;
    if (widget.post.reactions.containsKey(currentUserId) && widget.post.reactions[currentUserId] != 'none') {
      myReaction = widget.post.reactions[currentUserId];
    }

    final reactionData = myReaction != null && _zamelReactions.containsKey(myReaction) 
        ? _zamelReactions[myReaction]! 
        : null;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PostDetailScreen(postId: widget.post.id))),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 6)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // --- رأس المنشور ---
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: const Color(0xFF5B6CFF),
                    child: Text(
                      widget.post.username.isNotEmpty ? widget.post.username[0].toUpperCase() : 'م',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        GestureDetector(
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(userId: widget.post.userId))),
                          child: Text(widget.post.username, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        ),
                        if (widget.post.location.isNotEmpty)
                          Row(
                            children: [
                              const Icon(Icons.location_on, size: 12, color: Color(0xFF2EC7A5)),
                              const SizedBox(width: 2),
                              Text(widget.post.location, style: const TextStyle(color: Color(0xFF2EC7A5), fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        Text(_formatTimestamp(widget.post.timestamp), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  ),
                  Icon(
                    widget.post.privacy == 'private' ? Icons.lock : 
                    widget.post.privacy == 'friends' ? Icons.group : Icons.public,
                    size: 16, color: Colors.grey,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              Text(widget.post.text, style: const TextStyle(fontSize: 15, height: 1.5, color: Color(0xFF2F2F2F))),
              
              if (widget.post.mediaType == 'image' && widget.post.mediaData.isNotEmpty) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.network(
                    widget.post.mediaData,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    loadingBuilder: (ctx, child, progress) => progress == null ? child : Container(height: 200, color: Colors.grey[100], child: const Center(child: CircularProgressIndicator())),
                    errorBuilder: (ctx, err, stack) => Container(height: 200, color: Colors.grey[100], child: const Center(child: Icon(Icons.broken_image, size: 50, color: Colors.grey))),
                  ),
                ),
              ],
              
              if (widget.post.mediaType == 'video' && widget.post.mediaData.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  height: 220,
                  decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(18)),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const Positioned(bottom: 12, left: 12, child: Text('مقطع فيديو', style: TextStyle(color: Colors.white70, fontSize: 12))),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                        child: const Icon(Icons.play_arrow_rounded, size: 50, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildReactionsSummary(currentUserId),
                  Text('${widget.post.commentsCount} تعليق', style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              Container(height: 1, color: Colors.grey.shade200),
              const SizedBox(height: 4),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Expanded(
                    child: GestureDetector(
                      onLongPress: () => currentUser != null ? _showZamelReactions(context, currentUserId) : null,
                      onTap: () {
                        if (currentUser == null) return;
                        if (myReaction != null) {
                          _handleReaction(currentUserId, 'none'); 
                        } else {
                          _handleReaction(currentUserId, 'like'); 
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        color: Colors.transparent,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(reactionData?['emoji'] ?? '🤍', style: const TextStyle(fontSize: 20)),
                            const SizedBox(width: 6),
                            Text(
                              reactionData?['label'] ?? 'أوافق',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: reactionData?['color'] ?? Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: currentUser == null ? null : _showComments,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.chat_bubble_outline_rounded, color: Colors.grey[600], size: 20),
                            const SizedBox(width: 6),
                            Text('تعليق', style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: currentUser == null ? null : _toggleSave,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(_isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, color: _isSaved ? const Color(0xFF2EC7A5) : Colors.grey[600], size: 20),
                            const SizedBox(width: 6),
                            Text('حفظ', style: TextStyle(color: _isSaved ? const Color(0xFF2EC7A5) : Colors.grey[600], fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              
              if (widget.post.hashtags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 8,
                    children: widget.post.hashtags.map((tag) => Chip(
                      label: Text('#$tag', style: const TextStyle(fontSize: 12, color: Color(0xFF5B6CFF))),
                      backgroundColor: const Color(0xFF5B6CFF).withOpacity(0.1),
                      visualDensity: VisualDensity.compact,
                    )).toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // --- دالة التعليقات مع نظام التسجيل الصوتي المدمج (بصمة زامل) ---
  void _showComments() {
    final currentUser = context.read<AuthProvider>().currentUser;
    if (currentUser == null) return;

    final audioService = _audioCommentService;
    Timer? recordTimer; // العداد

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final commentController = TextEditingController();
        bool isTyping = false;
        bool isRecording = false;
        int recordingSeconds = 0;

        return StatefulBuilder(
          builder: (BuildContext ctx, StateSetter setModalState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 12),
                    Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(child: Text('التعليقات', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
                          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.55,
                      child: StreamBuilder<List<Comment>>(
                        stream: CommentService().commentsStream(widget.post.id),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xFF5B6CFF)));
                          final comments = snapshot.data ?? [];
                          if (comments.isEmpty) return const Center(child: Text('لا توجد تعليقات بعد. كن أول متفاعل!', style: TextStyle(color: Colors.grey)));
                          return ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: comments.length,
                            itemBuilder: (context, index) {
                              final comment = comments[index];
                              final isAudio = comment.type == 'audio' || comment.audioUrl.isNotEmpty || comment.text.startsWith('[AUDIO]');
                              
                              return Card(
                                elevation: 0,
                                color: Colors.grey[50],
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    radius: 16,
                                    backgroundColor: const Color(0xFF5B6CFF).withOpacity(0.2),
                                    child: Text(comment.username[0].toUpperCase(), style: const TextStyle(color: Color(0xFF5B6CFF), fontSize: 14, fontWeight: FontWeight.bold)),
                                  ),
                                  title: GestureDetector(
                                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(userId: comment.userId))),
                                    child: Text(comment.username, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 4),
                                      if (isAudio)
                                        InkWell(
                                          onTap: () async {
                                            try {
                                              await _toggleAudioPlayback(comment);
                                            } catch (_) {
                                              if (mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر تشغيل الصوت')));
                                              }
                                            }
                                          },
                                          child: Container(
                                            margin: const EdgeInsets.only(top: 4, bottom: 4),
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF5B6CFF).withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      _activeAudioUrl == comment.audioUrl && _isAudioPlaying
                                                          ? Icons.pause_circle_filled
                                                          : Icons.play_circle_fill,
                                                      color: const Color(0xFF5B6CFF),
                                                      size: 30,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: ClipRRect(
                                                        borderRadius: BorderRadius.circular(999),
                                                        child: LinearProgressIndicator(
                                                          value: _activeAudioUrl == comment.audioUrl
                                                              ? (_audioPosition.inMilliseconds / (comment.duration > 0 ? comment.duration * 1000 : 30000)).clamp(0.0, 1.0)
                                                              : 0.0,
                                                          minHeight: 6,
                                                          backgroundColor: Colors.white,
                                                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF5B6CFF)),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  _activeAudioUrl == comment.audioUrl
                                                      ? '${_formatDuration(_audioPosition)} / ${_formatDuration(Duration(seconds: comment.duration > 0 ? comment.duration : 30))}'
                                                      : (comment.duration > 0 ? '0:00 / ${_formatDuration(Duration(seconds: comment.duration))}' : '0:00 / 0:30'),
                                                  style: const TextStyle(color: Color(0xFF5B6CFF), fontWeight: FontWeight.bold, fontSize: 12),
                                                ),
                                              ],
                                            ),
                                          ),
                                        )
                                      else
                                        Text(comment.text, style: const TextStyle(color: Colors.black87)),
                                      const SizedBox(height: 4),
                                      Text(_formatCommentTime(comment.timestamp), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                    
                    // --- منطقة إدخال التعليق (المايك والنص) ---
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))],
                      ),
                      child: isRecording
                          ? Row(
                              children: [
                                const Icon(Icons.mic, color: Colors.redAccent, size: 28),
                                const SizedBox(width: 12),
                                Text(
                                  'جاري التسجيل... 00:0$recordingSeconds',
                                  style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                                const Spacer(),
                                const Text('اسحب للإلغاء', style: TextStyle(color: Colors.grey, fontSize: 12)),
                              ],
                            )
                          : Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: commentController,
                                    onChanged: (val) {
                                      setModalState(() => isTyping = val.trim().isNotEmpty);
                                    },
                                    decoration: InputDecoration(
                                      hintText: 'أضف تعليقاً كـ ${currentUser.username}...',
                                      filled: true,
                                      fillColor: Colors.grey[100],
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                
                                // زر المايك / الإرسال التفاعلي
                                GestureDetector(
                                  onLongPress: isTyping ? null : () async {
                                    final canRecord = await audioService.checkPermission();
                                    if (!canRecord) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الاذن للمكروفون مطلوب للتسجيل')));
                                      }
                                      return;
                                    }

                                    setModalState(() {
                                      isRecording = true;
                                      recordingSeconds = 0;
                                    });
                                    await audioService.startRecording();
                                    recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
                                      setModalState(() => recordingSeconds++);
                                    });
                                  },
                                  onLongPressEnd: isTyping ? null : (details) async {
                                    recordTimer?.cancel();
                                    setModalState(() => isRecording = false);

                                    final audioPath = await audioService.stopRecording();
                                    if (audioPath == null || audioPath.isEmpty) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فشل تسجيل الصوت')));
                                      }
                                      return;
                                    }

                                    try {
                                      final uploadResult = await audioService.uploadAudioFile(audioPath);
                                      if (uploadResult == null || uploadResult['url'] == null) {
                                        throw Exception('فشل الرفع');
                                      }

                                      await CommentService().addComment(
                                        postId: widget.post.id,
                                        userId: currentUser.id,
                                        username: currentUser.username,
                                        text: '[AUDIO]',
                                        audioUrl: uploadResult['url'],
                                        type: 'audio',
                                        duration: audioService.durationSeconds,
                                      );
                                    } catch (_) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فشل إرسال الصوت')));
                                      }
                                    }
                                  },
                                  onTap: () async {
                                    if (isTyping) {
                                      final text = commentController.text.trim();
                                      if (text.isEmpty) return;
                                      await CommentService().addComment(
                                        postId: widget.post.id,
                                        userId: currentUser.id,
                                        username: currentUser.username,
                                        text: text,
                                      );
                                      commentController.clear();
                                      setModalState(() => isTyping = false);
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اضغط مطولاً لتسجيل رسالة صوتية')));
                                    }
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: isTyping ? const Color(0xFF5B6CFF) : const Color(0xFF2EC7A5),
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: (isTyping ? const Color(0xFF5B6CFF) : const Color(0xFF2EC7A5)).withOpacity(0.3),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3)
                                        )
                                      ]
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
    ).then((_) {
      // إيقاف العداد عند قفل شاشة التعليقات
      recordTimer?.cancel();
    });
  }

  @override
  void dispose() {
    _audioPositionSub.cancel();
    _audioStateSub.cancel();
    _audioCommentService.dispose();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _formatCommentTime(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inHours < 1) return '${diff.inMinutes} د';
    if (diff.inDays < 1) return '${diff.inHours} س';
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatTimestamp(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inHours < 1) return '${diff.inMinutes} د';
    if (diff.inDays < 1) return '${diff.inHours} س';
    if (diff.inDays < 7) return '${diff.inDays} ي';
    return '${date.day}/${date.month}/${date.year}';
  }
}
