import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> createNotification({
    required String senderId,
    required String receiverId,
    required String type,
    String referenceId = '',
    String roomId = '',
    bool isRead = false,
  }) async {
    if (senderId == receiverId) return;
    await _firestore.collection('Notifications').add({
      'senderId': senderId,
      'receiverId': receiverId,
      'type': type,
      'referenceId': referenceId,
      'roomId': roomId,
      'isRead': isRead,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> markAsRead(String notificationId) async {
    await _firestore.collection('Notifications').doc(notificationId).update({'isRead': true});
  }
}
