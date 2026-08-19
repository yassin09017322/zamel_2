import 'package:cloud_firestore/cloud_firestore.dart';

class AtyaafVideoModel {
  final String id;
  final String videoUrl;
  final String thumbnailUrl;
  final String title;
  final String description;
  final String? relatedContentRef;

  const AtyaafVideoModel({
    required this.id,
    required this.videoUrl,
    required this.thumbnailUrl,
    required this.title,
    required this.description,
    this.relatedContentRef,
  });

  factory AtyaafVideoModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? {};
    return AtyaafVideoModel(
      id: data['id']?.toString() ?? snapshot.id,
      videoUrl: data['videoUrl']?.toString() ?? '',
      thumbnailUrl: data['thumbnailUrl']?.toString() ?? '',
      title: data['title']?.toString() ?? 'بدون عنوان',
      description: data['description']?.toString() ?? '',
      relatedContentRef: data['relatedContentRef']?.toString(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'videoUrl': videoUrl,
      'thumbnailUrl': thumbnailUrl,
      'title': title,
      'description': description,
      'relatedContentRef': relatedContentRef,
    };
  }

  static String buildOptimizedCloudinaryUrl({
    required String cloudName,
    required String publicId,
    String format = 'mp4',
    bool hls = false,
  }) {
    final base = 'https://res.cloudinary.com/$cloudName/video/upload/';
    final transformations = 'f_auto,q_auto,vc_auto';
    final streamSuffix = hls ? 'fl_hls/' : '';
    return '$base$transformations/$streamSuffix$publicId.$format';
  }
}
