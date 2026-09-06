import 'package:cloud_firestore/cloud_firestore.dart';

class Comment {
  final String id;
  final String postId;
  final String userId;
  final String username;
  final String userPhotoUrl;
  final String text;
  final DateTime timestamp;
  final DateTime? updatedAt;
  final String audioUrl;
  final String publicId;
  final String type;
  final int duration;
  final int mediaIndex;
  final String replyToCommentId;
  final String replyToUserId;
  final String replyToUsername;
  final String rootCommentId;
  final int likesCount;
  final int repliesCount;
  final bool isEdited;
  final bool isDeleted;
  final bool isLikedByCurrentUser;

  Comment({
    required this.id,
    this.postId = '',
    required this.userId,
    required this.username,
    this.userPhotoUrl = '',
    required this.text,
    required this.timestamp,
    this.updatedAt,
    this.audioUrl = '',
    this.publicId = '',
    this.type = 'text',
    this.duration = 0,
    this.mediaIndex = 0,
    this.replyToCommentId = '',
    this.replyToUserId = '',
    this.replyToUsername = '',
    this.rootCommentId = '',
    this.likesCount = 0,
    this.repliesCount = 0,
    this.isEdited = false,
    this.isDeleted = false,
    this.isLikedByCurrentUser = false,
  });

  factory Comment.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? <String, dynamic>{};
    final timestampValue =
        data['createdAt'] ?? data['timestamp'] ?? data['updatedAt'];
    DateTime date;
    if (timestampValue is Timestamp) {
      date = timestampValue.toDate();
    } else if (timestampValue is DateTime) {
      date = timestampValue;
    } else if (timestampValue is String) {
      date = DateTime.tryParse(timestampValue) ?? DateTime.now();
    } else {
      date = DateTime.now();
    }

    DateTime? updatedAt;
    final updatedAtValue = data['updatedAt'];
    if (updatedAtValue is Timestamp) {
      updatedAt = updatedAtValue.toDate();
    } else if (updatedAtValue is DateTime) {
      updatedAt = updatedAtValue;
    } else if (updatedAtValue is String) {
      updatedAt = DateTime.tryParse(updatedAtValue);
    }

    int readInt(String key) {
      final value = data[key];
      return value is num ? value.toInt() : 0;
    }

    int parsedMediaIndex = 0;
    if (data['mediaIndex'] is int) {
      parsedMediaIndex = data['mediaIndex'] as int;
    } else if (data['mediaIndex'] is num) {
      parsedMediaIndex = (data['mediaIndex'] as num).toInt();
    }

    return Comment(
      id: snapshot.id,
      postId: data['postId'] as String? ?? '',
      userId: data['userId'] as String? ?? '',
      username: data['username'] as String? ?? 'مستخدم',
      userPhotoUrl: data['userPhotoUrl'] as String? ?? '',
      text: data['text'] as String? ?? '',
      timestamp: date,
      updatedAt: updatedAt,
      audioUrl: data['audioUrl'] as String? ?? '',
      publicId: data['publicId'] as String? ?? '',
      type: data['type'] as String? ?? 'text',
      duration: data['duration'] is num ? (data['duration'] as num).toInt() : 0,
      mediaIndex: parsedMediaIndex,
      replyToCommentId: data['replyToCommentId'] as String? ?? '',
      replyToUserId: data['replyToUserId'] as String? ?? '',
      replyToUsername: data['replyToUsername'] as String? ?? '',
      rootCommentId: data['rootCommentId'] as String? ?? '',
      likesCount: readInt('likesCount'),
      repliesCount: readInt('repliesCount'),
      isEdited: data['isEdited'] as bool? ?? false,
      isDeleted: data['isDeleted'] as bool? ?? false,
    );
  }

  Comment copyWith({
    String? text,
    DateTime? updatedAt,
    int? likesCount,
    int? repliesCount,
    bool? isEdited,
    bool? isDeleted,
    bool? isLikedByCurrentUser,
  }) {
    return Comment(
      id: id,
      postId: postId,
      userId: userId,
      username: username,
      userPhotoUrl: userPhotoUrl,
      text: text ?? this.text,
      timestamp: timestamp,
      updatedAt: updatedAt ?? this.updatedAt,
      audioUrl: audioUrl,
      publicId: publicId,
      type: type,
      duration: duration,
      mediaIndex: mediaIndex,
      replyToCommentId: replyToCommentId,
      replyToUserId: replyToUserId,
      replyToUsername: replyToUsername,
      rootCommentId: rootCommentId,
      likesCount: likesCount ?? this.likesCount,
      repliesCount: repliesCount ?? this.repliesCount,
      isEdited: isEdited ?? this.isEdited,
      isDeleted: isDeleted ?? this.isDeleted,
      isLikedByCurrentUser: isLikedByCurrentUser ?? this.isLikedByCurrentUser,
    );
  }
}
