import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../services/chat_service.dart';
import 'chat_room_screen.dart';

class NewChatScreen extends StatelessWidget {
  final AppUser currentUser;

  const NewChatScreen({super.key, required this.currentUser});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إضافة محادثة جديدة')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('فشل تحميل المستخدمين: ${snapshot.error}'));
          }
          final users = snapshot.data?.docs.where((doc) => doc.id != currentUser.id).toList() ?? [];
          if (users.isEmpty) {
            return const Center(child: Text('لا يوجد مستخدمين آخرين لبدء محادثة.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: users.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final doc = users[index];
              final username = doc.data()['username'] as String? ?? 'مستخدم';
              return ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                tileColor: Colors.grey[100],
                title: Text(username),
                subtitle: Text(doc.data()['email'] as String? ?? ''),
                onTap: () async {
                  final roomId = await ChatService().createOrGetChatRoom(
                    currentUserId: currentUser.id,
                    currentUsername: currentUser.username,
                    otherUserId: doc.id,
                    otherUsername: username,
                  );
                  if (!context.mounted) return;
                  Navigator.of(context).pushReplacement(MaterialPageRoute(
                    builder: (_) => ChatRoomScreen(currentUser: currentUser, roomId: roomId),
                  ));
                },
              );
            },
          );
        },
      ),
    );
  }
}
