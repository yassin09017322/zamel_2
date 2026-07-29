import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_user.dart';
import '../providers/auth_provider.dart';
import '../services/call_service.dart';
import '../services/chat_service.dart';
import '../services/user_service.dart';
import '../screens/call_screen.dart';
import 'chat_room_screen.dart';

class UserProfileScreen extends StatefulWidget {
  final String userId;

  const UserProfileScreen({super.key, required this.userId});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final UserService _userService = UserService();
  bool _isProcessing = false;

  Future<void> _startCall(AppUser currentUser, AppUser user, String type) async {
    try {
      final roomId = await ChatService().createOrGetChatRoom(
        currentUserId: currentUser.id,
        currentUsername: currentUser.username,
        otherUserId: user.id,
        otherUsername: user.username,
      );

      final session = await CallService.instance.initiateCall(
        chatId: roomId,
        callerId: currentUser.id,
        callerName: currentUser.username,
        receiverId: user.id,
        receiverName: user.username,
        type: type,
      );

      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CallScreen(session: session),
      ));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل بدء المكالمة: ${error.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = context.watch<AuthProvider>().currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('الملف الشخصي')),
      body: StreamBuilder<AppUser?>(
        stream: _userService.userStream(widget.userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('حدث خطأ: ${snapshot.error}'));
          }
          final user = snapshot.data;
          if (user == null) {
            return const Center(child: Text('لم يتم العثور على المستخدم'));
          }

          final canFollow = currentUser != null && currentUser.id != user.id;
          final isFollowing = currentUser != null && currentUser.following.contains(user.id);

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CircleAvatar(
                  radius: 48,
                  backgroundImage: user.photoURL?.isNotEmpty == true ? NetworkImage(user.photoURL!) : null,
                  child: user.photoURL?.isEmpty == true ? Text(user.username.isNotEmpty ? user.username[0] : 'م', style: const TextStyle(fontSize: 32)) : null,
                ),
                const SizedBox(height: 16),
                Text(user.username, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(user.bio, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStat('متابع', user.followers.length),
                    _buildStat('يتابع', user.following.length),
                    _buildStat('نقاط', user.points),
                  ],
                ),
                const SizedBox(height: 20),
                Text('الموقع: ${user.location}', style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 8),
                Text('العمل: ${user.work}', style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 8),
                Text('الهواية: ${user.hobby}', style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 20),
                if (canFollow)
                  ElevatedButton(
                    onPressed: _isProcessing ? null : () async {
                      
                      setState(() => _isProcessing = true);
                      try {
                        if (isFollowing) {
                          await UserService().unfollowUser(currentUserId: currentUser.id, targetUserId: user.id);
                        } else {
                          await UserService().followUser(currentUserId: currentUser.id, targetUserId: user.id, currentUsername: currentUser.username);
                        }
                        if (mounted) setState(() {});
                      } catch (_) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فشل تحديث المتابعة')));
                      } finally {
                        if (mounted) setState(() => _isProcessing = false);
                      }
                    },
                    child: Text(isFollowing ? 'إلغاء المتابعة' : 'متابعة'),
                  ),
                const SizedBox(height: 12),
                if (currentUser != null && currentUser.id != user.id)
                  Column(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () async {
                          final roomId = await ChatService().createOrGetChatRoom(
                            currentUserId: currentUser.id,
                            currentUsername: currentUser.username,
                            otherUserId: user.id,
                            otherUsername: user.username,
                          );
                          if (!mounted) return;
                          Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatRoomScreen(currentUser: currentUser, roomId: roomId)));
                        },
                        icon: const Icon(Icons.chat),
                        label: const Text('دردشة'),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        alignment: WrapAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () async {
                              await _startCall(currentUser, user, 'audio');
                            },
                            icon: const Icon(Icons.call),
                            label: const Text('مكالمة صوتية'),
                          ),
                          ElevatedButton.icon(
                            onPressed: () async {
                              await _startCall(currentUser, user, 'video');
                            },
                            icon: const Icon(Icons.videocam),
                            label: const Text('مكالمة فيديو'),
                          ),
                        ],
                      ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStat(String label, int value) {
    return Column(
      children: [
        Text('$value', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.grey)),
      ],
    );
  }
}
