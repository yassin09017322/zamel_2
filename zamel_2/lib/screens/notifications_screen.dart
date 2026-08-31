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
      return const Scaffold(
        body: Center(child: Text('يرجى تسجيل الدخول لعرض الإشعارات')),
      );
    }

    final notificationsQuery = FirebaseFirestore.instance
        .collection('Notifications')
        .where('receiverId', isEqualTo: userId)
        .orderBy('timestamp', descending: true);

    return Scaffold(
      backgroundColor: Colors.white, // خلفية بيضاء نقية ستايل فيسبوك
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: notificationsQuery.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF5B6CFF)));
          }
          if (snapshot.hasError) {
            return Center(child: Text('حدث خطأ في الإشعارات: ${snapshot.error}'));
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return _buildEmptyState();
          }
          
          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data();
              final item = NotificationItem.fromFirestore(docs[index]);
              final currentUser = Provider.of<AuthProvider>(context, listen: false).currentUser;

              // استخراج اسم وصورة المرسل من قاعدة البيانات بذكاء (القيم الافتراضية في حال عدم وجودها)
              final senderName = data.containsKey('senderName') ? data['senderName'] : 'مستخدم';
              final senderAvatar = data.containsKey('senderAvatar') ? data['senderAvatar'] : '';

              return InkWell(
                onTap: () async {
                  // جعل الإشعار مقروءاً فور الضغط عليه
                  if (!item.isRead) {
                    await NotificationService().markAsRead(item.id);
                  }

                  if (!context.mounted) return;

                  // التوجيه للملف الشخصي (متابعة أو طلب صداقة)
                  if (item.type == 'follow' || item.type == 'friend_request') {
                    if (item.senderId.isNotEmpty) {
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => UserProfileScreen(userId: item.senderId)));
                    }
                    return;
                  }

                  // التوجيه لتفاصيل المنشور (إعجاب أو تعليق)
                  if (item.referenceId.isNotEmpty && (item.type == 'comment' || item.type == 'like' || item.type == 'post_update')) {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PostDetailScreen(postId: item.referenceId)));
                    return;
                  }

                  // التوجيه لغرفة الدردشة (المكالمات الفائتة والرسائل)
                  if ((item.type == 'call' || item.type == 'missed_call' || item.roomId.isNotEmpty) && currentUser != null) {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatRoomScreen(currentUser: currentUser, roomId: item.roomId)));
                    return;
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    // لون الإشعار غير المقروء الأزرق الفاتح (مثل فيسبوك تماماً)
                    color: item.isRead ? Colors.white : const Color(0xFFE7F3FF),
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade200, width: 1),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // صورة الحساب مع أيقونة نوع الإشعار المتراكبة
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          CircleAvatar(
                            radius: 32,
                            backgroundColor: Colors.grey.shade200,
                            backgroundImage: senderAvatar.isNotEmpty ? NetworkImage(senderAvatar) : null,
                            child: senderAvatar.isEmpty ? const Icon(Icons.person, color: Colors.grey, size: 35) : null,
                          ),
                          Positioned(
                            right: -4,
                            bottom: -4,
                            child: _buildNotificationIcon(item.type),
                          ),
                        ],
                      ),
                      const SizedBox(width: 14),
                      
                      // نص الإشعار والزمن
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildNotificationText(item.type, senderName),
                            const SizedBox(height: 6),
                            Text(
                              _formatTimestamp(item.timestamp),
                              style: TextStyle(
                                fontSize: 13,
                                color: item.isRead ? Colors.grey.shade600 : const Color(0xFF5B6CFF),
                                fontWeight: item.isRead ? FontWeight.normal : FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      // النقطة الزرقاء الجانبية للإشعارات الجديدة
                      if (!item.isRead)
                        Padding(
                          padding: const EdgeInsets.only(top: 12.0, right: 8.0),
                          child: const CircleAvatar(radius: 5, backgroundColor: Color(0xFF5B6CFF)),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ودجت الحالة الفارغة بشكل جميل
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_off_outlined, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text(
            'لا توجد إشعارات جديدة',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black54),
          ),
          const SizedBox(height: 8),
          const Text(
            'عندما يتفاعل الآخرون معك ستظهر إشعاراتك هنا.',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // بناء الأيقونة الدائرية الصغيرة التي توضح نوع التفاعل (مثل فيسبوك)
  Widget _buildNotificationIcon(String type) {
    IconData iconData;
    Color bgColor;

    switch (type) {
      case 'like':
        iconData = Icons.thumb_up_rounded;
        bgColor = const Color(0xFF1877F2); // أزرق فيسبوك
        break;
      case 'comment':
        iconData = Icons.chat_bubble_rounded;
        bgColor = const Color(0xFF28A745); // أخضر للتعليقات
        break;
      case 'follow':
        iconData = Icons.person_add_rounded;
        bgColor = const Color(0xFF1877F2);
        break;
      case 'friend_request':
        iconData = Icons.group_add_rounded;
        bgColor = const Color(0xFFF56036); // برتقالي لطلبات الصداقة
        break;
      case 'call':
      case 'missed_call':
        iconData = Icons.phone_missed_rounded;
        bgColor = const Color(0xFFE41E3F); // أحمر للمكالمات الفائتة
        break;
      case 'live_invite':
        iconData = Icons.videocam_rounded;
        bgColor = const Color(0xFF9C27B0); // بنفسجي للبثوث
        break;
      default:
        iconData = Icons.notifications_rounded;
        bgColor = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2), // حدود بيضاء لفصلها عن الصورة
      ),
      child: Icon(iconData, color: Colors.white, size: 14),
    );
  }

  // بناء نص الإشعار بنظام RichText لجعل اسم المرسل بالخط العريض
  Widget _buildNotificationText(String type, String senderName) {
    String actionText;
    switch (type) {
      case 'comment':
        actionText = ' بالتعليق على منشورك.';
        break;
      case 'like':
        actionText = ' بالإعجاب بمنشورك.';
        break;
      case 'follow':
        actionText = ' بمتابعتك.';
        break;
      case 'friend_request':
        actionText = ' بإرسال طلب صداقة إليك.';
        break;
      case 'live_invite':
        actionText = ' بدعوتك للانضمام إلى البث المباشر الخاص به.';
        break;
      case 'call':
      case 'missed_call':
        actionText = ' حاول الاتصال بك (مكالمة فائتة).';
        break;
      default:
        actionText = ' تفاعل مع حسابك.';
    }

    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 15, color: Colors.black87, fontFamily: 'Segoe UI', height: 1.4),
        children: [
          TextSpan(
            text: senderName, 
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)
          ),
          TextSpan(text: ' قام $actionText'),
        ],
      ),
    );
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
    if (diff.inDays < 7) return 'منذ ${diff.inDays} أيام';
    return '${date.day}/${date.month}/${date.year}';
  }
}
