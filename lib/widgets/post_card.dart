import 'dart:async'; // تم إضافتها لعداد تسجيل الصوت
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/comment.dart';
import '../models/post.dart';
import '../providers/auth_provider.dart';
import '../screens/post_detail_screen.dart';
import '../screens/profile_screen.dart';
import '../services/audio_service.dart';
import '../services/comment_service.dart';
import '../services/post_service.dart';
import '../services/post_translation_service.dart';
import 'comment_section.dart';
import 'media_preview.dart';
import 'main_feed_video_player.dart';

class PostCard extends StatefulWidget {
  final Post post;
  final bool isMainFeed;

  const PostCard({super.key, required this.post, this.isMainFeed = false});

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard>
    with SingleTickerProviderStateMixin {
  bool _isSaved = false;
  bool _isHidden = false;
  bool _notificationsEnabled = false;
  bool _seesFewerSimilarPosts = false;
  bool _isRemoved = false;
  bool _isTextExpanded = false;
  final AudioCommentService _audioCommentService = AudioCommentService();
  String? _activeAudioUrl;
  bool _isAudioPlaying = false;
  Duration _audioPosition = Duration.zero;
  late final StreamSubscription<Duration> _audioPositionSub;
  late final StreamSubscription<PlayerState> _audioStateSub;
  final PostTranslationService _translationService = PostTranslationService();
  String? _translationKey;
  String? _translatedText;
  bool _translationLoading = false;

  static const Map<String, Map<String, dynamic>> _zamelReactions = {
    'like': {'emoji': '👍', 'label': 'أوافق', 'color': Color(0xFF5B6CFF)},
    'love': {'emoji': '❤️', 'label': 'أبدعت', 'color': Color(0xFFE94057)},
    'haha': {'emoji': '😂', 'label': 'ضحكتني', 'color': Color(0xFFF2C94C)},
    'spot_on': {
      'emoji': '🎯',
      'label': 'في الصميم',
      'color': Color(0xFF2EC7A5),
    },
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
      if (state == PlayerState.completed ||
          state == PlayerState.stopped ||
          state == PlayerState.paused) {
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
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;
    try {
      final state = await PostService.getInteractionState(
        userId: user.id,
        post: widget.post,
      );
      if (mounted) {
        setState(() {
          _isSaved = state.isSaved;
          _isHidden = state.isHidden;
          _notificationsEnabled = state.notificationsEnabled;
          _seesFewerSimilarPosts = state.seesFewerSimilarPosts;
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تحميل خيارات المنشور: $error')),
        );
      }
    }
  }

  Future<void> _toggleSave() async {
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;
    final nextValue = !_isSaved;
    try {
      await PostService.setSavedPost(
        userId: user.id,
        postId: widget.post.id,
        saved: nextValue,
      );
      if (mounted) setState(() => _isSaved = nextValue);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تحديث حفظ المنشور: $error')),
        );
      }
    }
  }

  Future<void> _toggleHidden() async {
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;
    final nextValue = !_isHidden;
    try {
      await PostService.setHiddenPost(
        userId: user.id,
        postId: widget.post.id,
        hidden: nextValue,
      );
      if (mounted) setState(() => _isHidden = nextValue);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تحديث إخفاء المنشور: $error')),
        );
      }
    }
  }

  Future<void> _toggleNotifications() async {
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;
    final nextValue = !_notificationsEnabled;
    try {
      await PostService.setPostNotifications(
        userId: user.id,
        postId: widget.post.id,
        enabled: nextValue,
      );
      if (mounted) setState(() => _notificationsEnabled = nextValue);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تحديث إشعارات المنشور: $error')),
        );
      }
    }
  }

  Future<void> _toggleFewerSimilarPosts() async {
    final user = context.read<AuthProvider>().currentUser;
    final categoryId = widget.post.categoryId?.trim();
    if (user == null || categoryId == null || categoryId.isEmpty) return;
    final nextValue = !_seesFewerSimilarPosts;
    try {
      await PostService.setFewerSimilarPosts(
        userId: user.id,
        categoryId: categoryId,
        enabled: nextValue,
      );
      if (mounted) setState(() => _seesFewerSimilarPosts = nextValue);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تحديث تفضيل المنشورات: $error')),
        );
      }
    }
  }

  Future<void> _deletePost() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف المنشور؟'),
        content: const Text('سيتم حذف المنشور نهائيًا من Firestore.'),
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
    if (confirmed != true) return;
    try {
      await PostService.deletePost(postId: widget.post.id);
      if (mounted) setState(() => _isRemoved = true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تعذر حذف المنشور: $error')));
      }
    }
  }

  Future<void> _changeAudience() async {
    final selectedPrivacy = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('تغيير الجمهور'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'public'),
            child: Text('عام'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'friends'),
            child: Text('الأصدقاء / المتابعون'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'private'),
            child: Text('خاص / أنا فقط'),
          ),
        ],
      ),
    );
    if (selectedPrivacy == null || selectedPrivacy == widget.post.privacy)
      return;
    try {
      await PostService.updatePostPrivacy(
        postId: widget.post.id,
        privacy: selectedPrivacy,
      );
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تغيير جمهور المنشور: $error')),
        );
      }
    }
  }

  Future<void> _showPostMenu({required bool isOwner}) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: isOwner
              ? [
                  ListTile(
                    leading: const Icon(
                      Icons.delete_outline,
                      color: Colors.red,
                    ),
                    title: const Text('حذف المنشور'),
                    onTap: () => Navigator.pop(sheetContext, 'delete'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.notifications_none),
                    title: Text(
                      _notificationsEnabled
                          ? 'إيقاف إشعارات المنشور'
                          : 'تشغيل إشعارات المنشور',
                    ),
                    onTap: () => Navigator.pop(sheetContext, 'notifications'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.people_outline),
                    title: const Text('تغيير الجمهور'),
                    onTap: () => Navigator.pop(sheetContext, 'audience'),
                  ),
                ]
              : [
                  ListTile(
                    leading: Icon(
                      _isSaved ? Icons.bookmark : Icons.bookmark_border,
                    ),
                    title: Text(_isSaved ? 'إلغاء حفظ المنشور' : 'حفظ المنشور'),
                    onTap: () => Navigator.pop(sheetContext, 'save'),
                  ),
                  ListTile(
                    leading: Icon(
                      _isHidden ? Icons.visibility : Icons.visibility_off,
                    ),
                    title: Text(_isHidden ? 'إظهار المنشور' : 'إخفاء المنشور'),
                    onTap: () => Navigator.pop(sheetContext, 'hide'),
                  ),
                  if (widget.post.categoryId?.trim().isNotEmpty == true)
                    ListTile(
                      leading: const Icon(Icons.remove_circle_outline),
                      title: Text(
                        _seesFewerSimilarPosts
                            ? 'إلغاء تقليل المنشورات المشابهة'
                            : 'رؤية منشورات أقل تشبه هذا',
                      ),
                      onTap: () => Navigator.pop(sheetContext, 'fewer'),
                    ),
                ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'delete':
        await _deletePost();
      case 'notifications':
        await _toggleNotifications();
      case 'audience':
        await _changeAudience();
      case 'save':
        await _toggleSave();
      case 'hide':
        await _toggleHidden();
      case 'fewer':
        await _toggleFewerSimilarPosts();
    }
  }

  void _requestPostTranslation() {
    final targetLanguage = Localizations.localeOf(context).languageCode;
    final key = '${widget.post.id}|$targetLanguage|${widget.post.text}';
    if (_translationKey == key) return;

    _translationKey = key;
    _translatedText = null;
    _translationLoading = true;
    unawaited(_loadPostTranslation(key, targetLanguage));
  }

  Future<void> _loadPostTranslation(String key, String targetLanguage) async {
    String? translation;
    try {
      translation = await _translationService.translateIfNeeded(
        postId: widget.post.id,
        text: widget.post.text,
        targetLanguage: targetLanguage,
      );
    } catch (error) {
      debugPrint('Post translation failed: $error');
    } finally {
      if (!mounted || _translationKey != key) return;
      setState(() {
        _translatedText = translation;
        _translationLoading = false;
      });
    }
  }

  Widget _buildPostText({required bool isOwner}) {
    _requestPostTranslation();
    final original = _buildTextContent(isOwner: isOwner);
    if (_translationLoading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          original,
          const SizedBox(height: 8),
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
      );
    }
    if ((_translatedText ?? '').isEmpty) return original;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        original,
        const SizedBox(height: 8),
        Text(
          _translatedText!,
          style: const TextStyle(
            fontSize: 15,
            height: 1.5,
            color: Color(0xFF5B6CFF),
          ),
        ),
      ],
    );
  }

  Future<void> _copyPostText() async {
    await Clipboard.setData(ClipboardData(text: widget.post.text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم نسخ نص المنشور')));
  }

  Future<void> _editPostText() async {
    final controller = TextEditingController(text: widget.post.text);
    final updatedText = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تعديل المنشور'),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 8,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || updatedText == null || updatedText == widget.post.text) {
      return;
    }
    if (updatedText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يمكن أن يكون نص المنشور فارغًا')),
      );
      return;
    }
    try {
      await PostService.updatePostText(
        postId: widget.post.id,
        text: updatedText,
      );
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تعذر تعديل المنشور: $error')));
      }
    }
  }

  Future<void> _showTextPostMenu({
    required bool isOwner,
    required bool canExpand,
  }) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('نسخ المنشور'),
              onTap: () => Navigator.pop(sheetContext, 'copy'),
            ),
            if (canExpand)
              ListTile(
                leading: Icon(
                  _isTextExpanded ? Icons.unfold_less : Icons.unfold_more,
                ),
                title: Text(_isTextExpanded ? 'عرض أقل' : 'عرض أكثر'),
                onTap: () => Navigator.pop(sheetContext, 'expand'),
              ),
            if (isOwner)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('تعديل المنشور'),
                onTap: () => Navigator.pop(sheetContext, 'edit'),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'copy':
        await _copyPostText();
      case 'expand':
        setState(() => _isTextExpanded = !_isTextExpanded);
      case 'edit':
        await _editPostText();
    }
  }

  Widget _buildTextContent({required bool isOwner}) {
    const textStyle = TextStyle(
      fontSize: 15,
      height: 1.5,
      color: Color(0xFF2F2F2F),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.post.text, style: textStyle),
          textDirection: Directionality.of(context),
          maxLines: 6,
        )..layout(maxWidth: constraints.maxWidth);
        final canExpand = painter.didExceedMaxLines;
        final text = GestureDetector(
          onLongPress: () =>
              _showTextPostMenu(isOwner: isOwner, canExpand: canExpand),
          child: Text(
            widget.post.text,
            maxLines: canExpand && !_isTextExpanded ? 6 : null,
            overflow: canExpand && !_isTextExpanded
                ? TextOverflow.ellipsis
                : TextOverflow.visible,
            style: textStyle,
          ),
        );
        if (!canExpand) return text;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            text,
            TextButton(
              onPressed: () =>
                  setState(() => _isTextExpanded = !_isTextExpanded),
              child: Text(_isTextExpanded ? 'عرض أقل' : 'عرض أكثر'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _toggleAudioPlayback(Comment comment) async {
    if (comment.audioUrl.isEmpty) {
      return;
    }

    if (_activeAudioUrl == comment.audioUrl && _isAudioPlaying) {
      await _audioCommentService.pause();
      if (mounted) {
        setState(() => _isAudioPlaying = false);
      }
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
        reactionType: reactionType,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('فشل تسجيل التفاعل')));
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
                BoxShadow(
                  color: Colors.black.withAlpha(38),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
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
                          Text(
                            entry.value['emoji'],
                            style: const TextStyle(fontSize: 32),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            entry.value['label'],
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: entry.value['color'],
                            ),
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
    final validReactions = widget.post.reactions.values
        .where((r) => r != 'none')
        .toList();
    if (validReactions.isEmpty) {
      return const SizedBox.shrink();
    }

    final uniqueEmojis = validReactions
        .map((r) => _zamelReactions[r]?['emoji'])
        .where((e) => e != null)
        .toSet()
        .take(3)
        .toList();

    bool iReacted =
        widget.post.reactions.containsKey(currentUserId) &&
        widget.post.reactions[currentUserId] != 'none';
    int count = validReactions.length;

    String text = '';
    if (iReacted && count == 1) {
      text = 'أنت تفاعلت';
    } else if (iReacted && count > 1) {
      text = 'أنت و ${count - 1} آخرين';
    } else {
      text = '$count تفاعل';
    }

    return Row(
      children: [
        Row(
          children: uniqueEmojis
              .map(
                (e) => Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Text(
                    e.toString(),
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = context.watch<AuthProvider>().currentUser;
    final String currentUserId = currentUser?.id ?? '';
    if (_isHidden || _isRemoved) return const SizedBox.shrink();

    String? myReaction;
    if (widget.post.reactions.containsKey(currentUserId) &&
        widget.post.reactions[currentUserId] != 'none') {
      myReaction = widget.post.reactions[currentUserId];
    }

    final reactionData =
        myReaction != null && _zamelReactions.containsKey(myReaction)
        ? _zamelReactions[myReaction]!
        : null;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PostDetailScreen(postId: widget.post.id),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(15),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
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
                      widget.post.username.isNotEmpty
                          ? widget.post.username[0].toUpperCase()
                          : 'م',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        GestureDetector(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ProfileScreen(userId: widget.post.userId),
                            ),
                          ),
                          child: Text(
                            widget.post.username,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        if (widget.post.location.isNotEmpty)
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on,
                                size: 12,
                                color: Color(0xFF2EC7A5),
                              ),
                              const SizedBox(width: 2),
                              Text(
                                widget.post.location,
                                style: const TextStyle(
                                  color: Color(0xFF2EC7A5),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        Text(
                          _formatTimestamp(widget.post.timestamp),
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    widget.post.privacy == 'private'
                        ? Icons.lock
                        : widget.post.privacy == 'friends'
                        ? Icons.group
                        : Icons.public,
                    size: 16,
                    color: Colors.grey,
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_horiz),
                    tooltip: 'خيارات المنشور',
                    onPressed: currentUser == null
                        ? null
                        : () => _showPostMenu(
                            isOwner: currentUser.id == widget.post.userId,
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (widget.post.text.trim().isNotEmpty)
                _buildPostText(
                  isOwner: currentUser?.id == widget.post.userId,
                ),

              if (widget.post.mediaFiles.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildMediaGallery(widget.post.mediaFiles),
              ] else if (widget.post.mediaType == 'image' &&
                  widget.post.mediaData.isNotEmpty) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.network(
                    widget.post.mediaData,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    loadingBuilder: (ctx, child, progress) => progress == null
                        ? child
                        : Container(
                            height: 200,
                            color: Colors.grey[100],
                            child: const Center(
                              child: CircularProgressIndicator(),
                            ),
                          ),
                    errorBuilder: (ctx, err, stack) => Container(
                      height: 200,
                      color: Colors.grey[100],
                      child: const Center(
                        child: Icon(
                          Icons.broken_image,
                          size: 50,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ),
                ),
              ] else if (widget.post.mediaType == 'video' &&
                  widget.post.mediaData.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  height: 220,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const Positioned(
                        bottom: 12,
                        left: 12,
                        child: Text(
                          'مقطع فيديو',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(51),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          size: 50,
                          color: Colors.white,
                        ),
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
                  Text(
                    '${widget.post.commentsCount} تعليق',
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
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
                      onLongPress: () => currentUser != null
                          ? _showZamelReactions(context, currentUserId)
                          : null,
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
                            Text(
                              reactionData?['emoji'] ?? '🤍',
                              style: const TextStyle(fontSize: 20),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              reactionData?['label'] ?? 'أوافق',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color:
                                    reactionData?['color'] ?? Colors.grey[600],
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
                            Icon(
                              Icons.chat_bubble_outline_rounded,
                              color: Colors.grey[600],
                              size: 20,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'تعليق',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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
                            Icon(
                              _isSaved
                                  ? Icons.bookmark_rounded
                                  : Icons.bookmark_border_rounded,
                              color: _isSaved
                                  ? const Color(0xFF2EC7A5)
                                  : Colors.grey[600],
                              size: 20,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'حفظ',
                              style: TextStyle(
                                color: _isSaved
                                    ? const Color(0xFF2EC7A5)
                                    : Colors.grey[600],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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
                    children: widget.post.hashtags
                        .map(
                          (tag) => Chip(
                            label: Text(
                              '#$tag',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF5B6CFF),
                              ),
                            ),
                            backgroundColor: const Color(
                              0xFF5B6CFF,
                            ).withAlpha(26),
                            visualDensity: VisualDensity.compact,
                          ),
                        )
                        .toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // --- دالة التعليقات مع نظام التسجيل الصوتي المدمج (بصمة زامل) ---
  Widget _buildMediaGallery(List<PostMedia> mediaFiles) {
    if (mediaFiles.isEmpty) {
      return const SizedBox.shrink();
    }

    final mediaView = mediaFiles.take(4).toList();
    if (mediaView.length == 1) {
      final item = mediaView.first;
      if (item.mediaType == 'video') {
        return widget.isMainFeed
            ? MainFeedVideoPlayer(url: item.url)
            : MediaPreview(
                mediaPath: item.url,
                mediaType: 'video',
                enableAudio: true,
                showControls: true,
              );
      }

      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image.network(
          item.url,
          width: double.infinity,
          fit: BoxFit.cover,
          loadingBuilder: (ctx, child, progress) => progress == null
              ? child
              : Container(
                  height: 200,
                  color: Colors.grey[100],
                  child: const Center(child: CircularProgressIndicator()),
                ),
          errorBuilder: (ctx, err, stack) => Container(
            height: 200,
            color: Colors.grey[100],
            child: const Center(
              child: Icon(Icons.broken_image, size: 50, color: Colors.grey),
            ),
          ),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: mediaView.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemBuilder: (context, index) {
        final item = mediaView[index];
        if (item.mediaType == 'video') {
          return widget.isMainFeed
              ? MainFeedVideoPlayer(url: item.url)
              : MediaPreview(
                  mediaPath: item.url,
                  mediaType: 'video',
                  enableAudio: true,
                  showControls: true,
                );
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.network(
            item.url,
            fit: BoxFit.cover,
            errorBuilder: (ctx, err, stack) => Container(
              color: Colors.grey[100],
              child: const Center(
                child: Icon(Icons.broken_image, size: 28, color: Colors.grey),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showComments() {
    final currentUser = context.read<AuthProvider>().currentUser;
    if (currentUser == null) {
      return;
    }

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
        Comment? replyToComment;
        bool isCanceling = false;
        bool isSendingComment = false;

        return StatefulBuilder(
          builder: (BuildContext ctx, StateSetter setModalState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'التعليقات',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                    if (replyToComment != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'رد على ${replyToComment!.username}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF5B6CFF),
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () =>
                                    setModalState(() => replyToComment = null),
                                child: const Icon(
                                  Icons.close,
                                  size: 18,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.55,
                      child: StreamBuilder<List<Comment>>(
                        stream: CommentService().commentsStream(widget.post.id),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(
                                color: Color(0xFF5B6CFF),
                              ),
                            );
                          }
                          if (snapshot.hasError) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  'تعذر تحميل التعليقات\n${snapshot.error}',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            );
                          }
                          final comments = snapshot.data ?? [];
                          if (comments.isEmpty) {
                            return const Center(
                              child: Text(
                                'لا توجد تعليقات بعد. كن أول متفاعل!',
                                style: TextStyle(color: Colors.grey),
                              ),
                            );
                          }
                          return CommentSection(
                            comments: comments,
                            onReply: (comment) => setModalState(
                              () => replyToComment = comment,
                            ),
                          );
                        },
                      ),
                    ),

                    // --- منطقة إدخال التعليق (المايك والنص) ---
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(13),
                            blurRadius: 10,
                            offset: const Offset(0, -5),
                          ),
                        ],
                      ),
                      child: isRecording
                          ? Row(
                              children: [
                                const Icon(
                                  Icons.mic,
                                  color: Colors.redAccent,
                                  size: 28,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'جاري التسجيل... 00:0$recordingSeconds',
                                  style: const TextStyle(
                                    color: Colors.redAccent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                const Spacer(),
                                const Text(
                                  'اسحب للإلغاء',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            )
                          : Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: commentController,
                                    onChanged: (val) {
                                      setModalState(
                                        () => isTyping = val.trim().isNotEmpty,
                                      );
                                    },
                                    decoration: InputDecoration(
                                      hintText:
                                          'أضف تعليقاً كـ ${currentUser!.username}...',
                                      filled: true,
                                      fillColor: Colors.grey[100],
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(20),
                                        borderSide: BorderSide.none,
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 10,
                                          ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),

                                // زر المايك / الإرسال التفاعلي
                                GestureDetector(
                                  onLongPress: isTyping
                                      ? null
                                      : () async {
                                          final canRecord = await audioService
                                              .checkPermission();
                                          if (!canRecord) {
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'الاذن للمكروفون مطلوب للتسجيل',
                                                  ),
                                                ),
                                              );
                                            }
                                            return;
                                          }

                                          setModalState(() {
                                            isRecording = true;
                                            recordingSeconds = 0;
                                            isCanceling = false;
                                          });
                                          await audioService.startRecording();
                                          recordTimer = Timer.periodic(
                                            const Duration(seconds: 1),
                                            (timer) {
                                              setModalState(
                                                () => recordingSeconds++,
                                              );
                                            },
                                          );
                                        },
                                  onLongPressCancel: () async {
                                    if (!isRecording) {
                                      return;
                                    }
                                    isCanceling = true;
                                    recordTimer?.cancel();
                                    await audioService.stopRecording();
                                    setModalState(() {
                                      isRecording = false;
                                      recordingSeconds = 0;
                                    });
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('تم إلغاء التسجيل'),
                                        ),
                                      );
                                    }
                                  },
                                  onLongPressEnd: isTyping
                                      ? null
                                      : (details) async {
                                          if (isCanceling) {
                                            return;
                                          }

                                          recordTimer?.cancel();
                                          setModalState(
                                            () => isRecording = false,
                                          );

                                          final audioPath = await audioService
                                              .stopRecording();
                                          if (audioPath == null ||
                                              audioPath.isEmpty) {
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'فشل تسجيل الصوت',
                                                  ),
                                                ),
                                              );
                                            }
                                            return;
                                          }

                                          try {
                                            if (isSendingComment) return;
                                            setModalState(
                                              () => isSendingComment = true,
                                            );
                                            final uploadResult =
                                                await audioService
                                                    .uploadAudioFile(audioPath);
                                            if (uploadResult == null ||
                                                uploadResult['url'] == null) {
                                              throw Exception('فشل الرفع');
                                            }

                                            await CommentService().addComment(
                                              postId: widget.post.id,
                                              userId: currentUser!.id,
                                              username: currentUser!.username,
                                              text: '[AUDIO]',
                                              audioUrl: uploadResult['url'],
                                              type: 'audio',
                                              duration:
                                                  audioService.durationSeconds,
                                              replyToCommentId:
                                                  replyToComment?.id,
                                              replyToUserId:
                                                  replyToComment?.userId,
                                              replyToUsername:
                                                  replyToComment?.username,
                                              clientRequestId:
                                                  '${widget.post.id}_${DateTime.now().microsecondsSinceEpoch}',
                                            );
                                            setModalState(
                                              () => replyToComment = null,
                                            );
                                          } catch (error) {
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    'فشل إرسال الصوت: $error',
                                                  ),
                                                ),
                                              );
                                            }
                                          } finally {
                                            if (context.mounted) {
                                              setModalState(
                                                () => isSendingComment = false,
                                              );
                                            }
                                          }
                                        },
                                  onTap: () async {
                                    if (isTyping) {
                                      if (isSendingComment) return;
                                      final text = commentController.text
                                          .trim();
                                      if (text.isEmpty) {
                                        return;
                                      }
                                      setModalState(
                                        () => isSendingComment = true,
                                      );
                                      try {
                                        await CommentService().addComment(
                                          postId: widget.post.id,
                                          userId: currentUser!.id,
                                          username: currentUser!.username,
                                          text: text,
                                          replyToCommentId: replyToComment?.id,
                                          replyToUserId: replyToComment?.userId,
                                          replyToUsername:
                                              replyToComment?.username,
                                          clientRequestId:
                                              '${widget.post.id}_${DateTime.now().microsecondsSinceEpoch}',
                                        );
                                        commentController.clear();
                                        setModalState(() {
                                          isTyping = false;
                                          replyToComment = null;
                                        });
                                      } catch (error) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'فشل إرسال التعليق: $error',
                                              ),
                                            ),
                                          );
                                        }
                                      } finally {
                                        if (context.mounted) {
                                          setModalState(
                                            () => isSendingComment = false,
                                          );
                                        }
                                      }
                                    } else {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'اضغط مطولاً لتسجيل رسالة صوتية',
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: isTyping
                                          ? const Color(0xFF5B6CFF)
                                          : const Color(0xFF2EC7A5),
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color:
                                              (isTyping
                                                      ? const Color(0xFF5B6CFF)
                                                      : const Color(0xFF2EC7A5))
                                                  .withAlpha(77),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
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
    if (diff.inMinutes < 1) {
      return 'الآن';
    }
    if (diff.inHours < 1) {
      return '${diff.inMinutes} د';
    }
    if (diff.inDays < 1) {
      return '${diff.inHours} س';
    }
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatTimestamp(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) {
      return 'الآن';
    }
    if (diff.inHours < 1) {
      return '${diff.inMinutes} د';
    }
    if (diff.inDays < 1) {
      return '${diff.inHours} س';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays} ي';
    }
    return '${date.day}/${date.month}/${date.year}';
  }
}
