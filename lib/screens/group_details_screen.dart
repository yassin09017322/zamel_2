import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/group.dart';
import '../models/group_post.dart';
import '../providers/auth_provider.dart';
import '../services/group_service.dart';
import '../widgets/media_preview.dart';

class GroupDetailsScreen extends StatefulWidget {
  final String groupId;

  const GroupDetailsScreen({super.key, required this.groupId});

  @override
  State<GroupDetailsScreen> createState() => _GroupDetailsScreenState();
}

class _GroupDetailsScreenState extends State<GroupDetailsScreen> {
  final GroupService _groupService = GroupService();
  final TextEditingController _postController = TextEditingController();
  bool _isPosting = false;
  Uint8List? _selectedMediaBytes;
  String? _selectedMediaPath;
  String _selectedMediaName = '';
  String _selectedMediaType = 'none';
  double _uploadProgress = 0;

  bool get _hasSelectedMedia =>
      _selectedMediaBytes != null || _selectedMediaPath != null;

  Future<List<String>> _pendingJoinRequests(String groupId) {
    return _groupService.pendingJoinRequests(groupId);
  }

  Future<void> _respondToJoinRequest(
    String groupId,
    String userId, {
    required bool accept,
  }) async {
    try {
      if (accept) {
        await _groupService.acceptJoinRequest(groupId: groupId, userId: userId);
      } else {
        await _groupService.rejectJoinRequest(groupId: groupId, userId: userId);
      }
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    }
  }

  @override
  void dispose() {
    _postController.dispose();
    super.dispose();
  }

  Future<void> _pickMedia({required bool isVideo}) async {
    if (_isPosting) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: isVideo ? FileType.video : FileType.image,
        allowCompression: true,
        withData: kIsWeb,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final path = file.path?.trim();
      if (file.bytes == null && (path == null || path.isEmpty)) {
        throw Exception('تعذر الوصول إلى الملف المختار');
      }

      if (!mounted) return;
      setState(() {
        _selectedMediaBytes = file.bytes;
        _selectedMediaPath = path;
        _selectedMediaName = file.name.trim();
        _selectedMediaType = isVideo ? 'video' : 'image';
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر اختيار الوسائط: $error')),
        );
      }
    }
  }

  void _clearSelectedMedia({bool force = false}) {
    if (_isPosting && !force) return;
    setState(() {
      _selectedMediaBytes = null;
      _selectedMediaPath = null;
      _selectedMediaName = '';
      _selectedMediaType = 'none';
      _uploadProgress = 0;
    });
  }

  Future<void> _toggleMembership(Group group) async {
    final userId = context.read<AuthProvider>().currentUser?.id;
    if (userId == null) return;

    try {
      final isMember = group.memberIds.contains(userId);
      if (isMember) {
        await _groupService.leaveGroup(group.id);
      } else {
        await _groupService.joinGroup(group.id);
      }
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    }
  }

  Future<void> _publishPost(String groupId) async {
    final text = _postController.text.trim();
    if (text.isEmpty && !_hasSelectedMedia) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اكتب نصًا أو أضف وسائط للنشر')),
      );
      return;
    }

    setState(() => _isPosting = true);
    try {
      var mediaUrl = '';
      var mediaType = 'none';
      if (_hasSelectedMedia) {
        final uploadResult = await _groupService.uploadGroupMedia(
          bytes: _selectedMediaBytes,
          file: _selectedMediaPath == null
              ? null
              : XFile(_selectedMediaPath!),
          fileName: _selectedMediaName,
          isVideo: _selectedMediaType == 'video',
          onProgress: (progress) {
            if (mounted) {
              setState(() => _uploadProgress = progress.percentComplete);
            }
          },
        );
        if (!uploadResult.success || (uploadResult.url ?? '').trim().isEmpty) {
          throw Exception(uploadResult.error ?? 'فشل رفع الوسائط');
        }
        mediaUrl = uploadResult.url!.trim();
        mediaType = _selectedMediaType;
      }

      await _groupService.createPost(
        groupId: groupId,
        text: text,
        mediaUrl: mediaUrl,
        mediaType: mediaType,
      );
      _postController.clear();
      _clearSelectedMedia(force: true);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPosting = false;
          _uploadProgress = 0;
        });
      }
    }
  }

  Future<void> _togglePrivacy(Group group) async {
    try {
      await _groupService.setGroupPrivacy(
        groupId: group.id,
        isPrivate: !group.isPrivate,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    }
  }

  Future<void> _deletePost(String groupId, String postId) async {
    try {
      await _groupService.deletePost(groupId: groupId, postId: postId);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null) {
      return const Scaffold(
        body: Center(child: Text('يجب تسجيل الدخول أولاً')),
      );
    }

    return StreamBuilder<Group?>(
      stream: _groupService.groupStream(widget.groupId, userId: currentUser.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(child: Text('تعذر تحميل المجموعة: ${snapshot.error}')),
          );
        }

        final group = snapshot.data;
        if (group == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('المجموعة')),
            body: const Center(child: Text('لا يمكن عرض هذه المجموعة')),
          );
        }

        final isOwner = group.ownerId == currentUser.id;
        final isModerator = group.moderators.contains(currentUser.id);
        final isMember = group.memberIds.contains(currentUser.id);

        return Scaffold(
          appBar: AppBar(
            title: Text(group.name),
            backgroundColor: const Color(0xFF5B6CFF),
            foregroundColor: Colors.white,
            actions: [
              if (isOwner)
                IconButton(
                  icon: const Icon(Icons.lock_outline_rounded),
                  tooltip: 'تبديل الخصوصية',
                  onPressed: () => _togglePrivacy(group),
                ),
            ],
          ),
          body: Column(
            children: [
              Container(
                width: double.infinity,
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF0FF),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(
                            Icons.groups_2_rounded,
                            size: 34,
                            color: Color(0xFF5B6CFF),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                group.name,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                group.isPrivate ? 'مجموعة خاصة' : 'مجموعة عامة',
                                style: TextStyle(
                                  color: group.isPrivate
                                      ? Colors.orange.shade800
                                      : Colors.green.shade800,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: () => _toggleMembership(group),
                          icon: Icon(isMember ? Icons.exit_to_app_rounded : Icons.group_add_rounded),
                          label: Text(isMember ? 'مغادرة' : 'انضمام'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      group.description.isEmpty ? 'لا يوجد وصف' : group.description,
                      style: const TextStyle(color: Colors.black87, height: 1.5),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.person_outline_rounded, size: 16, color: Colors.grey),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'المالك: ${group.ownerName}',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Icon(Icons.group_rounded, size: 16, color: Colors.grey),
                        const SizedBox(width: 6),
                        Text(
                          '${group.memberCount} عضو',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if ((isOwner || isModerator) && group.isPrivate)
                FutureBuilder<List<String>>(
                  future: _pendingJoinRequests(group.id),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SizedBox.shrink();
                    }

                    final requests = snapshot.data ?? const <String>[];
                    if (requests.isEmpty) {
                      return const SizedBox.shrink();
                    }

                    return Container(
                      width: double.infinity,
                      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF5B6CFF)),
                              const SizedBox(width: 8),
                              Text(
                                'طلبات الانضمام (${requests.length})',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ...requests.map((userId) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF5F7FF),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      userId,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () => _respondToJoinRequest(
                                      group.id,
                                      userId,
                                      accept: false,
                                    ),
                                    child: const Text('رفض'),
                                  ),
                                  FilledButton(
                                    onPressed: () => _respondToJoinRequest(
                                      group.id,
                                      userId,
                                      accept: true,
                                    ),
                                    child: const Text('قبول'),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    );
                  },
                ),
              if (isOwner || isModerator || isMember)
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    children: [
                      if (_hasSelectedMedia) ...[
                        Row(
                          children: [
                            Icon(
                              _selectedMediaType == 'video'
                                  ? Icons.video_file_outlined
                                  : Icons.image_outlined,
                              color: const Color(0xFF5B6CFF),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _selectedMediaName.isEmpty
                                    ? 'تم اختيار الوسائط'
                                    : _selectedMediaName,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              tooltip: 'إزالة الوسائط',
                              onPressed: _isPosting ? null : _clearSelectedMedia,
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        if (_isPosting)
                          LinearProgressIndicator(value: _uploadProgress),
                      ],
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'إضافة صورة',
                            onPressed: _isPosting
                                ? null
                                : () => _pickMedia(isVideo: false),
                            icon: const Icon(Icons.image_outlined),
                          ),
                          IconButton(
                            tooltip: 'إضافة فيديو',
                            onPressed: _isPosting
                                ? null
                                : () => _pickMedia(isVideo: true),
                            icon: const Icon(Icons.video_library_outlined),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _postController,
                              decoration: const InputDecoration(
                                hintText: 'اكتب منشورًا للمجموعة...',
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: _isPosting
                                ? null
                                : () => _publishPost(group.id),
                            child: _isPosting
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('نشر'),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              else
                const SizedBox.shrink(),
              Expanded(
                child: StreamBuilder<List<GroupPost>>(
                  stream: _groupService.postsStream(group.id),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return Center(child: Text('تعذر تحميل المنشورات: ${snapshot.error}'));
                    }

                    final posts = snapshot.data ?? <GroupPost>[];
                    if (posts.isEmpty) {
                      return const Center(
                        child: Text('لا توجد منشورات في هذه المجموعة بعد'),
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: posts.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final post = posts[index];
                        final canDelete = post.authorId == currentUser.id || isOwner || isModerator;

                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundColor: const Color(0xFF5B6CFF).withOpacity(0.15),
                                    child: const Icon(Icons.person, color: Color(0xFF5B6CFF)),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      post.authorName,
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  if (canDelete)
                                    IconButton(
                                      onPressed: () => _deletePost(group.id, post.id),
                                      icon: const Icon(Icons.delete_outline_rounded),
                                    ),
                                ],
                              ),
                              if (post.text.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Text(post.text, style: const TextStyle(height: 1.5)),
                              ],
                              if (post.mediaUrl.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: MediaPreview(
                                    mediaPath: post.mediaUrl,
                                    mediaType: post.mediaType,
                                    showControls: post.mediaType == 'video',
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Text(
                                '${post.createdAt.day}/${post.createdAt.month}/${post.createdAt.year}',
                                style: const TextStyle(color: Colors.grey, fontSize: 12),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
