import 'package:cloud_firestore/cloud_firestore.dart';

class Post {
  final String id;
  final String text;
  final String userId;
  final String username;
  final String userProfileImage; // مفيد جداً لعرض صورة الكاتب في التغذية
  final String mediaType;
  final String mediaData;
  final String location;         // تم إضافة الموقع ليتوافق مع شاشة الإنشاء
  final bool isTemporary;        // تم إضافة حالة المنشور المؤقت (قصة/24 ساعة)
  final DateTime timestamp;
  final int commentsCount;
  final List<String> likes;
  final List<String> hashtags;
  final Map<String, dynamic> reactions; // تم تحويلها لـ dynamic لتدعم أنواع تفاعلات مختلفة
  final bool isVerified;
  final String privacy;          // متغير الخصوصية

  Post({
    required this.id,
    required this.text,
    required this.userId,
    required this.username,
    this.userProfileImage = '',
    required this.mediaType,
    required this.mediaData,
    this.location = '',
    this.isTemporary = false,
    required this.timestamp,
    required this.commentsCount,
    required this.likes,
    required this.hashtags,
    required this.reactions,
    this.isVerified = false,
    this.privacy = 'public',
  });

  // دالة القراءة من فايربيس (محمية بالكامل ضد الأخطاء Null-Safety)
  factory Post.fromFirestore(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data() ?? <String, dynamic>{};
    
    // معالجة آمنة للوقت (Timestamp)
    final timestampValue = data['timestamp'];
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

    // معالجة آمنة لعدد التعليقات
    int parsedCommentsCount = 0;
    if (data['commentsCount'] is int) {
      parsedCommentsCount = data['commentsCount'];
    } else if (data['commentsCount'] is num) {
      parsedCommentsCount = data['commentsCount'].toInt();
    }

    // معالجة آمنة للتفاعلات
    Map<String, dynamic> parsedReactions = {};
    if (data['reactions'] is Map) {
      parsedReactions = Map<String, dynamic>.from(data['reactions']);
    }

    // معالجة آمنة للإعجابات
    List<String> parsedLikes = [];
    if (data['likes'] is List) {
      parsedLikes = List<String>.from(data['likes'].map((e) => e.toString()));
    }

    // معالجة آمنة للهاشتاجات
    List<String> parsedHashtags = [];
    if (data['hashtags'] is List) {
      parsedHashtags = List<String>.from(data['hashtags'].map((e) => e.toString()));
    }

    return Post(
      id: snapshot.id,
      text: data['text'] as String? ?? '',
      userId: data['userId'] as String? ?? '',
      username: data['username'] as String? ?? 'مستخدم',
      userProfileImage: data['userProfileImage'] as String? ?? '',
      mediaType: data['mediaType'] as String? ?? 'none',
      mediaData: data['mediaData'] as String? ?? '',
      location: data['location'] as String? ?? '',
      isTemporary: data['isTemporary'] as bool? ?? false,
      timestamp: date,
      commentsCount: parsedCommentsCount,
      likes: parsedLikes,
      hashtags: parsedHashtags,
      reactions: parsedReactions,
      isVerified: data['isVerified'] as bool? ?? false,
      privacy: data['privacy'] as String? ?? 'public',
    );
  }

  // دالة الرفع إلى فايربيس
  Map<String, dynamic> toMap() {
    return {
      'text': text,
      'userId': userId,
      'username': username,
      'userProfileImage': userProfileImage,
      'mediaType': mediaType,
      'mediaData': mediaData,
      'location': location,
      'isTemporary': isTemporary,
      'timestamp': FieldValue.serverTimestamp(),
      'commentsCount': commentsCount,
      'likes': likes,
      'hashtags': hashtags,
      'reactions': reactions,
      'isVerified': isVerified,
      'privacy': privacy,
    };
  }

  // دالة copyWith الاحترافية (مهمة جداً لتحديث حالة الإعجاب والتعليقات في الشاشة مباشرة)
  Post copyWith({
    String? id,
    String? text,
    String? userId,
    String? username,
    String? userProfileImage,
    String? mediaType,
    String? mediaData,
    String? location,
    bool? isTemporary,
    DateTime? timestamp,
    int? commentsCount,
    List<String>? likes,
    List<String>? hashtags,
    Map<String, dynamic>? reactions,
    bool? isVerified,
    String? privacy,
  }) {
    return Post(
      id: id ?? this.id,
      text: text ?? this.text,
      userId: userId ?? this.userId,
      username: username ?? this.username,
      userProfileImage: userProfileImage ?? this.userProfileImage,
      mediaType: mediaType ?? this.mediaType,
      mediaData: mediaData ?? this.mediaData,
      location: location ?? this.location,
      isTemporary: isTemporary ?? this.isTemporary,
      timestamp: timestamp ?? this.timestamp,
      commentsCount: commentsCount ?? this.commentsCount,
      likes: likes ?? this.likes,
      hashtags: hashtags ?? this.hashtags,
      reactions: reactions ?? this.reactions,
      isVerified: isVerified ?? this.isVerified,
      privacy: privacy ?? this.privacy,
    );
  }
}