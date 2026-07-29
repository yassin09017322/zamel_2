import 'package:cloud_firestore/cloud_firestore.dart';

class Comment {
  final String id;
  final String userId;
  final String username;
  final String text;
  final DateTime timestamp;
  final String audioUrl;
  final String publicId;
  final String type;
  final int duration;

  Comment({
    required this.id,
    required this.userId,
    required this.username,
    required this.text,
    required this.timestamp,
    this.audioUrl = '',
    this.publicId = '',
    this.type = 'text',
    this.duration = 0,
  });

  factory Comment.fromFirestore(DocumentSnapshot<Map<String, dynamic>> snapshot) {
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

    return Comment(
      id: snapshot.id,
      userId: data['userId'] as String? ?? '',
      username: data['username'] as String? ?? 'مستخدم',
      text: data['text'] as String? ?? '',
      timestamp: date,
      audioUrl: data['audioUrl'] as String? ?? '',
      publicId: data['publicId'] as String? ?? '',
      type: data['type'] as String? ?? 'text',
      duration: data['duration'] is int ? data['duration'] as int : 0,
    );
  }
}
