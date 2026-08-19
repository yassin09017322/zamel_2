import 'package:cloud_firestore/cloud_firestore.dart';

class ChatRoom {
  final String id;
  final List<String> participants;
  final List<String> participantNames;
  final String lastMessage;
  final DateTime lastTimestamp;

  ChatRoom({
    required this.id,
    required this.participants,
    required this.participantNames,
    required this.lastMessage,
    required this.lastTimestamp,
  });

  factory ChatRoom.fromFirestore(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data() ?? <String, dynamic>{};
    final timestampValue = data['lastTimestamp'];
    DateTime timestamp;
    if (timestampValue is Timestamp) {
      timestamp = timestampValue.toDate();
    } else if (timestampValue is DateTime) {
      timestamp = timestampValue;
    } else {
      timestamp = DateTime.now();
    }

    return ChatRoom(
      id: snapshot.id,
      participants: List<String>.from(data['participants'] as List<dynamic>? ?? []),
      participantNames: List<String>.from(data['participantNames'] as List<dynamic>? ?? []),
      lastMessage: data['lastMessage'] as String? ?? '',
      lastTimestamp: timestamp,
    );
  }
}
