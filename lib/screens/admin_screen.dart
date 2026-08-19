import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../services/post_service.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  Future<void> _toggleBan(String userId, bool ban) async {
    await FirebaseFirestore.instance.collection('users').doc(userId).update({'isBanned': ban});
  }

  Future<void> _toggleAdmin(String userId, bool makeAdmin) async {
    await FirebaseFirestore.instance.collection('users').doc(userId).update({'role': makeAdmin ? 'admin' : 'user'});
  }

  Future<void> _togglePosting(String userId, bool canPost) async {
    await FirebaseFirestore.instance.collection('users').doc(userId).update({'canPost': canPost});
  }

  Future<void> _deletePost(String postId) async {
    await PostService.deletePost(postId: postId);
  }

  Future<void> _deleteStory(String storyId) async {
    await FirebaseFirestore.instance.collection('stories').doc(storyId).delete();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final currentUser = authProvider.currentUser;
    final l10n = AppLocalizations.of(context);

    if (l10n == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    if (currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.adminTitle)),
        body: Center(child: Text(l10n.adminLoginRequired)),
      );
    }

    if (currentUser.role != 'admin') {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.adminTitle)),
        body: Center(child: Text(l10n.adminRoleRequired)),
      );
    }

    final usersQuery = FirebaseFirestore.instance.collection('users').orderBy('createdAt', descending: true);
    final postsQuery = FirebaseFirestore.instance.collection('posts').orderBy('timestamp', descending: true);
    final storiesQuery = FirebaseFirestore.instance.collection('stories').orderBy('timestamp', descending: true);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.adminTitle),
          centerTitle: true,
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.adminUsersTab),
              Tab(text: l10n.adminPostsTab),
              Tab(text: l10n.adminStoriesTab),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: usersQuery.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text(l10n.adminErrorUsers(snapshot.error.toString())));
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(child: Text(l10n.adminNoUsers));
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final userData = docs[index].data();
                    final userId = docs[index].id;
                    final username = userData['username'] as String? ?? 'مستخدم';
                    final email = userData['email'] as String? ?? '';
                    final role = userData['role'] as String? ?? 'user';
                    final isBanned = userData['isBanned'] as bool? ?? false;
                    final canPost = userData['canPost'] as bool? ?? true;
                    final followers = List<String>.from(userData['followers'] as List<dynamic>? ?? []);
                    final points = userData['points'] as int? ?? 0;

                    return Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 1,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 24,
                                  backgroundColor: Colors.blue.shade700,
                                  child: Text(
                                    username.isNotEmpty ? username[0] : 'م',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(username, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 4),
                                      Text(email, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                                    ],
                                  ),
                                ),
                                Chip(
                                  label: Text(role == 'admin' ? 'مشرف' : 'مستخدم'),
                                  backgroundColor: role == 'admin' ? Colors.amber.shade100 : Colors.grey.shade200,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              children: [
                                Chip(label: Text(l10n.adminFollowers(followers.length))),
                                Chip(label: Text(l10n.adminPoints(points))),
                                if (!canPost) Chip(label: Text(l10n.adminBlockedFromPosting), backgroundColor: Colors.orange.shade100),
                                if (isBanned) Chip(label: Text(l10n.adminBanned), backgroundColor: Colors.red.shade100),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isBanned ? Colors.green : Colors.red,
                                    ),
                                    onPressed: () async {
                                      await _toggleBan(userId, !isBanned);
                                      if (!mounted) return;
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text(isBanned ? l10n.adminUserUnbanSuccess : l10n.adminUserBanSuccess)),
                                      );
                                    },
                                    child: Text(isBanned ? l10n.adminUnbanUser : l10n.adminBanUser),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () async {
                                      await _togglePosting(userId, !canPost);
                                      if (!mounted) return;
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text(canPost ? l10n.adminPostingDisabled : l10n.adminPostingEnabled)),
                                      );
                                    },
                                    child: Text(canPost ? l10n.adminDisablePosting : l10n.adminEnablePosting),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () async {
                                      await _toggleAdmin(userId, role != 'admin');
                                      if (!mounted) return;
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text(role != 'admin' ? l10n.adminPromoted : l10n.adminDemoted)),
                                      );
                                    },
                                    child: Text(role != 'admin' ? l10n.adminUpgrade : l10n.adminDowngrade),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: postsQuery.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text(l10n.adminErrorPosts(snapshot.error.toString())));
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(child: Text(l10n.adminNoPosts));
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final postData = docs[index].data();
                    final postId = docs[index].id;
                    final username = postData['username'] as String? ?? 'مستخدم';
                    final text = postData['text'] as String? ?? '';
                    final likes = List<String>.from(postData['likes'] as List<dynamic>? ?? []);
                    final commentsCount = postData['commentsCount'] as int? ?? 0;
                    final mediaType = postData['mediaType'] as String? ?? 'none';
                    return Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 1,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: Colors.blue.shade700,
                                  child: Text(username.isNotEmpty ? username[0] : 'م', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(child: Text(username, style: const TextStyle(fontWeight: FontWeight.bold))),
                                Chip(label: Text(mediaType)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(text, maxLines: 3, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 12),
                            Wrap(spacing: 8, children: [
                              Chip(label: Text('${likes.length} إعجاب')),
                              Chip(label: Text('$commentsCount تعليق')),
                            ]),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    icon: const Icon(Icons.delete_outline),
                                    label: const Text('حذف المنشور'),
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
                                    onPressed: () async {
                                      await _deletePost(postId);
                                      if (!mounted) return;
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف المنشور')));
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: storiesQuery.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text(l10n.adminErrorStories(snapshot.error.toString())));
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(child: Text(l10n.adminNoStories));
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final storyData = docs[index].data();
                    final storyId = docs[index].id;
                    final username = storyData['username'] as String? ?? 'مستخدم';
                    final mediaType = storyData['mediaType'] as String? ?? 'image';
                    final imageUrl = storyData['image'] as String? ?? '';
                    return Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 1,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: Colors.blue.shade700,
                                  child: Text(username.isNotEmpty ? username[0] : 'م', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(child: Text(username, style: const TextStyle(fontWeight: FontWeight.bold))),
                                Chip(label: Text(mediaType)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (imageUrl.isNotEmpty)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(imageUrl, height: 140, width: double.infinity, fit: BoxFit.cover),
                              ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('حذف القصة'),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
                              onPressed: () async {
                                await _deleteStory(storyId);
                                if (!mounted) return;
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف القصة')));
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
