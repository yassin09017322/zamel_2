import 'package:cloud_firestore/cloud_firestore.dart';

class AtyaafVideo {
  final String id;
  final String userId;
  final String videoUrl;
  final String thumbnailUrl;
  final String title;
  final String description;
  final String relatedContentRef;
  final int likesCount;
  final int viewsCount;
  final String publicId;
  final String caption;
  final DateTime? createdAt;

  DateTime get timestamp => createdAt ?? DateTime.now();

  const AtyaafVideo({
    required this.id,
    this.userId = '',
    required this.videoUrl,
    required this.thumbnailUrl,
    required this.title,
    required this.description,
    required this.relatedContentRef,
    this.likesCount = 0,
    this.viewsCount = 0,
    this.publicId = '',
    this.caption = '',
    this.createdAt,
  });

  factory AtyaafVideo.fromFirestore(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data() ?? <String, dynamic>{};
    final timestampData = data['createdAt'] ?? data['timestamp'];
    final captionText = (data['caption'] as String?) ?? (data['description'] as String?) ?? '';
    final titleText = (data['title'] as String?) ?? (captionText.isNotEmpty ? captionText : 'Atyaaf');
    final likesValue = data['likes'] ?? data['likesCount'];
    final viewsValue = data['views'] ?? data['viewsCount'];

    return AtyaafVideo(
      id: snapshot.id,
      userId: (data['userId'] as String?) ?? '',
      videoUrl: (data['videoUrl'] as String?) ?? '',
      thumbnailUrl: (data['thumbnailUrl'] as String?) ?? '',
      title: titleText,
      description: captionText,
      relatedContentRef: (data['relatedContentRef'] as String?) ?? 'home',
      likesCount: likesValue is int ? likesValue : 0,
      viewsCount: viewsValue is int ? viewsValue : 0,
      publicId: (data['publicId'] as String?) ?? '',
      caption: captionText,
      createdAt: timestampData is Timestamp ? timestampData.toDate() : null,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'videoUrl': videoUrl,
      'thumbnailUrl': thumbnailUrl,
      'title': title,
      'description': description,
      'caption': caption,
      'relatedContentRef': relatedContentRef,
      'likesCount': likesCount,
      'likes': likesCount,
      'viewsCount': viewsCount,
      'views': viewsCount,
      'publicId': publicId,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}