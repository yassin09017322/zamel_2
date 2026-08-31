import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationItem {
  final String id;
  final String senderId;
  final String receiverId;
  final String type;
  final String referenceId;
  final String roomId;
  final bool isRead;
  final DateTime timestamp;

  NotificationItem({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.type,
    required this.referenceId,
    required this.roomId,
    required this.isRead,
    required this.timestamp,
  });

  factory NotificationItem.fromFirestore(DocumentSnapshot<Map<String, dynamic>> snapshot) {
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
      isRead: data['isRead'] as bool? ?? false,
      timestamp: date,
    );
  }
}
