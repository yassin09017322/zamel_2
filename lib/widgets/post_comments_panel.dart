import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/comment.dart';
import '../providers/auth_provider.dart';
import '../providers/comment_provider.dart';
import 'comment_section.dart';

class PostCommentsPanel extends StatefulWidget {
  final String postId;
  final bool bottomSheet;

  const PostCommentsPanel({
    super.key,
    required this.postId,
    this.bottomSheet = false,
  });

  @override
  State<PostCommentsPanel> createState() => _PostCommentsPanelState();
}

class _PostCommentsPanelState extends State<PostCommentsPanel> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => CommentProvider(postId: widget.postId),
      child: Consumer2<CommentProvider, AuthProvider>(
        builder: (context, provider, auth, _) {
          final user = auth.currentUser;
          final visibleComments = <Comment>[...provider.comments];
          for (final comment in provider.comments) {
            if (provider.isRepliesExpanded(comment.id)) {
              visibleComments.addAll(provider.repliesFor(comment.id));
            }
          }

          return Column(
            children: [
              if (widget.bottomSheet) _buildSheetHeader(context),
              Expanded(child: _buildList(context, provider, visibleComments)),
              if (user != null) _buildComposer(context, provider, user),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSheetHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'التعليقات',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    CommentProvider provider,
    List<Comment> visibleComments,
  ) {
    if (provider.isLoading && visibleComments.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.error != null && visibleComments.isEmpty) {
      return _ErrorMessage(
        message: provider.error!,
        onRetry: () => provider.loadMore(),
      );
    }
    if (visibleComments.isEmpty) {
      return const Center(child: Text('لا توجد تعليقات بعد. كن أول من يعلق!'));
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: visibleComments.length + 1,
      itemBuilder: (context, index) {
        if (index == visibleComments.length) {
          return _buildLoadMore(context, provider);
        }
        final comment = visibleComments[index];
        final isReply = comment.replyToCommentId.isNotEmpty;
        return Padding(
          padding: EdgeInsetsDirectional.only(start: isReply ? 20 : 0),
          child: Column(
            children: [
              CommentSection(
                comments: [comment],
                onReply: provider.startReply,
                onLike: provider.toggleLike,
                onEdit: (item) {
                  _controller.text = item.text;
                  provider.startEditing(item);
                },
                onDelete: (item) => _confirmDelete(context, provider, item),
                currentUserId: Provider.of<AuthProvider>(
                  context,
                  listen: false,
                ).currentUser?.id,
                isLiked: (item) => item.isLikedByCurrentUser,
              ),
              if (!isReply && comment.repliesCount > 0)
                TextButton.icon(
                  onPressed: provider.isRepliesExpanded(comment.id)
                      ? () => provider.collapseReplies(comment.id)
                      : () => provider.loadReplies(comment.id),
                  icon: Icon(
                    provider.isRepliesExpanded(comment.id)
                        ? Icons.expand_less
                        : Icons.forum_outlined,
                  ),
                  label: Text(
                    provider.isRepliesExpanded(comment.id)
                        ? 'إخفاء الردود'
                        : 'عرض الردود (${comment.repliesCount})',
                  ),
                ),
              if (!isReply &&
                  provider.isRepliesExpanded(comment.id) &&
                  provider.hasMoreReplies(comment.id))
                TextButton(
                  onPressed: () => provider.loadMoreReplies(comment.id),
                  child: const Text('تحميل المزيد من الردود'),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLoadMore(BuildContext context, CommentProvider provider) {
    if (!provider.hasMore) return const SizedBox(height: 16);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: provider.isLoadingMore
          ? const Center(child: CircularProgressIndicator())
          : OutlinedButton(
              onPressed: provider.loadMore,
              child: const Text('تحميل المزيد من التعليقات'),
            ),
    );
  }

  Widget _buildComposer(
    BuildContext context,
    CommentProvider provider,
    dynamic user,
  ) {
    final replyingTo = provider.replyToUsername;
    return SafeArea(
      top: false,
      child: Column(
        children: [
          if (replyingTo != null)
            Container(
              width: double.infinity,
              color: Colors.grey.shade100,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(child: Text('رد على $replyingTo')),
                  IconButton(
                    onPressed: provider.cancelReply,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          if (provider.editingCommentId != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: provider.cancelEditing,
                child: const Text('إلغاء التعديل'),
              ),
            ),
          if (provider.isRecording)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.mic, color: Colors.redAccent),
                  const SizedBox(width: 8),
                  Text('جاري التسجيل... ${provider.recordingSeconds} ث'),
                  const Spacer(),
                  TextButton(
                    onPressed: provider.cancelRecording,
                    child: const Text('إلغاء'),
                  ),
                  FilledButton(
                    onPressed: provider.isSending
                        ? null
                        : () => _sendAudio(provider, user),
                    child: const Text('إرسال'),
                  ),
                ],
              ),
            )
          else if (provider.isUploading)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text('جاري رفع التعليق الصوتي...'),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: provider.uploadProgress),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendText(provider, user),
                      decoration: InputDecoration(
                        hintText: provider.editingCommentId != null
                            ? 'تعديل التعليق'
                            : 'أضف تعليقاً كـ ${user.username}',
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: provider.isSending
                        ? null
                        : () => _sendText(provider, user),
                    icon: const Icon(Icons.send_rounded),
                  ),
                  GestureDetector(
                    onLongPress: provider.isSending
                        ? null
                        : () async {
                            try {
                              await provider.startRecording();
                            } catch (error) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(error.toString())),
                                );
                              }
                            }
                          },
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.mic),
                    ),
                  ),
                ],
              ),
            ),
          if (provider.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                provider.error!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _sendText(CommentProvider provider, dynamic user) async {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    try {
      await provider.sendText(
        text: text,
        userId: user.id,
        username: user.username,
        userPhotoUrl: user.photoURL,
      );
      _controller.clear();
    } catch (_) {}
  }

  Future<void> _sendAudio(CommentProvider provider, dynamic user) async {
    try {
      await provider.sendAudio(
        userId: user.id,
        username: user.username,
        userPhotoUrl: user.photoURL,
      );
    } catch (_) {}
  }

  Future<void> _confirmDelete(
    BuildContext context,
    CommentProvider provider,
    Comment comment,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف التعليق'),
        content: const Text('هل تريد حذف هذا التعليق؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await provider.delete(comment);
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(error.toString())));
        }
      }
    }
  }
}

class _ErrorMessage extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorMessage({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: onRetry,
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }
}
