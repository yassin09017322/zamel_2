import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart'; // من أجل XFile

import '../models/post.dart';
import '../models/comment.dart';
import '../providers/auth_provider.dart';
import '../screens/profile_screen.dart';
import '../services/comment_service.dart';
import '../services/post_service.dart';
import '../services/audio_service.dart';
import '../services/media_service.dart';
import '../widgets/comment_section.dart';
import '../widgets/media_preview.dart';

class PostDetailScreen extends StatefulWidget {
  final String postId;

  const PostDetailScreen({super.key, required this.postId});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final TextEditingController _commentController = TextEditingController();
  final CommentService _commentService = CommentService();
  final AudioCommentService _audioService = AudioCommentService();
  final MediaService _mediaService = MediaService();

  bool _isTyping = false;
  bool _isRecording = false;
  int _recordingSeconds = 0;
  Timer? _recordTimer;
  bool _isCanceling = false;

  String? _replyToCommentId;
  String? _replyToUserId;
  String? _replyToUsername;

  @override
  void dispose() {
    _commentController.dispose();
    _audioService.dispose();
    _recordTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = context.watch<AuthProvider>().currentUser;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تفاصيل المنشور'),
          backgroundColor: Colors.white,
          elevation: 0,
        ),
        body: StreamBuilder<Post?>(
          stream: PostService.postStream(widget.postId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('فشل تحميل المنشور: ${snapshot.error}'));
            }
            final post = snapshot.data;
            if (post == null) {
              return const Center(child: Text('لم يتم العثور على المنشور.'));
            }

            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                    children: [
                      _buildPostCard(post),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(Icons.chat_bubble_outline_rounded, color: Theme.of(context).colorScheme.primary, size: 20),
                          const SizedBox(width: 8),
                          const Text('التعليقات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      
                      if (_replyToUsername != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            children: [
                              Expanded(child: Text('رد على $_replyToUsername', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF5B6CFF)))),
                              GestureDetector(
                                onTap: () => setState(() {
                                  _replyToCommentId = null;
                                  _replyToUserId = null;
                                  _replyToUsername = null;
                                }),
                                child: const Icon(Icons.close, size: 18, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),

                      StreamBuilder<List<Comment>>(
                        stream: _commentService.commentsStream(post.id),
                        builder: (context, commentsSnapshot) {
                          if (commentsSnapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final comments = commentsSnapshot.data ?? [];
                          if (comments.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: Text('لا توجد تعليقات بعد. كن أول من يعلق!'),
                            );
                          }
                          return CommentSection(
                            comments: comments,
                            onReply: (comment) {
                              setState(() {
                                _replyToCommentId = comment.id;
                                _replyToUserId = comment.userId;
                                _replyToUsername = comment.username;
                              });
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
                if (currentUser != null) _buildInteractiveCommentInput(currentUser.username, currentUser.id, post.id),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildPostCard(Post post) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 6)),
        ],
      ),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFF5B6CFF),
                child: Text(post.username.isNotEmpty ? post.username[0].toUpperCase() : 'م', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(userId: post.userId))),
                      child: Text(post.username, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                    Text(_formatTimestamp(post.timestamp), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(post.text, style: const TextStyle(fontSize: 15, height: 1.5, color: Color(0xFF2F2F2F))),
          if (post.mediaFiles.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...post.mediaFiles.map((media) {
              if (media.mediaType == 'video') {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: MediaPreview(mediaPath: media.url, mediaType: 'video'),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: MediaPreview(mediaPath: media.url, mediaType: 'image'),
              );
            }).toList(),
          ] else if ((post.mediaType == 'image' || post.mediaType == 'video') && post.mediaData.isNotEmpty) ...[
            const SizedBox(height: 12),
            MediaPreview(mediaPath: post.mediaData, mediaType: post.mediaType),
          ],
        ],
      ),
    );
  }

  // --- 🔥 دالة إدخال التعليق السحرية المدمجة مع المايك (زي ما صلحناها في الدردشة والقنوات) ---
  Widget _buildInteractiveCommentInput(String username, String userId, String postId) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(13), blurRadius: 10, offset: const Offset(0, -5))],
      ),
      child: _isRecording
          ? Row(
              children: [
                const Icon(Icons.mic, color: Colors.redAccent, size: 28),
                const SizedBox(width: 12),
                Text(
                  'جاري التسجيل... 00:${_recordingSeconds.toString().padLeft(2, '0')}',
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
                    controller: _commentController,
                    onChanged: (val) => setState(() => _isTyping = val.trim().isNotEmpty),
                    decoration: InputDecoration(
                      hintText: 'أضف تعليقاً كـ $username...',
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onLongPress: _isTyping ? null : () async {
                    final canRecord = await _audioService.checkPermission();
                    if (!canRecord) {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('صلاحية الميكروفون مطلوبة')));
                      return;
                    }
                    setState(() {
                      _isRecording = true;
                      _recordingSeconds = 0;
                      _isCanceling = false;
                    });
                    await _audioService.startRecording();
                    _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
                      setState(() => _recordingSeconds++);
                    });
                  },
                  onLongPressCancel: () async {
                    if (!_isRecording) return;
                    _isCanceling = true;
                    _recordTimer?.cancel();
                    await _audioService.stopRecording();
                    setState(() {
                      _isRecording = false;
                      _recordingSeconds = 0;
                    });
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إلغاء التسجيل')));
                  },
                  onLongPressEnd: _isTyping ? null : (details) async {
                    if (_isCanceling) return;
                    _recordTimer?.cancel();
                    setState(() => _isRecording = false);

                    final audioPath = await _audioService.stopRecording();
                    if (audioPath == null || audioPath.isEmpty) return;

                    try {
                      // 🔥 استخدام XFile المباشر لرفع الصوت بنجاح!
                      final localXFile = XFile(audioPath);
                      final uploadResult = await _mediaService.uploadXFileWithResult(localXFile, isVideo: false);
                      
                      if (!uploadResult.success || uploadResult.url == null || uploadResult.url!.isEmpty) {
                        throw Exception('فشل رفع الصوت');
                      }

                      await _commentService.addComment(
                        postId: postId,
                        userId: userId,
                        username: username,
                        text: '[AUDIO]',
                        audioUrl: uploadResult.url!,
                        type: 'audio',
                        duration: _audioService.durationSeconds,
                        replyToCommentId: _replyToCommentId,
                        replyToUserId: _replyToUserId,
                        replyToUsername: _replyToUsername,
                      );
                      setState(() {
                        _replyToCommentId = null;
                        _replyToUserId = null;
                        _replyToUsername = null;
                      });
                    } catch (_) {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فشل إرسال الصوت')));
                    }
                  },
                  onTap: () async {
                    if (_isTyping) {
                      final text = _commentController.text.trim();
                      if (text.isEmpty) return;
                      try {
                        await _commentService.addComment(
                          postId: postId,
                          userId: userId,
                          username: username,
                          text: text,
                          replyToCommentId: _replyToCommentId,
                          replyToUserId: _replyToUserId,
                          replyToUsername: _replyToUsername,
                        );
                        _commentController.clear();
                        setState(() {
                          _isTyping = false;
                          _replyToCommentId = null;
                          _replyToUserId = null;
                          _replyToUsername = null;
                        });
                      } catch (_) {
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فشل إرسال التعليق')));
                      }
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اضغط مطولاً لتسجيل رسالة صوتية')));
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _isTyping ? const Color(0xFF5B6CFF) : const Color(0xFF2EC7A5),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(_isTyping ? Icons.send_rounded : Icons.mic, color: Colors.white, size: 22),
                  ),
                ),
              ],
            ),
    );
  }

  String _formatTimestamp(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inHours < 1) return '${diff.inMinutes} د';
    if (diff.inDays < 1) return '${diff.inHours} س';
    return '${date.day}/${date.month}/${date.year}';
  }
}
