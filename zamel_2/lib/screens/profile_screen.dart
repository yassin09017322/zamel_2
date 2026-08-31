import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_user.dart';
import '../models/post.dart';
import '../providers/auth_provider.dart';
import '../screens/chat_room_screen.dart';
import '../services/chat_service.dart';
import '../services/user_service.dart';
import '../widgets/post_card.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String? userId;

  const ProfileScreen({super.key, this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isProcessing = false;

  Widget _buildStatChip(String label, int value, List<String> userIds, String title) {
    return GestureDetector(
      onTap: userIds.isEmpty ? null : () => _openPeopleListScreen(title: title, userIds: userIds),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.18),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text('$label $value', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Future<void> _openPeopleListScreen({required String title, required List<String> userIds}) async {
    if (userIds.isEmpty) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _PeopleListScreen(title: title, userIds: userIds),
    ));
  }

  Future<void> _handleFollowToggle(AppUser currentUser, AppUser targetUser) async {
    if (currentUser.id == targetUser.id) return;

    setState(() => _isProcessing = true);
    try {
      if (currentUser.following.contains(targetUser.id)) {
        await UserService().unfollowUser(currentUserId: currentUser.id, targetUserId: targetUser.id);
      } else {
        await UserService().followUser(
          currentUserId: currentUser.id,
          targetUserId: targetUser.id,
          currentUsername: currentUser.username,
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فشل تحديث المتابعة')));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _openChat(AppUser currentUser, AppUser targetUser) async {
    try {
      final roomId = await ChatService().createOrGetChatRoom(
        currentUserId: currentUser.id,
        currentUsername: currentUser.username,
        otherUserId: targetUser.id,
        otherUsername: targetUser.username,
      );
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChatRoomScreen(currentUser: currentUser, roomId: roomId),
      ));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر فتح الدردشة')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = context.watch<AuthProvider>().currentUser;
    final profileUserId = widget.userId ?? currentUser?.id;

    if (profileUserId == null || profileUserId.isEmpty) {
      return const Scaffold(body: Center(child: Text('يرجى تسجيل الدخول لعرض الملف الشخصي')));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.userId == null ? 'الملف الشخصي' : 'ملف المستخدم'),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').doc(profileUserId).snapshots(),
        builder: (context, userSnapshot) {
          if (userSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (userSnapshot.hasError) {
            return Center(child: Text('حدث خطأ: ${userSnapshot.error}'));
          }
          final profileDoc = userSnapshot.data;
          if (profileDoc == null || !profileDoc.exists) {
            return const Center(child: Text('لم يتم العثور على المستخدم'));
          }

          final user = AppUser.fromFirestore(profileDoc.data(), profileDoc.id);
          final isOwnProfile = currentUser?.id == user.id;
          final isFollowing = currentUser != null && currentUser.following.contains(user.id);
          final profileImage = (user.photoURL?.isNotEmpty == true) ? user.photoURL! : '';
          final followersCount = user.followersCount > 0 ? user.followersCount : user.followers.length;
          final followingCount = user.followingCount > 0 ? user.followingCount : user.following.length;
          final friendsList = user.followers.where((id) => user.following.contains(id)).toList();
          final friendsCount = user.friendsCount > 0 ? user.friendsCount : friendsList.length;

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('posts').where('userId', isEqualTo: profileUserId).snapshots(),
            builder: (context, postsSnapshot) {
              if (postsSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (postsSnapshot.hasError) {
                return Center(child: Text('حدث خطأ: ${postsSnapshot.error}'));
              }

              final posts = (postsSnapshot.data?.docs ?? []).map((doc) => Post.fromFirestore(doc)).toList()
                ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
              final postsCount = posts.length;

              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF5B6CFF), Color(0xFF2EC7A5)],
                        ),
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, 8))],
                      ),
                      child: Column(
                        children: [
                          Stack(
                            children: [
                              CircleAvatar(
                                radius: 50,
                                backgroundColor: Colors.white24,
                                backgroundImage: profileImage.isNotEmpty ? NetworkImage(profileImage) : null,
                                child: profileImage.isEmpty
                                    ? Text(
                                        user.username.isNotEmpty ? user.username[0].toUpperCase() : 'م',
                                        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                                      )
                                    : null,
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: const Color(0xFF5B6CFF), width: 2),
                                  ),
                                  child: const Icon(Icons.verified_rounded, color: Color(0xFF5B6CFF), size: 18),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            user.username.isNotEmpty ? user.username : 'مستخدم',
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            user.bio.isNotEmpty ? user.bio : 'مرحبا! أنا أستخدم زامل ✨',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildStatChip('متابعين', followersCount, user.followers, 'المتابعين'),
                              _buildStatChip('أتابع', followingCount, user.following, 'أتابع'),
                              _buildStatChip('الأصدقاء', friendsCount, friendsList, 'الأصدقاء'),
                              _buildStatChip('منشورات', postsCount, const <String>[], 'المنشورات'),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (isOwnProfile)
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EditProfileScreen())),
                              icon: const Icon(Icons.mode_edit_outline_rounded),
                              label: const Text('تعديل الملف'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF5B6CFF),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت مشاركة الملف بنجاح'))),
                              icon: const Icon(Icons.share_rounded),
                              label: const Text('مشاركة'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                side: const BorderSide(color: Color(0xFF5B6CFF)),
                                foregroundColor: const Color(0xFF5B6CFF),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                            ),
                          ),
                        ],
                      )
                    else if (currentUser != null)
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isProcessing ? null : () => _handleFollowToggle(currentUser, user),
                              icon: const Icon(Icons.person_add_alt_1_rounded),
                              label: Text(isFollowing ? 'إلغاء المتابعة' : 'متابعة'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF5B6CFF),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _openChat(currentUser, user),
                              icon: const Icon(Icons.message_rounded),
                              label: const Text('رسالة'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                side: const BorderSide(color: Color(0xFF5B6CFF)),
                                foregroundColor: const Color(0xFF5B6CFF),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.person_outline_rounded, color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 8),
                              Text('معلومات الحساب', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          const Divider(height: 1),
                          const SizedBox(height: 10),
                          _buildInfoRow(Icons.work_outline_rounded, 'العمل', user.work),
                          _buildInfoRow(Icons.location_on_outlined, 'الموقع', user.location),
                          _buildInfoRow(Icons.sports_esports_outlined, 'الهواية', user.hobby),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(Icons.grid_on_rounded, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        Text('المنشورات', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (posts.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: const Center(child: Text('لا توجد منشورات بعد.')),
                      )
                    else
                      ...posts.map((post) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: PostCard(post: post),
                          )),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(value, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

class _PeopleListScreen extends StatelessWidget {
  final String title;
  final List<String> userIds;

  const _PeopleListScreen({required this.title, required this.userIds});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').where(FieldPath.documentId, whereIn: userIds.take(10).toList()).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('حدث خطأ: ${snapshot.error}'));
          }

          final users = (snapshot.data?.docs ?? []).map((doc) => AppUser.fromFirestore(doc.data(), doc.id)).toList();

          if (users.isEmpty) {
            return const Center(child: Text('لا توجد عناصر بعد.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: users.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final user = users[index];
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))],
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundImage: (user.photoURL?.isNotEmpty == true) ? NetworkImage(user.photoURL!) : null,
                      child: (user.photoURL?.isNotEmpty != true)
                          ? Text(user.username.isNotEmpty ? user.username[0].toUpperCase() : 'م', style: const TextStyle(fontWeight: FontWeight.bold))
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(user.username.isNotEmpty ? user.username : 'مستخدم', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18),
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(userId: user.id))),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
