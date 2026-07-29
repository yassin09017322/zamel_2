import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/post.dart';
import '../models/comment.dart';
import '../providers/auth_provider.dart';
import '../screens/profile_screen.dart';
import '../services/comment_service.dart';
import '../services/post_service.dart';
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
  bool _sending = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = context.watch<AuthProvider>().currentUser;

    return Scaffold(
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
                        return CommentSection(comments: comments);
                      },
                    ),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
              if (currentUser != null) _buildCommentInput(currentUser.username, currentUser.id, post.id),
            ],
          );
        },
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
          if ((post.mediaType == 'image' || post.mediaType == 'video') && post.mediaData.isNotEmpty) ...[
            const SizedBox(height: 12),
            MediaPreview(mediaPath: post.mediaData, mediaType: post.mediaType),
          ],
          if (post.hashtags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: post.hashtags.map((tag) => Chip(
                label: Text('#$tag', style: const TextStyle(fontSize: 12, color: Color(0xFF5B6CFF))),
                backgroundColor: const Color(0xFF5B6CFF).withOpacity(0.1),
                visualDensity: VisualDensity.compact,
              )).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCommentInput(String username, String userId, String postId) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _commentController,
              textDirection: TextDirection.rtl,
              decoration: InputDecoration(
                hintText: 'أضف تعليقاً...',
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 26,
            backgroundColor: Colors.blue,
            child: IconButton(
              icon: _sending ? const CircularProgressIndicator(color: Colors.white) : const Icon(Icons.send, color: Colors.white),
              onPressed: _sending ? null : () async {
                final text = _commentController.text.trim();
                if (text.isEmpty) return;
                setState(() => _sending = true);
                try {
                  await _commentService.addComment(postId: postId, userId: userId, username: username, text: text);
                  _commentController.clear();
                } catch (_) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فشل إضافة التعليق')));
                } finally {
                  setState(() => _sending = false);
                }
              },
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
