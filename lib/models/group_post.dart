import 'package:cloud_firestore/cloud_firestore.dart';

class GroupPost {
  final String id;
  final String groupId;
  final String authorId;
  final String authorName;
  final String text;
  final String mediaUrl;
  final String mediaType;
  final DateTime createdAt;
  final List<String> likes;
  final int commentsCount;

  const GroupPost({
    required this.id,
    required this.groupId,
    required this.authorId,
    required this.authorName,
    required this.text,
    required this.mediaUrl,
    required this.mediaType,
    required this.createdAt,
    required this.likes,
    required this.commentsCount,
  });

  factory GroupPost.fromFirestore(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data() ?? <String, dynamic>{};
    final createdAt = data['createdAt'];
    return GroupPost(
      id: snapshot.id,
      groupId: data['groupId'] as String? ?? '',
      authorId: data['authorId'] as String? ?? '',
      authorName: data['authorName'] as String? ?? 'مستخدم',
      text: data['text'] as String? ?? '',
      mediaUrl: data['mediaUrl'] as String? ?? '',
      mediaType: data['mediaType'] as String? ?? 'none',
      createdAt: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
      likes: List<String>.from(data['likes'] ?? const []),
      commentsCount: (data['commentsCount'] as num?)?.toInt() ?? 0,
    );
  }
}
