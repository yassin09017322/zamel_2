import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';

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
    await FirebaseFirestore.instance.collection('posts').doc(postId).delete();
  }

  Future<void> _deleteStory(String storyId) async {
    await FirebaseFirestore.instance.collection('stories').doc(storyId).delete();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final currentUser = authProvider.currentUser;

    if (currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('لوحة الإدارة')),
        body: const Center(child: Text('الرجاء تسجيل الدخول للوصول إلى لوحة الإدارة.')),
      );
    }

    if (currentUser.role != 'admin') {
      return Scaffold(
        appBar: AppBar(title: const Text('لوحة الإدارة')),
        body: const Center(child: Text('عذراً، هذه الصفحة متاحة للمشرفين فقط.')),
      );
    }

    final usersQuery = FirebaseFirestore.instance.collection('users').orderBy('createdAt', descending: true);
    final postsQuery = FirebaseFirestore.instance.collection('posts').orderBy('timestamp', descending: true);
    final storiesQuery = FirebaseFirestore.instance.collection('stories').orderBy('timestamp', descending: true);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('لوحة الإدارة'),
          centerTitle: true,
          bottom: const TabBar(
            tabs: [
              Tab(text: 'المستخدمون'),
              Tab(text: 'المنشورات'),
              Tab(text: 'القصص'),
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
                  return Center(child: Text('حدث خطأ في جلب المستخدمين: ${snapshot.error}'));
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(child: Text('لا يوجد مستخدمين حتى الآن.'));
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
                                Chip(label: Text('متابعين ${followers.length}')),
                                Chip(label: Text('نقاط $points')),
                                if (!canPost) Chip(label: const Text('ممنوع من النشر'), backgroundColor: Colors.orange.shade100),
                                if (isBanned) Chip(label: const Text('محظور'), backgroundColor: Colors.red.shade100),
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
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text(isBanned ? 'تم رفع الحظر عن المستخدم' : 'تم حظر المستخدم')),
                                      );
                                    },
                                    child: Text(isBanned ? 'رفع الحظر' : 'حظر المستخدم'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () async {
                                      await _togglePosting(userId, !canPost);
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text(canPost ? 'تم تعطيل النشر عن المستخدم' : 'تم تفعيل النشر للمستخدم')),
                                      );
                                    },
                                    child: Text(canPost ? 'تعطيل النشر' : 'تفعيل النشر'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () async {
                                      await _toggleAdmin(userId, role != 'admin');
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text(role != 'admin' ? 'تم ترقية المستخدم إلى مشرف' : 'تم خفض المستخدم إلى مستخدم عادي')),
                                      );
                                    },
                                    child: Text(role != 'admin' ? 'ترقية' : 'خفض رتبة'),
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
                  return Center(child: Text('حدث خطأ في جلب المنشورات: ${snapshot.error}'));
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(child: Text('لا توجد منشورات حتى الآن.'));
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
                  return Center(child: Text('حدث خطأ في جلب القصص: ${snapshot.error}'));
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(child: Text('لا توجد قصص حتى الآن.'));
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
