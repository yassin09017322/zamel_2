import 'dart:async';
import 'package:zamel_appp/src/platform_file.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/post.dart';
import '../models/story.dart';
import '../providers/auth_provider.dart';
import '../providers/feed_provider.dart';
import '../providers/settings_provider.dart';
import '../services/media_service.dart';
import '../services/post_service.dart';
import '../services/story_service.dart';
import '../widgets/create_post_widget.dart';
import '../widgets/post_card.dart';
import '../widgets/story_upload_widget.dart';
import 'story_viewer_screen.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final StoryService _storyService = StoryService();
  final ImagePicker _picker = ImagePicker();
  final Set<String> _hiddenStoryUsers = <String>{};

  Future<void> _handleRefresh() async {
    setState(() {});
    await Future.delayed(const Duration(seconds: 1));
  }

  Future<void> _showStoryUploadSheet(BuildContext context) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.currentUser;
    if (user == null || !user.canPost) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('عذراً، لا يمكنك النشر حالياً.')));
      return;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: Container(
              color: Theme.of(context).scaffoldBackgroundColor,
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('رفع قصة جديدة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final String? storyText = await _askTextStory(context);
                      if (storyText == null || storyText.trim().isEmpty) return;

                      final int? durationSelected = await _askStoryDuration(context, 24);
                      if (durationSelected == null) return;

                      if (!mounted) return;

                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => const Center(child: CircularProgressIndicator(color: Color(0xFFE94057))),
                      );

                      try {
                        await _storyService.addStory(
                          userId: user.id,
                          username: user.username,
                          imageUrl: '',
                          mediaType: 'text',
                          text: storyText.trim(),
                          expireHours: durationSelected,
                        );

                        if (!mounted) return;
                        Navigator.pop(context);
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم رفع القصة النصية بنجاح 🎉')));
                      } catch (e) {
                        if (!mounted) return;
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('حدث خطأ أثناء رفع القصة النصية: $e')));
                      }
                    },
                    icon: const Icon(Icons.text_fields, color: Colors.white),
                    label: const Text('قصة نصية', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5C4DA5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 12),
                  StoryUploadWidget(
                    onUpload: ({file, bytes, fileName, cloudUrl, required String mediaType}) async {
                      final mediaService = MediaService();
                      final String uploadedUrl;
                      final bool isVideo = mediaType == 'video';

                      if (kIsWeb && bytes != null) {
                        uploadedUrl = await mediaService.uploadBytes(
                          bytes,
                          fileName ?? 'story_media',
                          isVideo: isVideo,
                        );
                      } else if (file != null && !kIsWeb) {
                        uploadedUrl = await mediaService.uploadFile(
                          file,
                          isVideo: isVideo,
                          explicitFileName: fileName,
                        );
                      } else if (bytes != null) {
                        uploadedUrl = await mediaService.uploadBytes(
                          bytes,
                          fileName ?? 'story_media',
                          isVideo: isVideo,
                        );
                      } else if (cloudUrl != null && cloudUrl.isNotEmpty) {
                        uploadedUrl = cloudUrl;
                      } else {
                        throw Exception('لم يتم توفير ملف أو رابط صالح');
                      }

                      await _storyService.addStory(
                        userId: user.id,
                        username: user.username,
                        imageUrl: uploadedUrl,
                        mediaType: mediaType,
                        expireHours: 24,
                      );
                      if (mounted) {
                        Navigator.pop(context);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<String?> _askTextStory(BuildContext context) async {
    final TextEditingController controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('اكتب قصة', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                maxLines: 6,
                minLines: 3,
                decoration: const InputDecoration(
                  hintText: 'اكتب نص القصة هنا...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE94057),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('رفع القصة', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<int?> _askStoryDuration(BuildContext context, int initialDuration) async {
    int selectedDuration = initialDuration;
    return showDialog<int>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('مدة ظهور القصة', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('اختر مدة ظهور القصة قبل رفعها:'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [24, 48, 72].map((hours) {
                  final selected = hours == selectedDuration;
                  return ChoiceChip(
                    label: Text('$hours ساعة'),
                    selected: selected,
                    onSelected: (_) {
                      selectedDuration = hours;
                      Navigator.pop(ctx, hours);
                    },
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('إلغاء')),
          ],
        ),
      ),
    );
  }

  void _openCreatePostScreen(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.currentUser;
    
    if (user == null || !user.canPost) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('عذراً، لا يمكنك النشر حالياً.')));
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, 
      useSafeArea: true, 
      backgroundColor: Colors.transparent,
      builder: (context) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: CreatePostWidget(
            onPublish: (text, isTemp, loc, mediaType, mediaData, localFile, webBytes, mediaFileName, privacy, categoryId, mediaFiles) async {
              if (categoryId == null || categoryId.trim().isEmpty) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('category_required'.tr())),
                  );
                }
                return;
              }

              final primaryMediaType = mediaFiles != null && mediaFiles.isNotEmpty ? mediaFiles.first['mediaType']?.toString() ?? mediaType : mediaType;
              final primaryMediaData = mediaFiles != null && mediaFiles.isNotEmpty ? mediaFiles.first['url']?.toString() ?? mediaData : mediaData;

              await PostService.publishPost(
                userId: user.id,
                username: user.username,
                text: text,
                isTemporary: isTemp,
                location: loc,
                mediaType: primaryMediaType,
                mediaData: primaryMediaData,
                categoryId: categoryId,
                mediaFiles: mediaFiles,
                privacy: privacy,
              );
              
              await PostService.addPoints(user.id, 5);
              
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('publish_success'.tr())));
              }
            },
          ),
        );
      },
    );
  }

  Widget _buildAddStoryCard(BuildContext context) {
    return GestureDetector(
      onTap: () => _showStoryUploadSheet(context),
      child: Container(
        width: 100,
        margin: const EdgeInsets.only(left: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF8A2387), Color(0xFFE94057), Color(0xFFF27121)], 
            begin: Alignment.topLeft, 
            end: Alignment.bottomRight
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [BoxShadow(color: const Color(0xFFE94057).withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1.5)),
              child: const Icon(Icons.add, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 12),
            const Text('إضافة قصة', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildUserStoryCard(BuildContext context, Story story, List<Story> storiesGroup) {
    return GestureDetector(
      onTap: () {
        final relevantStories = storiesGroup.where((item) => item.userId == story.userId).toList();
        if (relevantStories.isEmpty) {
          relevantStories.add(story);
        }
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => StoryViewerScreen(
            stories: relevantStories,
            initialIndex: relevantStories.indexWhere((item) => item.id == story.id),
            isOwner: story.userId == Provider.of<AuthProvider>(context, listen: false).currentUser?.id,
            onHideStoryUser: (userId) {
              setState(() {
                _hiddenStoryUsers.add(userId);
              });
            },
          ),
        ));
      },
      child: Container(
        width: 100,
        margin: const EdgeInsets.only(left: 12),
        child: Column(
          children: [
            Container(
              height: 110, width: 100, padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF8A2387), Color(0xFFE94057), Color(0xFFF27121)], begin: Alignment.topRight, end: Alignment.bottomLeft), 
                borderRadius: BorderRadius.circular(24)
              ),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, borderRadius: BorderRadius.circular(22)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: story.mediaType == 'text'
                      ? Container(
                          color: const Color(0xFF4C2C72),
                          padding: const EdgeInsets.all(12),
                          child: Center(
                            child: Text(
                              story.text.isNotEmpty ? story.text : 'قصة نصية',
                              textAlign: TextAlign.center,
                              maxLines: 6,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.3),
                            ),
                          ),
                        )
                      : Image.network(story.imageUrl, fit: BoxFit.cover, errorBuilder: (_,__,___) => const Icon(Icons.broken_image)),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(child: Text(story.username, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
                if (story.isVerified) ...[const SizedBox(width: 4), const Icon(Icons.verified, color: Color(0xFF1DA1F2), size: 14)],
              ],
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final feedProvider = Provider.of<FeedProvider>(context);
    final settingsProvider = context.watch<SettingsProvider>();
    final selectedMode = settingsProvider.feedMode;

    final isArabic = context.locale.languageCode == 'ar';

    return Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: RefreshIndicator(
        onRefresh: _handleRefresh,
        color: const Color(0xFFE94057),
        backgroundColor: Colors.white,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('القصص', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.add_box_rounded, size: 28, color: Colors.black87),
                      tooltip: 'إنشاء منشور جديد',
                      onPressed: () => _openCreatePostScreen(context), 
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 145,
                child: StreamBuilder<List<Story>>(
                  stream: _storyService.storiesStream(),
                  builder: (context, snapshot) {
                    final stories = snapshot.data ?? [];
                    final visibleStories = stories.where((story) => !_hiddenStoryUsers.contains(story.userId)).toList();
                    final groupedStories = StoryService.groupStoriesByUser(visibleStories);
                    return ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      scrollDirection: Axis.horizontal,
                      itemCount: groupedStories.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) return _buildAddStoryCard(context);
                        final group = groupedStories[index - 1];
                        return _buildUserStoryCard(context, group.first, group);
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Divider(color: Colors.grey[200], thickness: 6),
              const SizedBox(height: 8),
              StreamBuilder<List<Post>>(
                stream: feedProvider.postsStream(categoryId: selectedMode),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(padding: EdgeInsets.all(40.0), child: Center(child: CircularProgressIndicator(color: Color(0xFF5B6CFF))));
                  }
                  if (snapshot.hasError) {
                    return Padding(padding: const EdgeInsets.all(20.0), child: Center(child: Text('حدث خطأ\n${snapshot.error}', textAlign: TextAlign.center)));
                  }
                  
                  final posts = snapshot.data ?? [];
                  
                  if (posts.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(40.0),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.post_add, size: 60, color: Colors.grey),
                            SizedBox(height: 16),
                            Text('لا توجد منشورات حتى الآن.\nكن أول من يشارك أفكاره مع مجتمع زامل!', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 16)),
                          ],
                        ),
                      ),
                    );
                  }
                  
                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    itemCount: posts.length,
                    separatorBuilder: (context, index) => Divider(color: Colors.grey[200], thickness: 6, height: 24),
                    itemBuilder: (context, index) => PostCard(post: posts[index]),
                  );
                },
              ),
              const SizedBox(height: 100), 
            ],
          ),
        ),
      ),
    );
  }
}
