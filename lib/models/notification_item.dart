import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationItem {
  final String id;
  final String senderId;
  final String receiverId;
  final String type;
  final String referenceId;
  final String roomId;
  final String groupId;
  final String channelId;
  final String postId;
  final String commentId;
  final String parentCommentId;
  final bool isRead;
  final DateTime timestamp;

  NotificationItem({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.type,
    required this.referenceId,
    required this.roomId,
    required this.groupId,
    required this.channelId,
    required this.postId,
    required this.commentId,
    required this.parentCommentId,
    required this.isRead,
    required this.timestamp,
  });

  factory NotificationItem.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? <String, dynamic>{};
    final timestampValue = data['timestamp'];
    DateTime date;
    if (timestampValue is Timestamp) {
      date = timestampValue.toDate();
    } else if (timestampValue is DateTime) {
      date = timestampValue;
    } else {
      date = DateTime.now();
    }

    return NotificationItem(
      id: snapshot.id,
      senderId: data['senderId'] as String? ?? '',
      receiverId: data['receiverId'] as String? ?? '',
      type: data['type'] as String? ?? 'system_alert',
      referenceId: data['referenceId'] as String? ?? '',
      roomId: data['roomId'] as String? ?? '',
      groupId: data['groupId'] as String? ?? '',
      channelId: data['channelId'] as String? ?? '',
      postId: data['postId'] as String? ?? '',
      commentId: data['commentId'] as String? ?? '',
      parentCommentId: data['parentCommentId'] as String? ?? '',
      isRead: data['isRead'] as bool? ?? false,
      timestamp: date,
    );
  }
}
