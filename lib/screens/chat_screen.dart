import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../models/chat_room.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../services/chat_service.dart';
import '../services/engagement_service.dart';
import 'chat_room_screen.dart';
import 'new_chat_screen.dart';
import 'user_search_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  @override
  void initState() {
    super.initState();
    EngagementService.recordActivity();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final currentUser = authProvider.currentUser;

    if (currentUser == null) {
      return const Center(child: Text('الرجاء تسجيل الدخول لعرض الدردشات'));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('الدردشات'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UserSearchScreen()));
            },
          ),
        ],
      ),
      body: StreamBuilder<List<ChatRoom>>(
        stream: ChatService().chatRoomsForUser(currentUser.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('حدث خطأ في تحميل الدردشات: ${snapshot.error}'));
          }
          final rooms = snapshot.data ?? [];
          if (rooms.isEmpty) {
            return const Center(child: Text('لا توجد دردشات بعد. ابدأ محادثة جديدة.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: rooms.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final room = rooms[index];
              final participantNames = room.participantNames;
              final otherName = participantNames.length == 2
                  ? participantNames.firstWhere((name) => name != currentUser.username, orElse: () => participantNames.first)
                  : participantNames.join(', ');

              final otherUserId = room.participants.firstWhere(
                (id) => id != currentUser.id,
                orElse: () => '',
              );

              return ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                tileColor: Colors.grey[100],
                title: Text(otherName.isNotEmpty ? otherName : 'محادثة'),
                subtitle: otherUserId.isNotEmpty
                    ? StreamBuilder<DatabaseEvent>(
                        stream: FirebaseDatabase.instance.ref().child('presence/$otherUserId').onValue,
                        builder: (context, snapshot) {
                          final data = snapshot.data?.snapshot.value as Map<dynamic, dynamic>? ?? <dynamic, dynamic>{};
                          final settingsProvider = context.watch<SettingsProvider>();
                          final sharePresence = settingsProvider.sharePresence;
                          final online = data['online'] == true;
                          DateTime? lastSeen;
                          final lastSeenValue = data['lastSeen'];
                          if (lastSeenValue is int) {
                            lastSeen = DateTime.fromMillisecondsSinceEpoch(lastSeenValue);
                          }
                          final statusText = sharePresence
                              ? (online ? 'متصل الآن' : _formatLastSeen(lastSeen))
                              : 'معلومات التواجد مخفية';
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(statusText, style: TextStyle(fontSize: 12, color: online ? Colors.green : Colors.grey[700])),
                              const SizedBox(height: 2),
                              Text(room.lastMessage.isEmpty ? 'ابدأ المحادثة الآن' : room.lastMessage, maxLines: 1, overflow: TextOverflow.ellipsis),
                            ],
                          );
                        },
                      )
                    : Text(room.lastMessage.isEmpty ? 'ابدأ المحادثة الآن' : room.lastMessage, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Text(_formatTime(room.lastTimestamp)),
                onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ChatRoomScreen(
                      currentUser: currentUser,
                      roomId: room.id,
                    ),
                  ));
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => NewChatScreen(currentUser: currentUser),
          ));
        },
        icon: const Icon(Icons.chat),
        label: const Text('محادثة جديدة'),
      ),
    );
  }

  String _formatLastSeen(DateTime? timestamp) {
    if (timestamp == null) {
      return 'آخر ظهور: غير متاح';
    }
    return 'آخر ظهور ${timeago.format(timestamp, locale: 'ar', clock: DateTime.now())}';
  }

  String _formatTime(DateTime date) {
    final difference = DateTime.now().difference(date);
    if (difference.inDays > 1) return '${difference.inDays} يوم';
    if (difference.inHours >= 1) return '${difference.inHours} س';
    if (difference.inMinutes >= 1) return '${difference.inMinutes} د';
    return 'الآن';
  }
}
