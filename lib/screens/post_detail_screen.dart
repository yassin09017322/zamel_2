import 'package:flutter/material.dart';

import '../models/post.dart';
import '../screens/profile_screen.dart';
import '../services/post_service.dart';
import '../widgets/media_preview.dart';
import '../widgets/post_comments_panel.dart';

class PostDetailScreen extends StatefulWidget {
  final String postId;

  const PostDetailScreen({super.key, required this.postId});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  @override
  Widget build(BuildContext context) {
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
              return Center(
                child: Text('فشل تحميل المنشور: ${snapshot.error}'),
              );
            }
            final post = snapshot.data;
            if (post == null) {
              return const Center(child: Text('لم يتم العثور على المنشور.'));
            }

            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 12,
                    ),
                    children: [
                      _buildPostCard(post),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(
                            Icons.chat_bubble_outline_rounded,
                            color: Theme.of(context).colorScheme.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'التعليقات',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      SizedBox(
                        height: 560,
                        child: PostCommentsPanel(postId: post.id),
                      ),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
                const SizedBox.shrink(),
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
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
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
                child: Text(
                  post.username.isNotEmpty
                      ? post.username[0].toUpperCase()
                      : 'م',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ProfileScreen(userId: post.userId),
                        ),
                      ),
                      child: Text(
                        post.username,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Text(
                      _formatTimestamp(post.timestamp),
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            post.text,
            style: const TextStyle(
              fontSize: 15,
              height: 1.5,
              color: Color(0xFF2F2F2F),
            ),
          ),
          if (post.mediaFiles.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...post.mediaFiles.map((media) {
              if (media.mediaType == 'video') {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: MediaPreview(
                    mediaPath: media.url,
                    mediaType: 'video',
                    enableAudio: true,
                    showControls: true,
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: MediaPreview(mediaPath: media.url, mediaType: 'image'),
              );
            }).toList(),
          ] else if ((post.mediaType == 'image' || post.mediaType == 'video') &&
              post.mediaData.isNotEmpty) ...[
            const SizedBox(height: 12),
            MediaPreview(
              mediaPath: post.mediaData,
              mediaType: post.mediaType,
              enableAudio: post.mediaType == 'video',
              showControls: post.mediaType == 'video',
            ),
          ],
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
