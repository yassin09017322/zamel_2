import 'package:cloud_firestore/cloud_firestore.dart';

class Story {
  final String id;
  final String userId;
  final String username;
  final String imageUrl;
  final String text;
  final String mediaType;
  final DateTime timestamp;
  final DateTime expiresAt;
  final int expireHours;
  final String? originalStoryId;
  final DateTime originalTimestamp;
  final bool isVerified;
  final List<Map<String, dynamic>> viewers;
  final List<Map<String, dynamic>> reactions;
  final List<Map<String, dynamic>> replies;

  Story({
    required this.id,
    required this.userId,
    required this.username,
    required this.imageUrl,
    this.text = '',
    required this.mediaType,
    required this.timestamp,
    required this.expiresAt,
    this.expireHours = 24,
    this.originalStoryId,
    DateTime? originalTimestamp,
    this.isVerified = false,
    this.viewers = const [],
    this.reactions = const [],
    this.replies = const [],
  }) : originalTimestamp = originalTimestamp ?? timestamp;

  bool isActiveAt(DateTime now) => now.toUtc().isBefore(expiresAt.toUtc());

  String get memoryKey => originalStoryId ?? id;

  bool isMemoryFor(DateTime date) {
    final original = originalTimestamp.toUtc();
    final current = date.toUtc();
    if (original.month == current.month && original.day == current.day) {
      return true;
    }
    return original.month == 2 &&
        original.day == 29 &&
        current.month == 2 &&
        current.day == 28 &&
        !_isLeapYear(current.year);
  }

  static bool _isLeapYear(int year) =>
      year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);

  factory Story.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    final timestamp =
        _readTimestamp(data?['timestamp']) ?? DateTime.now().toUtc();
    final expireHours = (data?['expireHours'] as num?)?.toInt() ?? 24;
    final expiresAt =
        _readTimestamp(data?['expiresAt']) ??
        timestamp.add(Duration(hours: expireHours));
    final originalTimestamp =
        _readTimestamp(data?['originalTimestamp']) ?? timestamp;

    return Story(
      id: doc.id,
      userId: data?['userId'] ?? '',
      username: data?['username'] ?? 'مستخدم',
      imageUrl: data?['imageUrl'] ?? data?['image'] ?? '',
      mediaType: data?['mediaType'] ?? 'image',
      timestamp: timestamp,
      expiresAt: expiresAt,
      expireHours: expireHours,
      originalStoryId: data?['originalStoryId'] as String?,
      originalTimestamp: originalTimestamp,
      isVerified: data?['isVerified'] ?? false,
      text: data?['text'] ?? '',
      viewers: _parseMaps(data?['viewers']),
      reactions: _parseMaps(data?['reactions']),
      replies: _parseMaps(data?['replies']),
    );
  }

  static DateTime? _readTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate().toUtc();
    if (value is DateTime) return value.toUtc();
    if (value is String) return DateTime.tryParse(value)?.toUtc();
    return null;
  }

  static DateTime? readExpiresAt(Map<String, dynamic>? data) {
    return _readTimestamp(data?['expiresAt']);
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
      'text': text,
      'mediaType': mediaType,
      'timestamp': Timestamp.fromDate(timestamp.toUtc()),
      'expireHours': expireHours,
      'expiresAt': Timestamp.fromDate(expiresAt.toUtc()),
      if (originalStoryId != null) 'originalStoryId': originalStoryId,
      'originalTimestamp': Timestamp.fromDate(originalTimestamp.toUtc()),
      'isVerified': isVerified,
      'viewers': viewers,
      'reactions': reactions,
      'replies': replies,
    };
  }
}
