import 'package:cloud_firestore/cloud_firestore.dart';

class Story {
  final String id;
  final String userId;
  final String username;
  final String imageUrl;
  final String mediaType;
  final DateTime timestamp;
  final bool isVerified;
  final List<Map<String, dynamic>> viewers;
  final List<Map<String, dynamic>> reactions;
  final List<Map<String, dynamic>> replies;

  Story({
    required this.id,
    required this.userId,
    required this.username,
    required this.imageUrl,
    required this.mediaType,
    required this.timestamp,
    this.isVerified = false,
    this.viewers = const [],
    this.reactions = const [],
    this.replies = const [],
  });

  factory Story.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;

    return Story(
      id: doc.id,
      userId: data?['userId'] ?? '',
      username: data?['username'] ?? 'مستخدم',
      imageUrl: data?['imageUrl'] ?? data?['image'] ?? '',
      mediaType: data?['mediaType'] ?? 'image',
      timestamp: data?['timestamp'] != null
          ? (data!['timestamp'] as Timestamp).toDate()
          : DateTime.now(),
      isVerified: data?['isVerified'] ?? false,
      viewers: _parseMaps(data?['viewers']),
      reactions: _parseMaps(data?['reactions']),
      replies: _parseMaps(data?['replies']),
    );
  }

  static List<Map<String, dynamic>> _parseMaps(dynamic source) {
    if (source is List) {
        return source
          .whereType<Map<String, dynamic>>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }
    return [];
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'username': username,
      'imageUrl': imageUrl,
      'image': imageUrl,
      'mediaType': mediaType,
      'timestamp': FieldValue.serverTimestamp(),
      'isVerified': isVerified,
      'viewers': viewers,
      'reactions': reactions,
      'replies': replies,
    };
  }
}