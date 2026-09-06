# POSTS COMMENTS — FULL SYSTEM

> نطاق هذا الملف: نظام تعليقات المنشورات في تطبيق Flutter النشط الموجود تحت `lib/` في جذر المشروع `c:\zamel_2`. لم يتم تعديل أي ملف أصلي. أنظمة Chat/Messages وStories وReels وChannels وGroups مستبعدة من المسار النشط، مع ذكر الاعتمادات المشتركة فقط.

## 1. SYSTEM OVERVIEW

يوجد مساران فعليان لتعليقات المنشورات في Flutter:

1. من `PostCard` داخل التغذية أو الملف الشخصي: يضغط المستخدم زر التعليق، فتفتح نافذة `showModalBottomSheet`. النافذة تستمع إلى `CommentService.commentsStream(post.id)` وتعرض البيانات عبر `CommentSection`، وتوفر إدخال النص والتسجيل الصوتي والردود.
2. من `PostDetailScreen`: ينتقل المستخدم إلى تفاصيل المنشور، ثم تعرض الشاشة منشورًا حيًا عبر `PostService.postStream` وتعليقات حيّة عبر `CommentService.commentsStream`، مع إدخال نص/صوت والردود.

عند إرسال تعليق، تتحقق `CommentService` من وجود مستخدم Firebase مصادق عليه، وصحة معرف المستخدم والمنشور، ووجود نص أو رابط صوتي صالح، ثم تنفذ Firestore transaction. المعاملة تتحقق من المنشور ومن التعليق الأب عند الرد، تكتب مستند التعليق في `posts/{postId}/comments/{commentId}`، وتزيد `posts/{postId}.commentsCount` ذريًا بمقدار واحد. مستمع `snapshots()` يعيد القائمة إلى الواجهة مباشرة.

لا يوجد Provider أو Controller أو Bloc أو Repository مستقل للتعليقات. الحالة المحلية موجودة داخل `PostCard` bottom sheet و`PostDetailScreen`، أما القراءة الحية فتأتي مباشرة من Firestore عبر `CommentService`.

## 2. FILE MAP

| File path | Role | Why related |
|---|---|---|
| `lib/widgets/post_card.dart` | Post entry point and comments bottom sheet | Displays count, opens comments, sends text/audio comments, starts replies |
| `lib/screens/post_detail_screen.dart` | Full post details/comments screen | Displays post and comments, sends text/audio comments, starts replies |
| `lib/widgets/comment_section.dart` | Comment tree and item UI | Renders root comments, nested replies, timestamps, profiles and audio playback |
| `lib/models/comment.dart` | Comment model | Parses Firestore comment documents and all comment fields |
| `lib/services/comment_service.dart` | Comment Firestore service | Reads comments, creates comments, validates identity, updates post count |
| `lib/models/post.dart` | Post model | Owns `commentsCount` and parses the post document |
| `lib/services/post_service.dart` | Post Firestore service | Streams posts/details, initializes count, exposes count helper |
| `lib/providers/auth_provider.dart` | Auth state | Supplies current authenticated `AppUser` to comment UI |
| `lib/models/app_user.dart` | User model | Supplies user ID and username used by comment creation |
| `lib/main.dart` | Provider wiring | Registers `AuthProvider` and feed providers globally |
| `lib/services/audio_service.dart` | Shared audio comments service | Records, uploads and plays audio comments |
| `lib/services/media_service.dart` | Shared upload service | Uploads recorded audio through Cloudflare Worker |
| `lib/screens/feed_screen.dart` | Feed caller | Constructs `PostCard` for feed posts |
| `lib/screens/profile_screen.dart` | Profile caller | Constructs `PostCard` for profile posts |
| `lib/screens/notifications_screen.dart` | Comment notification entry | Routes a notification of type `comment` to `PostDetailScreen` |
| `lib/models/notification_item.dart` | Notification model | Parses notification reference/type used by routing |
| `lib/services/notification_service.dart` | Shared notification service | Provides generic notification creation/mark-as-read; no active comment writer calls it |
| `pubspec.yaml` | Package dependencies | Declares Firebase, Provider, audio, recording and upload packages |
| `test/services/ZAMEL/firestore.rules` | Rules fixture | Contains the only discovered rules for post comments; not a root production rules file |
| `test/services/ZAMEL/index.html` | Legacy web implementation | Separate JavaScript comments implementation; not imported by active Flutter code |

## 3. ENTRY POINT

### Feed and profile entry

`lib/screens/feed_screen.dart` constructs the post card:

```dart
PostCard(post: posts[index], isMainFeed: true)
```

`lib/screens/profile_screen.dart` constructs the same widget for profile posts:

```dart
PostCard(post: post)
```

`lib/widgets/post_card.dart` displays the post count and binds the comment action:

```dart
Text(
  '${widget.post.commentsCount} تعليق',
  style: const TextStyle(
    color: Colors.grey,
    fontSize: 13,
    fontWeight: FontWeight.bold,
  ),
),
```

```dart
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
```

The `PostCard` method is:

```dart
void _showComments() {
  final currentUser = context.read<AuthProvider>().currentUser;
  if (currentUser == null) {
    return;
  }

  final audioService = _audioCommentService;
  Timer? recordTimer;

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
                                        'أضف تعليقاً كـ ${currentUser.username}...',
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
                              GestureDetector(
                                onLongPress: isTyping
                                    ? null
                                    : () async {
                                        final canRecord = await audioService
                                            .checkPermission();
                                        if (!canRecord) {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
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
                                  if (!isRecording) return;
                                  isCanceling = true;
                                  recordTimer?.cancel();
                                  await audioService.stopRecording();
                                  setModalState(() {
                                    isRecording = false;
                                    recordingSeconds = 0;
                                  });
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('تم إلغاء التسجيل'),
                                      ),
                                    );
                                  }
                                },
                                onLongPressEnd: isTyping
                                    ? null
                                    : (details) async {
                                        if (isCanceling) return;
                                        recordTimer?.cancel();
                                        setModalState(() => isRecording = false);
                                        final audioPath =
                                            await audioService.stopRecording();
                                        if (audioPath == null ||
                                            audioPath.isEmpty) {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text('فشل تسجيل الصوت'),
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
                                          final uploadResult = await audioService
                                              .uploadAudioFile(audioPath);
                                          if (uploadResult == null ||
                                              uploadResult['url'] == null) {
                                            throw Exception('فشل الرفع');
                                          }
                                          await CommentService().addComment(
                                            postId: widget.post.id,
                                            userId: currentUser.id,
                                            username: currentUser.username,
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
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
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
                                  if (!isTyping) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'اضغط مطولاً لتسجيل رسالة صوتية',
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  if (isSendingComment) return;
                                  final text = commentController.text.trim();
                                  if (text.isEmpty) return;
                                  setModalState(() => isSendingComment = true);
                                  try {
                                    await CommentService().addComment(
                                      postId: widget.post.id,
                                      userId: currentUser.id,
                                      username: currentUser.username,
                                      text: text,
                                      replyToCommentId: replyToComment?.id,
                                      replyToUserId: replyToComment?.userId,
                                      replyToUsername: replyToComment?.username,
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
                                      ScaffoldMessenger.of(context).showSnackBar(
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
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isTyping
                                        ? const Color(0xFF5B6CFF)
                                        : const Color(0xFF2EC7A5),
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
  ).then((_) {
    recordTimer?.cancel();
  });
}
```

The post body also routes to the detail screen:

```dart
Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => PostDetailScreen(postId: widget.post.id),
  ),
)
```

## 4. COMMENTS UI

### CommentSection

`lib/widgets/comment_section.dart` is the reusable comment list. It receives `List<Comment>` and an optional reply callback. It groups replies by `replyToCommentId`, identifies root comments, recursively renders child replies, and prevents cycles using `ancestorIds`.

The widget displays username, timestamp, reply target, text/audio content, profile navigation and a reply button. It does not display comment profile images.

```dart
import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../models/comment.dart';
import '../screens/profile_screen.dart';
import '../services/audio_service.dart';

class CommentSection extends StatefulWidget {
  final List<Comment> comments;
  final void Function(Comment comment)? onReply;

  const CommentSection({super.key, required this.comments, this.onReply});

  @override
  State<CommentSection> createState() => _CommentSectionState();
}

class _CommentSectionState extends State<CommentSection> {
  final AudioCommentService _audioService = AudioCommentService();
  String? _activeAudioUrl;
  bool _isAudioPlaying = false;
  Duration _audioPosition = Duration.zero;
  late final StreamSubscription<Duration> _positionSub;
  late final StreamSubscription<PlayerState> _stateSub;

  @override
  void initState() {
    super.initState();
    _positionSub = _audioService.positionStream.listen((position) {
      if (!mounted) return;
      setState(() => _audioPosition = position);
    });
    _stateSub = _audioService.playerStateStream.listen((state) {
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
  }

  @override
  void dispose() {
    _positionSub.cancel();
    _stateSub.cancel();
    _audioService.dispose();
    super.dispose();
  }

  Future<void> _toggleAudioPlayback(Comment comment) async {
    if (comment.audioUrl.isEmpty) return;

    if (_activeAudioUrl == comment.audioUrl && _isAudioPlaying) {
      await _audioService.pause();
      if (mounted) setState(() => _isAudioPlaying = false);
      return;
    }

    await _audioService.stop();
    await _audioService.play(comment.audioUrl);
    if (mounted) {
      setState(() {
        _activeAudioUrl = comment.audioUrl;
        _audioPosition = Duration.zero;
        _isAudioPlaying = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final commentsByParent = <String, List<Comment>>{};
    final commentIds = widget.comments.map((comment) => comment.id).toSet();
    for (final comment in widget.comments) {
      final parentId = comment.replyToCommentId.trim();
      if (parentId.isNotEmpty) {
        commentsByParent.putIfAbsent(parentId, () => <Comment>[]).add(comment);
      }
    }

    final rootComments = widget.comments.where((comment) {
      final parentId = comment.replyToCommentId.trim();
      return parentId.isEmpty || !commentIds.contains(parentId);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rootComments
          .map((comment) => _buildCommentTree(comment, commentsByParent, <String>{}))
          .toList(),
    );
  }

  Widget _buildCommentTree(
    Comment comment,
    Map<String, List<Comment>> commentsByParent,
    Set<String> ancestorIds,
  ) {
    final nextAncestorIds = <String>{...ancestorIds, comment.id};
    final replies = (commentsByParent[comment.id] ?? const <Comment>[])
        .where((reply) => !nextAncestorIds.contains(reply.id));
    final isAudio = comment.type == 'audio' ||
        comment.audioUrl.isNotEmpty ||
        comment.text.startsWith('[AUDIO]');
    final active = _activeAudioUrl == comment.audioUrl;
    final duration = Duration(seconds: comment.duration > 0 ? comment.duration : 30);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ProfileScreen(userId: comment.userId),
                          ),
                        ),
                        child: Text(
                          comment.username,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _formatTime(comment.timestamp),
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                  if (comment.replyToUsername.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        'رد على ${comment.replyToUsername}',
                        style: const TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  if (isAudio)
                    InkWell(
                      onTap: () async {
                        try {
                          await _toggleAudioPlayback(comment);
                        } catch (_) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('تعذر تشغيل الصوت')),
                            );
                          }
                        }
                      },
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF5B6CFF).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  active && _isAudioPlaying
                                      ? Icons.pause_circle_filled
                                      : Icons.play_circle_fill,
                                  color: const Color(0xFF5B6CFF),
                                  size: 28,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    comment.text.isNotEmpty &&
                                            !comment.text.startsWith('[AUDIO]')
                                        ? comment.text
                                        : 'تعليق صوتي',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0F1A3A),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            LinearProgressIndicator(
                              value: active
                                  ? (_audioPosition.inMilliseconds /
                                          duration.inMilliseconds)
                                      .clamp(0.0, 1.0)
                                  : 0.0,
                              backgroundColor: Colors.white,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFF5B6CFF),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              active
                                  ? '${_formatDuration(_audioPosition)} / ${_formatDuration(duration)}'
                                  : '0:00 / ${_formatDuration(duration)}',
                              style: const TextStyle(
                                color: Color(0xFF5B6CFF),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Text(
                      comment.text,
                      style: const TextStyle(color: Colors.black87, height: 1.4),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => widget.onReply?.call(comment),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF5B6CFF),
                        ),
                        child: const Text('رد'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (replies.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 20),
              child: Column(
                children: replies
                    .map((reply) => _buildCommentTree(
                          reply,
                          commentsByParent,
                          nextAncestorIds,
                        ))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _formatTime(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inHours < 1) return '${diff.inMinutes} د';
    if (diff.inDays < 1) return '${diff.inHours} س';
    return '${date.day}/${date.month}/${date.year}';
  }
}
```

## 5. COMMENT MODEL

File: `lib/models/comment.dart`

Fields:

| Field | Type | Firestore source/default |
|---|---|---|
| `id` | `String` | Snapshot document ID |
| `userId` | `String` | `userId`, default empty |
| `username` | `String` | `username`, default `مستخدم` |
| `text` | `String` | `text`, default empty |
| `timestamp` | `DateTime` | `createdAt`, then `timestamp`, then `updatedAt`; fallback `DateTime.now()` |
| `audioUrl` | `String` | `audioUrl`, default empty |
| `publicId` | `String` | `publicId`, default empty |
| `type` | `String` | `type`, default `text` |
| `duration` | `int` | `duration`; non-int values become `0` |
| `mediaIndex` | `int` | int/num conversion, default `0` |
| `replyToCommentId` | `String` | Parent comment ID, default empty |
| `replyToUserId` | `String` | Parent author ID, default empty |
| `replyToUsername` | `String` | Parent author name, default empty |

Complete model source:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

class Comment {
  final String id;
  final String userId;
  final String username;
  final String text;
  final DateTime timestamp;
  final String audioUrl;
  final String publicId;
  final String type;
  final int duration;
  final int mediaIndex;
  final String replyToCommentId;
  final String replyToUserId;
  final String replyToUsername;

  Comment({
    required this.id,
    required this.userId,
    required this.username,
    required this.text,
    required this.timestamp,
    this.audioUrl = '',
    this.publicId = '',
    this.type = 'text',
    this.duration = 0,
    this.mediaIndex = 0,
    this.replyToCommentId = '',
    this.replyToUserId = '',
    this.replyToUsername = '',
  });

  factory Comment.fromFirestore(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data() ?? <String, dynamic>{};
    final timestampValue =
        data['createdAt'] ?? data['timestamp'] ?? data['updatedAt'];
    DateTime date;
    if (timestampValue is Timestamp) {
      date = timestampValue.toDate();
    } else if (timestampValue is DateTime) {
      date = timestampValue;
    } else if (timestampValue is String) {
      date = DateTime.tryParse(timestampValue) ?? DateTime.now();
    } else {
      date = DateTime.now();
    }

    int parsedMediaIndex = 0;
    if (data['mediaIndex'] is int) {
      parsedMediaIndex = data['mediaIndex'] as int;
    } else if (data['mediaIndex'] is num) {
      parsedMediaIndex = (data['mediaIndex'] as num).toInt();
    }

    return Comment(
      id: snapshot.id,
      userId: data['userId'] as String? ?? '',
      username: data['username'] as String? ?? 'مستخدم',
      text: data['text'] as String? ?? '',
      timestamp: date,
      audioUrl: data['audioUrl'] as String? ?? '',
      publicId: data['publicId'] as String? ?? '',
      type: data['type'] as String? ?? 'text',
      duration: data['duration'] is int ? data['duration'] as int : 0,
      mediaIndex: parsedMediaIndex,
      replyToCommentId: data['replyToCommentId'] as String? ?? '',
      replyToUserId: data['replyToUserId'] as String? ?? '',
      replyToUsername: data['replyToUsername'] as String? ?? '',
    );
  }
}
```

## 6. STATE MANAGEMENT

There is no comment-specific Provider/Controller/Bloc/Riverpod/GetX class.

The global wiring in `lib/main.dart` includes:

```dart
return MultiProvider(
  providers: [
    ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
    ChangeNotifierProvider<SettingsProvider>(
      create: (_) => SettingsProvider(),
    ),
    ChangeNotifierProvider<AtyaafProvider>(create: (_) => AtyaafProvider()),
    ChangeNotifierProvider<EngagementProvider>(
      create: (_) => EngagementProvider(),
    ),
    ChangeNotifierProvider<FeedProvider>(create: (_) => FeedProvider()),
    Provider<LocalStorageService>(create: (_) => LocalStorageService()),
  ],
  child: PresenceTracker(
```

Comments use `AuthProvider` only as a shared dependency. Local comment state is held by:

- `PostCard._showComments`: `StatefulBuilder`, `isTyping`, `isRecording`, `recordingSeconds`, `replyToComment`, `isCanceling`, `isSendingComment`.
- `PostDetailScreen`: `_isTyping`, `_isRecording`, `_recordingSeconds`, `_recordTimer`, `_isCanceling`, `_isSendingComment`, and reply IDs/names.
- `CommentSection`: audio playback state and subscriptions.

## 7. COMMENT SERVICE

File: `lib/services/comment_service.dart`. Complete source:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/comment.dart';

class CommentService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static const Duration _writeTimeout = Duration(seconds: 30);

  static Map<String, dynamic> buildCommentPayload({
    required String postId,
    required String userId,
    required String username,
    required String text,
    String? audioUrl,
    String? publicId,
    String? type,
    int? duration,
    int mediaIndex = 0,
    String? replyToCommentId,
    String? replyToUserId,
    String? replyToUsername,
  }) {
    final resolvedUserId = userId.trim().isNotEmpty ? userId.trim() : '';
    final resolvedUsername = username.trim().isNotEmpty ? username.trim() : 'مستخدم';
    final normalizedText = text.trim();
    final normalizedAudioUrl = (audioUrl ?? '').trim();

    return {
      'postId': postId.trim(),
      'userId': resolvedUserId,
      'username': resolvedUsername,
      'text': normalizedText,
      'audioUrl': normalizedAudioUrl,
      'publicId': publicId ?? '',
      'type': type ?? 'text',
      'duration': duration ?? 0,
      'mediaIndex': mediaIndex,
      'replyToCommentId': replyToCommentId ?? '',
      'replyToUserId': replyToUserId ?? '',
      'replyToUsername': replyToUsername ?? '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'timestamp': FieldValue.serverTimestamp(),
    };
  }

  Stream<List<Comment>> commentsStream(String postId, {int? mediaIndex}) {
    final normalizedPostId = postId.trim();
    if (normalizedPostId.isEmpty) {
      return Stream.value(const <Comment>[]);
    }

    Query<Map<String, dynamic>> query = _firestore
        .collection('posts')
        .doc(normalizedPostId)
        .collection('comments')
        .orderBy('createdAt', descending: true);

    if (mediaIndex != null) {
      query = query.where('mediaIndex', isEqualTo: mediaIndex);
    }

    return query.snapshots().map((snapshot) {
      final comments = snapshot.docs
          .map((doc) => Comment.fromFirestore(doc))
          .toList();
      comments.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return comments;
    });
  }

  Future<void> addComment({
    required String postId,
    required String userId,
    required String username,
    required String text,
    String? audioUrl,
    String? publicId,
    String? type,
    int? duration,
    int mediaIndex = 0,
    String? replyToCommentId,
    String? replyToUserId,
    String? replyToUsername,
    String? clientRequestId,
  }) async {
    final currentUser = _auth.currentUser;
    final authenticatedUserId = currentUser?.uid ?? '';
    final requestedUserId = userId.trim();
    if (authenticatedUserId.isEmpty) {
      throw Exception('يجب تسجيل الدخول لإرسال تعليق');
    }
    if (requestedUserId.isNotEmpty && requestedUserId != authenticatedUserId) {
      throw Exception('هوية صاحب التعليق غير صالحة');
    }
    final effectiveUserId = authenticatedUserId;
    final effectiveUsername = username.trim().isNotEmpty
        ? username.trim()
        : (currentUser?.displayName ?? currentUser?.email ?? 'مستخدم');

    if (postId.trim().isEmpty) {
      throw Exception('معرف المنشور غير صالح');
    }
    if (effectiveUserId.isEmpty) {
      throw Exception('هوية صاحب التعليق غير صالحة');
    }

    final normalizedText = text.trim();
    final normalizedAudioUrl = (audioUrl ?? '').trim();

    if (normalizedText.isEmpty && normalizedAudioUrl.isEmpty) {
      throw Exception('لا يمكن إرسال تعليق فارغ');
    }
    if (normalizedAudioUrl.isNotEmpty) {
      final audioUri = Uri.tryParse(normalizedAudioUrl);
      if (audioUri == null ||
          audioUri.scheme != 'https' ||
          audioUri.host.isEmpty) {
        throw Exception('رابط الصوت غير صالح');
      }
    }

    final postReference = _firestore.collection('posts').doc(postId.trim());
    final parentCommentId = (replyToCommentId ?? '').trim();
    final commentReference =
        clientRequestId == null || clientRequestId.trim().isEmpty
        ? postReference.collection('comments').doc()
        : postReference.collection('comments').doc(clientRequestId.trim());

    try {
      await _firestore
          .runTransaction((transaction) async {
            final postSnapshot = await transaction.get(postReference);
            if (!postSnapshot.exists) {
              throw Exception('المنشور غير موجود');
            }

            if (parentCommentId.isNotEmpty) {
              final parentSnapshot = await transaction.get(
                postReference.collection('comments').doc(parentCommentId),
              );
              if (!parentSnapshot.exists) {
                throw Exception('التعليق الأب غير موجود');
              }
            }

            final existingComment = await transaction.get(commentReference);
            if (existingComment.exists) {
              final existingData =
                  existingComment.data() ?? <String, dynamic>{};
              if (existingData['userId'] == effectiveUserId) {
                return;
              }
              throw Exception('معرف طلب التعليق مستخدم مسبقًا');
            }

            final payload = buildCommentPayload(
              postId: postId,
              userId: effectiveUserId,
              username: effectiveUsername,
              text: text,
              audioUrl: normalizedAudioUrl,
              publicId: publicId,
              type: type,
              duration: duration,
              mediaIndex: mediaIndex,
              replyToCommentId: replyToCommentId,
              replyToUserId: replyToUserId,
              replyToUsername: replyToUsername,
            );

            transaction.set(commentReference, payload);
            transaction.update(postReference, {
              'commentsCount': FieldValue.increment(1),
            });
          })
          .timeout(_writeTimeout);
    } on FirebaseException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        Exception(
          'فشل حفظ التعليق (${error.code}): ${error.message ?? 'خطأ غير معروف'}',
        ),
        stackTrace,
      );
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        Exception('فشل حفظ التعليق: $error'),
        stackTrace,
      );
    }
  }

  Future<void> addLike({required String postId, required String userId}) async {
    final postRef = _firestore.collection('posts').doc(postId);
    await postRef.update({
      'likes': FieldValue.arrayUnion([userId]),
    });
  }

  Future<void> removeLike({
    required String postId,
    required String userId,
  }) async {
    final postRef = _firestore.collection('posts').doc(postId);
    await postRef.update({
      'likes': FieldValue.arrayRemove([userId]),
    });
  }
}
```

The two methods named `addLike` and `removeLike` update the parent post's `likes` field. They are not comment-like operations and no active call site for them was found.

## 8. FIRESTORE / DATABASE

### Active Flutter collection path

```text
posts/{postId}
posts/{postId}/comments/{commentId}
```

### Create comment

The active Flutter implementation writes a comment and increments the parent post count in one transaction:

```dart
transaction.set(commentReference, payload);
transaction.update(postReference, {
  'commentsCount': FieldValue.increment(1),
});
```

### Comment document structure

```text
postId: String
userId: String
username: String
text: String
audioUrl: String
publicId: String
type: String
duration: int
mediaIndex: int
replyToCommentId: String
replyToUserId: String
replyToUsername: String
createdAt: server timestamp
updatedAt: server timestamp
timestamp: server timestamp
```

The document ID is generated by Firestore unless `clientRequestId` is supplied. The active UI supplies a value based on post ID and current microseconds, giving basic idempotency.

### Read comments

```dart
Query<Map<String, dynamic>> query = _firestore
    .collection('posts')
    .doc(normalizedPostId)
    .collection('comments')
    .orderBy('createdAt', descending: true);

if (mediaIndex != null) {
  query = query.where('mediaIndex', isEqualTo: mediaIndex);
}

return query.snapshots().map((snapshot) {
  final comments = snapshot.docs
      .map((doc) => Comment.fromFirestore(doc))
      .toList();
  comments.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  return comments;
});
```

Reads are realtime, not paginated, and have no `limit`. The UI separately sorts the converted list by the parsed timestamp.

### Update comment

NOT FOUND in the active Flutter implementation.

### Delete comment

NOT FOUND in the active Flutter implementation.

### Like/unlike comment

NOT FOUND in the active Flutter implementation. `CommentService.addLike/removeLike` update `posts/{postId}.likes`, not a comment document. The legacy web implementation has comment likes and is documented in section 17.

### Reply

Replies are ordinary comment documents with parent metadata:

```dart
'replyToCommentId': replyToCommentId ?? '',
'replyToUserId': replyToUserId ?? '',
'replyToUsername': replyToUsername ?? '',
```

`addComment` reads the parent comment inside the same transaction and rejects a missing parent.

### Pagination

NOT FOUND for comments. Post pagination exists in `FeedProvider`, but it does not paginate the comment subcollection.

### Count

New posts initialize the count in `PostService.publishPost`:

```dart
'commentsCount': 0,
```

The active comment transaction increments it:

```dart
'commentsCount': FieldValue.increment(1),
```

`PostService` also contains this helper:

```dart
static Future<void> updateCommentsCount({
  required String postId,
  required int incrementBy,
}) async {
  try {
    final docRef = _firestore.collection('posts').doc(postId);
    await docRef.update({'commentsCount': FieldValue.increment(incrementBy)});
  } catch (e) {
    throw Exception('فشل تحديث عداد التعليقات: $e');
  }
}
```

No active Flutter comment call site for this helper was found. There is no active decrement when deleting a comment because deletion is not implemented.

### Indexes

No Firebase index file or production root `firestore.rules` file was found. The query requiring the visible fields is `orderBy('createdAt')`; optional `mediaIndex` filtering may require a Firestore composite index depending on the deployed database configuration.

### Rules fixture

The only discovered rules file is `test/services/ZAMEL/firestore.rules`, not a root production rules file:

```text
match /posts/{postId} {
  allow read: if true;
  allow create: if isSignedIn();
  allow update: if isAdmin() || resource.data.userId == request.auth.uid;
  allow delete: if isAdmin();
}

match /posts/{postId}/comments/{commentId} {
  allow read: if true;
  allow create: if isSignedIn();
  allow update: if isAdmin();
  allow delete: if isAdmin();
}
```

## 9. SEND COMMENT FLOW

### Text

```text
User types in TextField
→ local isTyping becomes true
→ user taps send
→ UI trims text and rejects empty text locally
→ CommentService.addComment()
→ FirebaseAuth.currentUser is checked
→ supplied userId must match Firebase UID
→ post ID must be non-empty
→ text/audio empty check passes
→ transaction verifies post exists
→ parent comment is verified when replying
→ client request ID is checked for idempotency
→ comment document is written
→ posts.commentsCount is incremented atomically
→ Firestore snapshot stream emits the new list
→ CommentSection rebuilds
→ input/reply local state is cleared
```

### Audio

```text
User long-presses the comment action
→ microphone permission is checked
→ AudioCommentService starts recording
→ recording duration timer updates local UI
→ release stops recording
→ recorded file/bytes are uploaded by MediaService through the Cloudflare Worker
→ returned HTTPS URL is validated by CommentService
→ addComment() writes text '[AUDIO]', type 'audio', audioUrl and duration
→ comments snapshot emits the new comment
→ CommentSection renders audio playback UI
```

## 10. REPLIES

Replies are implemented in the active Flutter path. `CommentSection` builds a client-side tree from the flat stream:

```dart
final commentsByParent = <String, List<Comment>>{};
final commentIds = widget.comments.map((comment) => comment.id).toSet();
for (final comment in widget.comments) {
  final parentId = comment.replyToCommentId.trim();
  if (parentId.isNotEmpty) {
    commentsByParent.putIfAbsent(parentId, () => <Comment>[]).add(comment);
  }
}

final rootComments = widget.comments.where((comment) {
  final parentId = comment.replyToCommentId.trim();
  return parentId.isEmpty || !commentIds.contains(parentId);
});
```

The recursive tree prevents cycles:

```dart
final nextAncestorIds = <String>{...ancestorIds, comment.id};
final replies = (commentsByParent[comment.id] ?? const <Comment>[])
    .where((reply) => !nextAncestorIds.contains(reply.id));
```

The UI invokes `onReply` from:

```dart
TextButton(
  onPressed: () => widget.onReply?.call(comment),
  style: TextButton.styleFrom(
    foregroundColor: const Color(0xFF5B6CFF),
  ),
  child: const Text('رد'),
),
```

The parent ID, parent user ID and parent username are then passed to `addComment`. Nested replies are therefore supported by repeated use of the same fields.

## 11. COMMENT LIKES

### Active Flutter

NOT FOUND as a comment feature.

The only similarly named active methods are:

```dart
Future<void> addLike({required String postId, required String userId}) async {
  final postRef = _firestore.collection('posts').doc(postId);
  await postRef.update({
    'likes': FieldValue.arrayUnion([userId]),
  });
}

Future<void> removeLike({
  required String postId,
  required String userId,
}) async {
  final postRef = _firestore.collection('posts').doc(postId);
  await postRef.update({
    'likes': FieldValue.arrayRemove([userId]),
  });
}
```

These update the post likes array and do not read or write `posts/{postId}/comments/{commentId}`.

### Legacy web only

The separate `test/services/ZAMEL/index.html` has `likeComment(postId, commentId)`, which toggles a `likes` array on a comment document. It is not imported into the active Flutter application.

## 12. AUDIO / VOICE COMMENTS

Audio comments are FOUND in the active Flutter implementation.

File: `lib/services/audio_service.dart`. Relevant complete service:

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart' as audioplayers;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import 'media_service.dart';
import 'package:zamel_appp/src/platform_file.dart' as io;
import 'web_audio_stub.dart' if (dart.library.html) 'web_audio.dart';

class AudioCommentService {
  final AudioRecorder _mobileRecorder = AudioRecorder();
  final audioplayers.AudioPlayer _player = audioplayers.AudioPlayer();
  final MediaService _mediaService = MediaService();

  bool _isRecording = false;
  String? _recordingPath;
  Timer? _timer;
  int _durationSeconds = 0;
  Uint8List? _webRecordedBytes;

  bool get isRecording => _isRecording;
  int get durationSeconds => _durationSeconds;
  String? get recordingPath => _recordingPath;
  Uint8List? get recordedBytes => _webRecordedBytes;

  Stream<Duration> get positionStream => _player.onPositionChanged;
  Stream<audioplayers.PlayerState> get playerStateStream => _player.onPlayerStateChanged;

  Future<bool> checkPermission() async {
    if (kIsWeb) {
      return true;
    }
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<String?> startRecording() async {
    final hasPermission = await checkPermission();
    if (!hasPermission) return null;

    if (kIsWeb) {
      _webRecordedBytes = null;
      _recordingPath = 'comment.webm';
      _durationSeconds = 0;
      _isRecording = true;
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _durationSeconds++;
      });
      await WebAudioRecorder.start();
      return _recordingPath;
    }

    final tempDir = await getTemporaryDirectory();
    final filePath = '${tempDir.path}/comment_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _mobileRecorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: filePath,
    );
    _recordingPath = filePath;
    _durationSeconds = 0;
    _isRecording = true;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _durationSeconds++;
    });
    return filePath;
  }

  Future<String?> stopRecording() async {
    if (!_isRecording) return null;
    _timer?.cancel();
    _timer = null;

    if (kIsWeb) {
      _webRecordedBytes = await WebAudioRecorder.stop();
      _isRecording = false;
      return _recordingPath;
    }

    final path = await _mobileRecorder.stop();
    _isRecording = false;
    if (path == null || path.isEmpty) return null;
    _recordingPath = path;
    return path;
  }

  Future<Map<String, dynamic>?> uploadAudioFile(String filePath) async {
    if (kIsWeb) {
      final bytes = _webRecordedBytes;
      if (bytes == null || bytes.isEmpty) return null;

      final uploadedUrl = await _mediaService.uploadBytes(
        bytes,
        filePath.endsWith('.webm') ? 'comment.webm' : 'comment.wav',
        isVideo: false,
      );
      return {'url': uploadedUrl};
    }

    final dynamic file = io.File(filePath);
    if (!await (file as dynamic).exists()) return null;

    final uploadedUrl = await _mediaService.uploadFile(
      file,
      isVideo: false,
    );

    return {'url': uploadedUrl};
  }

  Future<void> play(String url) async {
    if (url.isEmpty) return;

    if (url.startsWith('http://') || url.startsWith('https://')) {
      await _player.play(audioplayers.UrlSource(url));
      return;
    }

    if (kIsWeb) return;

    await _player.play(audioplayers.DeviceFileSource(url));
  }

  Future<void> pause() async {
    await _player.pause();
  }

  Future<void> stop() async {
    await _player.stop();
  }

  Future<void> dispose() async {
    _timer?.cancel();
    await _player.stop();
    await _player.dispose();
    await _mobileRecorder.dispose();
  }
}
```

Audio comment payload values used by both active UIs:

```dart
text: '[AUDIO]',
audioUrl: uploadedUrl,
type: 'audio',
duration: audioService.durationSeconds,
```

`CommentSection` uses `audioplayers`, tracks position/state streams, and renders a play/pause control plus progress bar. Recording uses `record` on mobile and the web audio implementation on web. `permission_handler` is used for microphone permission on non-web platforms.

## 13. COMMENT COUNTER

The count source is `Post.commentsCount`, parsed from `posts/{postId}.commentsCount` by `Post.fromFirestore`.

```dart
final int commentsCount;
```

```dart
int parsedCommentsCount = 0;
if (data['commentsCount'] is int) {
  parsedCommentsCount = data['commentsCount'];
} else if (data['commentsCount'] is num) {
  parsedCommentsCount = data['commentsCount'].toInt();
}
```

The feed card displays:

```dart
'${widget.post.commentsCount} تعليق'
```

The detail screen streams the parent post through `PostService.postStream`, so its post count updates when the parent document changes. The bottom sheet is opened from a `Post` passed to `PostCard`; its count is not locally incremented by the comment UI.

The active create flow increments the parent count in the same transaction as comment creation. There is no active delete flow and therefore no decrement flow.

## 14. NOTIFICATIONS

The active notification screen accepts a notification with `type == 'comment'` and routes it to the post detail screen:

```dart
if (item.referenceId.isNotEmpty &&
    (item.type == 'comment' ||
     item.type == 'like' ||
     item.type == 'post_update')) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => PostDetailScreen(postId: item.referenceId),
    ),
  );
  return;
}
```

The display text for a comment notification is:

```dart
case 'comment':
  actionText = ' بالتعليق على منشورك.';
  break;
```

`NotificationItem` parses `type`, `referenceId`, `postId`, sender/receiver IDs and read state.

The active Flutter comment write path does not call `NotificationService.createNotification`. No active caller creating a `type: 'comment'` notification was found. Therefore comment notification navigation exists, but comment notification creation is NOT FOUND in the active Flutter implementation.

## 15. ERROR HANDLING

### Authentication and permissions

`PostCard` disables the comment action when `currentUser == null`. `PostDetailScreen` renders its input only when `currentUser != null`. `CommentService` independently checks `FirebaseAuth.currentUser` and rejects unauthenticated writes.

The service rejects a supplied `userId` that differs from the Firebase UID:

```dart
if (requestedUserId.isNotEmpty && requestedUserId != authenticatedUserId) {
  throw Exception('هوية صاحب التعليق غير صالحة');
}
```

The UI does not explicitly check `AppUser.isBanned` or `AppUser.canPost` before comment creation. Such checks are NOT FOUND in the active comment path.

### Loading

Both comment UIs show `CircularProgressIndicator` while the stream is waiting.

### Empty states

Bottom sheet:

```dart
'لا توجد تعليقات بعد. كن أول متفاعل!'
```

Detail screen:

```dart
'لا توجد تعليقات بعد. كن أول من يعلق!'
```

### Read failures

Both UIs display a red error message containing the stream error:

```dart
'تعذر تحميل التعليقات\n${snapshot.error}'
```

### Send failures

Text bottom sheet:

```dart
'فشل إرسال التعليق: $error'
```

Audio bottom sheet:

```dart
'فشل إرسال الصوت: $error'
```

Detail screen uses the same two messages. `CommentService` wraps Firebase errors with the Firebase code/message and wraps other errors with `فشل حفظ التعليق`.

### Validation failures

Implemented in `CommentService`:

- empty authentication state
- mismatched user ID
- empty post ID
- empty text and empty audio together
- non-HTTPS or malformed audio URLs
- nonexistent post
- nonexistent reply parent
- reused client request ID belonging to another user
- 30-second Firestore write timeout

### Missing error/edge features

NOT FOUND:

- offline comment queue
- retry button for failed comment writes
- comment deletion errors
- comment editing errors
- comment pagination errors
- comment moderation/report errors
- comment-specific test suite

## 16. DEPENDENCIES

From `pubspec.yaml` and the active imports:

| Dependency | Use in Posts Comments |
|---|---|
| `firebase_auth` | Authenticated Firebase UID validation |
| `cloud_firestore` | Comment stream, transaction, post count and notification data |
| `provider` | Reading `AuthProvider.currentUser` |
| `audioplayers` | Playing comment audio and playback state |
| `record` | Mobile microphone recording |
| `permission_handler` | Microphone permission on non-web |
| `path_provider` | Temporary mobile recording path |
| `dio` | Media upload HTTP requests |
| `firebase_database` | Shared AuthProvider presence only; not comment persistence |
| Flutter Material | Comment sheets, inputs, cards, loading/error states |

The upload endpoint configured by `MediaService` is:

```text
https://zamel-2.yassin090173221.workers.dev/
```

## 17. SHARED CODE

### Authentication

`lib/providers/auth_provider.dart` listens to Firebase Auth state, then listens to `users/{uid}` and exposes `AppUser? currentUser`. The comment UI uses `currentUser.id` and `currentUser.username`; `CommentService` separately uses Firebase Auth for authoritative identity.

Relevant source:

```dart
class AuthProvider extends ChangeNotifier {
  final FirebaseAuth auth = FirebaseAuth.instance;
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();

  AppUser? currentUser;
  bool isLoading = true;
  String? errorMessage;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSubscription;

  AuthProvider() {
    _initialize();
  }

  Future<void> _initialize() async {
    auth.authStateChanges().listen((firebaseUser) async {
      isLoading = true;
      errorMessage = null;
      notifyListeners();

      await _userSubscription?.cancel();
      _userSubscription = null;

      if (firebaseUser == null || !firebaseUser.emailVerified) {
        currentUser = null;
        isLoading = false;
        notifyListeners();
        return;
      }

      final userRef = firestore.collection('users').doc(firebaseUser.uid);
      _userSubscription = userRef.snapshots().listen(
        (snapshot) async {
          if (snapshot.exists && snapshot.data() != null) {
            currentUser = AppUser.fromFirestore(snapshot.data()!, firebaseUser.uid);
            if (currentUser != null && currentUser!.isOnline != true) {
              await updateUserPresence(online: true);
            }
          } else {
            currentUser = null;
          }
          isLoading = false;
          notifyListeners();
        },
        onError: (error) {
          errorMessage = error.toString();
          isLoading = false;
          notifyListeners();
        },
      );
    });
  }
}
```

`AppUser` fields relevant to comments are `id`, `username`, `photoURL`, `isBanned`, and `canPost`. The active comment code uses only `id` and `username` directly. `photoURL` is not rendered for comment items. `isBanned` and `canPost` are not checked by the active comment UI/service.

### Post model

`Post` is shared by feed, profile and detail screens. Comment-related fields are `id`, `userId`, `username`, `timestamp`, `commentsCount`, and media fields used by the post detail card.

### Post service

`PostService.postStream(postId)` supplies the detail screen. `publishPost` initializes `commentsCount`. `updateCommentsCount` exists but is not called by the active comment service.

### Audio and media

`AudioCommentService` is a shared service also used by other parts of the application, but the comment path uses it for microphone recording and playback. `MediaService` is a shared upload service; comments use only `uploadFile`/`uploadBytes` through `AudioCommentService`.

### Notifications

`NotificationService` is shared with calls, channels and user actions. The active comments path does not invoke it, while `NotificationsScreen` can navigate to a post when an externally-created notification has type `comment`.

### Legacy web implementation

`test/services/ZAMEL/index.html` contains a separate JavaScript comments feature using the same high-level `posts/{postId}/comments` path but a different document shape and UI. It is not imported by `lib/`, so it is recorded as a separate historical/parallel implementation rather than merged into the active Flutter flow.

## 18. COMPLETE SOURCE COLLECTION

This section collects the complete active source files that are comment-specific, plus the exact comment-related source blocks from shared files. The complete sources of `lib/models/comment.dart`, `lib/services/comment_service.dart`, `lib/widgets/comment_section.dart`, and `lib/services/audio_service.dart` are included above in sections 4, 5, 7 and 12 respectively. The following shared-file blocks are the actual comment-related portions.

### `lib/models/post.dart`

```dart
final int commentsCount;
```

```dart
int parsedCommentsCount = 0;
if (data['commentsCount'] is int) {
  parsedCommentsCount = data['commentsCount'];
} else if (data['commentsCount'] is num) {
  parsedCommentsCount = data['commentsCount'].toInt();
}
```

```dart
commentsCount: parsedCommentsCount,
```

### `lib/services/post_service.dart`

```dart
'commentsCount': 0,
```

```dart
static Stream<Post?> postStream(String postId) {
  return _firestore.collection('posts').doc(postId).snapshots().map((
    snapshot,
  ) {
    if (!snapshot.exists) return null;
    return Post.fromFirestore(snapshot);
  });
}
```

```dart
static Future<void> updateCommentsCount({
  required String postId,
  required int incrementBy,
}) async {
  try {
    final docRef = _firestore.collection('posts').doc(postId);
    await docRef.update({'commentsCount': FieldValue.increment(incrementBy)});
  } catch (e) {
    throw Exception('فشل تحديث عداد التعليقات: $e');
  }
}
```

### `lib/screens/post_detail_screen.dart`

```dart
final TextEditingController _commentController = TextEditingController();
final CommentService _commentService = CommentService();
final AudioCommentService _audioService = AudioCommentService();

bool _isTyping = false;
bool _isRecording = false;
int _recordingSeconds = 0;
Timer? _recordTimer;
bool _isCanceling = false;
bool _isSendingComment = false;

String? _replyToCommentId;
String? _replyToUserId;
String? _replyToUsername;
```

```dart
StreamBuilder<List<Comment>>(
  stream: _commentService.commentsStream(post.id),
  builder: (context, commentsSnapshot) {
    if (commentsSnapshot.connectionState == ConnectionState.waiting) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }
    if (commentsSnapshot.hasError) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Text(
          'تعذر تحميل التعليقات\n${commentsSnapshot.error}',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.red),
        ),
      );
    }
    final comments = commentsSnapshot.data ?? [];
    if (comments.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Text(
          'لا توجد تعليقات بعد. كن أول من يعلق!',
        ),
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
```

```dart
await _commentService.addComment(
  postId: postId,
  userId: userId,
  username: username,
  text: text,
  replyToCommentId: _replyToCommentId,
  replyToUserId: _replyToUserId,
  replyToUsername: _replyToUsername,
  clientRequestId:
      '${postId}_${DateTime.now().microsecondsSinceEpoch}',
);
```

```dart
await _commentService.addComment(
  postId: postId,
  userId: userId,
  username: username,
  text: '[AUDIO]',
  audioUrl: uploadedUrl,
  type: 'audio',
  duration: _audioService.durationSeconds,
  replyToCommentId: _replyToCommentId,
  replyToUserId: _replyToUserId,
  replyToUsername: _replyToUsername,
  clientRequestId:
      '${postId}_${DateTime.now().microsecondsSinceEpoch}',
);
```

### `lib/screens/feed_screen.dart`

```dart
PostCard(post: posts[index], isMainFeed: true)
```

### `lib/screens/profile_screen.dart`

```dart
PostCard(post: post)
```

### `lib/screens/notifications_screen.dart`

```dart
if (item.referenceId.isNotEmpty && (item.type == 'comment' || item.type == 'like' || item.type == 'post_update')) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => PostDetailScreen(postId: item.referenceId)));
  return;
}
```

```dart
case 'comment':
  iconData = Icons.chat_bubble_rounded;
  bgColor = const Color(0xFF28A745);
  break;
```

```dart
case 'comment':
  actionText = ' بالتعليق على منشورك.';
  break;
```

### `lib/main.dart`

```dart
ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
ChangeNotifierProvider<FeedProvider>(create: (_) => FeedProvider()),
```

### `lib/services/media_service.dart`

The active audio-comment calls use these public methods:

```dart
Future<String> uploadFile(
  File file, {
  bool isVideo = false,
  String? explicitFileName,
}) async {
  final result = await uploadFileWithResult(
    file,
    isVideo: isVideo,
    explicitFileName: explicitFileName,
  );
  if (!result.success || (result.url ?? '').trim().isEmpty) {
    throw Exception(result.error ?? 'Upload failed');
  }
  return result.url!;
}
```

```dart
Future<String> uploadBytes(
  Uint8List bytes,
  String filename, {
  bool isVideo = false,
}) async {
  final result = await uploadBytesWithResult(
    bytes,
    filename,
    isVideo: isVideo,
  );
  if (!result.success || (result.url ?? '').trim().isEmpty) {
    throw Exception(result.error ?? 'Upload failed');
  }
  return result.url!;
}
```

The upload request sends `File-Name`, `Content-Type`, `Content-Length`, `X-File-Type` and expects a valid HTTPS URL in the response. It applies a 500 MB size limit, a 10-minute timeout and up to three attempts with retryable network/server errors.

### `test/services/ZAMEL/firestore.rules`

```text
match /posts/{postId}/comments/{commentId} {
  allow read: if true;
  allow create: if isSignedIn();
  allow update: if isAdmin();
  allow delete: if isAdmin();
}
```

### `test/services/ZAMEL/index.html` legacy source collection

This source is not part of the active Flutter implementation, but it is an existing Posts Comments implementation in the repository:

```javascript
window.openComments = function(postId) {
    window._currentPostId = postId;
    loadComments(postId);
    openModal('commentsModal');
};

window.loadComments = function(postId) {
    const container = document.getElementById('commentsContainer');
    container.innerHTML = '<div style="text-align:center; padding:20px; color:var(--text-muted);">جاري تحميل التعليقات...</div>';
    const q = query(collection(db, "posts", postId, "comments"), orderBy("timestamp", "desc"));
    onSnapshot(q, (snapshot) => {
        container.innerHTML = '';
        if (snapshot.empty) {
            container.innerHTML =
                '<div style="text-align:center; padding:20px; color:var(--text-muted);">لا توجد تعليقات، كن أول من يعلق! 💬</div>';
            return;
        }
        snapshot.forEach((doc) => {
            const data = doc.data();
            const commentHTML = `
                    <div class="comment-item" id="comment_${doc.id}">
                        <div class="comment-header">
                            <div class="avatar">${(data.username || 'م')[0].toUpperCase()}</div>
                            <strong>${data.username || 'مستخدم'}</strong>
                            <small style="color:var(--text-muted);">${data.timestamp ? new Date(data.timestamp.seconds*1000).toLocaleString() : 'الآن'}</small>
                        </div>
                        <div class="comment-body">
                            ${data.type === 'audio' ? `<audio controls src="${data.audioData}"></audio>` : data.text}
                        </div>
                        <div class="comment-actions">
                            <button onclick="replyToComment('${postId}','${doc.id}','${data.username || 'مستخدم'}')">رد</button>
                            <button onclick="likeComment('${postId}','${doc.id}')">❤️ ${data.likes ? data.likes.length : 0}</button>
                            ${window.currentAdminRole === 'admin' ? `<button onclick="window.deleteContentAdmin('comment','${postId}::${doc.id}')" style="color:var(--error);">حذف إداري</button>` : ''}
                        </div>
                        ${data.replies ? `<div class="replies">${data.replies.map(r => `<div style="padding:6px 0; border-bottom:1px solid var(--border-color);"><strong>${r.username}:</strong> ${r.text}</div>`).join('')}</div>` : ''}
                    </div>
                `;
            container.insertAdjacentHTML('beforeend', commentHTML);
        });
        container.scrollTop = container.scrollHeight;
    });
};

window.addComment = async function() {
    const inputField = document.getElementById('commentInput');
    const text = inputField.value.trim();
    if (!text) return;
    const postId = window._currentPostId;
    const userId = auth.currentUser?.uid;
    if (!postId || !userId) { alert("حدث خطأ، حاول مرة أخرى."); return; }
    try {
        const userData = await getDoc(doc(db, "users", userId));
        const username = userData.exists() ? userData.data().username : auth.currentUser?.email || 'مستخدم';
        const postRef = doc(db, "posts", postId);
        const postSnap = await getDoc(postRef);
        const postData = postSnap.exists() ? postSnap.data() : {};
        await addDoc(collection(db, "posts", postId, "comments"), {
            text: text,
            username: username,
            timestamp: serverTimestamp(),
            type: 'text',
            likes: [],
            replies: []
        });
        await updateDoc(postRef, { commentsCount: increment(1) });
        if (postData.userId && postData.userId !== userId) {
            await createNotification({ senderId: userId, receiverId: postData.userId, type: 'comment', referenceId: postId });
        }
        inputField.value = '';
        showToast("✅ تم إضافة التعليق");
        playNotificationSound();
        await addPoints(1);
    } catch (e) {
        console.error(e);
        showToast("❌ فشل إضافة التعليق");
    }
};

window.replyToComment = function(postId, commentId, username) {
    const reply = prompt(`رد على ${username}:`);
    if (!reply || reply.trim() === '') return;
    const commentRef = doc(db, "posts", postId, "comments", commentId);
    getDoc(commentRef).then(docSnap => {
        if (docSnap.exists()) {
            const data = docSnap.data();
            const replies = data.replies || [];
            replies.push({
                username: auth.currentUser?.email?.split('@')[0] || 'مستخدم',
                text: reply.trim(),
                timestamp: new Date().toISOString()
            });
            updateDoc(commentRef, { replies: replies });
            showToast("✅ تم إضافة الرد");
        }
    }).catch(e => showToast("❌ فشل إضافة الرد"));
};

window.likeComment = async function(postId, commentId) {
    const userId = auth.currentUser?.uid || 'user1';
    const commentRef = doc(db, "posts", postId, "comments", commentId);
    try {
        const docSnap = await getDoc(commentRef);
        if (!docSnap.exists()) return;
        const data = docSnap.data();
        const likes = data.likes || [];
        if (likes.includes(userId)) {
            await updateDoc(commentRef, { likes: arrayRemove(userId) });
        } else {
            await updateDoc(commentRef, { likes: arrayUnion(userId) });
        }
    } catch (e) { console.error(e); }
};
```

The legacy web file also has browser audio recording code beginning with `toggleAudioRecording`; it is excluded from the active Flutter graph and is not used by `lib/`.

## 19. DEPENDENCY GRAPH

### Active Flutter graph

```text
FeedScreen
  ↓ constructs
PostCard
  ↓ tap comment action, only when AuthProvider.currentUser != null
_showComments()
  ↓ showModalBottomSheet + StatefulBuilder
CommentService.commentsStream(post.id)
  ↓ Firestore snapshots
posts/{postId}/comments
  ↓ Comment.fromFirestore
CommentSection
  ↓ groups replyToCommentId and renders text/audio
Reply button
  ↓ local replyToComment state
TextField or long-press microphone
  ↓ CommentService.addComment
FirebaseAuth identity validation
  ↓ Firestore transaction
post existence + parent existence + idempotency check
  ↓ transaction.set
posts/{postId}/comments/{commentId}
  ↓ transaction.update
posts/{postId}.commentsCount += 1
  ↓ realtime snapshot
CommentSection/UI update
```

### Detail route graph

```text
PostCard body or external comment notification
  ↓ Navigator.push
PostDetailScreen(postId)
  ↓ PostService.postStream(postId)
Post UI + comments section
  ↓ CommentService.commentsStream(post.id)
CommentSection + _buildInteractiveCommentInput
  ↓ same addComment transaction
Firestore
  ↓ realtime streams
PostDetailScreen rebuilds
```

### Audio branch

```text
Comment input long press
  ↓
AudioCommentService.checkPermission()
  ↓
record/WebAudioRecorder
  ↓
AudioCommentService.stopRecording()
  ↓
MediaService.uploadFile/uploadBytes
  ↓
Cloudflare Worker HTTPS upload endpoint
  ↓
validated audioUrl
  ↓
CommentService.addComment(type: 'audio')
  ↓
CommentSection + audioplayers playback
```

## 20. CURRENT IMPLEMENTATION SUMMARY

- The active Flutter Posts Comments system is implemented in `PostCard`, `PostDetailScreen`, `CommentSection`, `Comment`, and `CommentService`.
- Feed and profile posts enter through `PostCard`; the post body and comment notifications can enter through `PostDetailScreen`.
- Comments are read in realtime from `posts/{postId}/comments`, ordered by `createdAt` descending, with an optional `mediaIndex` filter that is not used by the two active UI call sites.
- Text and audio comments are supported.
- Audio comments are recorded on mobile/web, uploaded through `MediaService`, stored as an HTTPS URL, and played through `audioplayers`.
- Replies are stored as separate comment documents with `replyToCommentId`, `replyToUserId`, and `replyToUsername`; the UI renders them recursively.
- Comment creation validates Firebase authentication, user identity, post existence, non-empty content, audio URL scheme, reply parent existence and client request ID reuse.
- Comment creation and `commentsCount` increment occur in one Firestore transaction.
- Post comment counts are initialized to zero on post creation and displayed by `PostCard`.
- There is no active Flutter comment pagination, edit, delete, report, moderation UI, comment like state, comment like count, or comment notification creation.
- The methods named `CommentService.addLike/removeLike` modify parent post likes, not comment likes.
- There is no dedicated comment Provider, controller, Bloc, Riverpod state, GetX state, repository or comment-specific test suite.
- Profile avatars are not rendered in `CommentSection`; only the username is clickable and routes to `ProfileScreen`.
- The only discovered Firestore rules for comments are in the test fixture under `test/services/ZAMEL/firestore.rules`; no root production rules file was found.
- A separate legacy JavaScript comments implementation exists under `test/services/ZAMEL/index.html`. It includes comment likes, embedded replies, admin deletion, notification creation and browser audio recording, but it is not imported by the active Flutter application and uses a different document shape in places.

### Inspection counts

- Files inspected: **20** repository files, including 18 active/shared Flutter dependency files and the two legacy/reference files used for repository-wide verification.
- Files found related to Posts Comments: **18** active/shared Flutter files, plus the two legacy/reference files listed above.
- Audio Comments: **FOUND** in the active Flutter implementation.
