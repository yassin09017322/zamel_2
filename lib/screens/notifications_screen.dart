import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/notification_item.dart';
import '../providers/auth_provider.dart';
import '../screens/chat_room_screen.dart';
import '../screens/post_detail_screen.dart';
import '../screens/user_profile_screen.dart';
import '../services/notification_service.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final userId = context.select<AuthProvider, String?>((provider) => provider.currentUser?.id);
    if (userId == null) {
      return const Center(child: Text('يرجى تسجيل الدخول لعرض الإشعارات'));
    }

    final notificationsQuery = FirebaseFirestore.instance
        .collection('Notifications')
        .where('receiverId', isEqualTo: userId)
        .orderBy('timestamp', descending: true);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: notificationsQuery.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('حدث خطأ في الإشعارات: ${snapshot.error}'));
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(child: Text('لا توجد إشعارات جديدة')); 
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          itemCount: docs.length,
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final item = NotificationItem.fromFirestore(docs[index]);
            final currentUser = Provider.of<AuthProvider>(context, listen: false).currentUser;

            return Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: ListTile(
                title: Text(_notificationText(item.type)),
                subtitle: Text(item.referenceId.isNotEmpty ? 'مرجع: ${item.referenceId}' : ''),
                trailing: Text(_formatTimestamp(item.timestamp)),
                leading: item.isRead ? null : const Icon(Icons.fiber_manual_record, size: 12, color: Colors.blue),
                onTap: () async {
                  await NotificationService().markAsRead(item.id);

                  if (item.type == 'follow' || item.type == 'friend_request') {
                    if (item.senderId.isNotEmpty) {
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => UserProfileScreen(userId: item.senderId)));
                    }
                    return;
                  }

                  if (item.referenceId.isNotEmpty && (item.type == 'comment' || item.type == 'like' || item.type == 'post_update')) {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PostDetailScreen(postId: item.referenceId)));
                    return;
                  }

                  if (item.roomId.isNotEmpty && currentUser != null) {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatRoomScreen(currentUser: currentUser, roomId: item.roomId)));
                    return;
                  }
                },
              ),
            );
          },
        );
      },
    );
  }

  String _notificationText(String type) {
    switch (type) {
      case 'comment':
        return 'أضاف تعليقاً على منشورك';
      case 'like':
        return 'أعجب بمنشورك';
      case 'follow':
        return 'بدأ متابعتك';
      case 'friend_request':
        return 'أرسل لك طلب صداقة';
      case 'live_invite':
        return 'دعوة للبث المباشر';
      default:
        return 'إشعار جديد';
    }
  }

  String _formatTimestamp(dynamic timestampValue) {
    if (timestampValue == null) return '';
    DateTime date;
    if (timestampValue is Timestamp) {
      date = timestampValue.toDate();
    } else if (timestampValue is DateTime) {
      date = timestampValue;
    } else {
      return '';
    }
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inHours < 1) return '${diff.inMinutes} د';
    if (diff.inDays < 1) return '${diff.inHours} س';
    return '${date.day}/${date.month}/${date.year}';
  }
}
