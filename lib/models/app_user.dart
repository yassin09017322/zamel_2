import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String id;
  final String email;
  final String username;
  final String? photoURL;
  final String role;
  final bool isBanned;
  final bool canPost;
  final List<String> followers;
  final List<String> following;
  final int followersCount;
  final int followingCount;
  final int friendsCount;
  final String bio;
  final String location;
  final String work;
  final String hobby;
  final int points;
  final String rank;
  final bool isOnline;
  final DateTime? lastSeen;
  final bool sharePresence;

  AppUser({
    required this.id,
    required this.email,
    required this.username,
    this.photoURL,
    required this.role,
    required this.isBanned,
    required this.canPost,
    required this.followers,
    required this.following,
    this.followersCount = 0,
    this.followingCount = 0,
    this.friendsCount = 0,
    required this.bio,
    required this.location,
    required this.work,
    required this.hobby,
    required this.points,
    required this.rank,
    this.isOnline = false,
    this.lastSeen,
    this.sharePresence = true,
  });

  factory AppUser.fromFirestore(Map<String, dynamic>? data, String id) {
    final safeData = data ?? <String, dynamic>{};
    return AppUser(
      id: id,
      email: safeData['email'] as String? ?? '',
      username: safeData['username'] as String? ?? '',
      photoURL: safeData['photoURL'] as String? ?? '',
      role: safeData['role'] as String? ?? 'user',
      isBanned: safeData['isBanned'] as bool? ?? false,
      canPost: safeData['canPost'] as bool? ?? true,
      followers: List<String>.from(safeData['followers'] as List<dynamic>? ?? []),
      following: List<String>.from(safeData['following'] as List<dynamic>? ?? []),
      followersCount: safeData['followersCount'] is num ? (safeData['followersCount'] as num).toInt() : 0,
      followingCount: safeData['followingCount'] is num ? (safeData['followingCount'] as num).toInt() : 0,
      friendsCount: safeData['friendsCount'] is num ? (safeData['friendsCount'] as num).toInt() : 0,
      bio: safeData['bio'] as String? ?? 'مرحباً! أنا في ZAMEL ✨',
      location: safeData['location'] as String? ?? 'غير محدد',
      work: safeData['work'] as String? ?? 'غير محدد',
      hobby: safeData['hobby'] as String? ?? 'غير محدد',
      points: safeData['points'] as int? ?? 0,
      rank: safeData['rank'] as String? ?? '✨ عضو جديد',
      isOnline: safeData['isOnline'] as bool? ?? false,
      lastSeen: safeData['lastSeen'] is DateTime
          ? safeData['lastSeen'] as DateTime
          : safeData['lastSeen'] is Timestamp
              ? (safeData['lastSeen'] as Timestamp).toDate()
              : null,
      sharePresence: safeData['sharePresence'] as bool? ?? true,
    );
  }

  // الدالة دي بترفع البيانات الجديدة للفايربيس
  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'username': username,
      'photoURL': photoURL,
      'role': role,
      'isBanned': isBanned,
      'canPost': canPost,
      'followers': followers,
      'following': following,
      'followersCount': followersCount,
      'followingCount': followingCount,
      'friendsCount': friendsCount,
      'bio': bio,
      'location': location,
      'work': work,
      'hobby': hobby,
      'points': points,
      'rank': rank,
      'isOnline': isOnline,
      'lastSeen': lastSeen,
      'sharePresence': sharePresence,
    };
  }

  // الدالة دي بتعمل تحديث لحظي للبيانات في واجهة التطبيق
  AppUser copyWith({
    String? id,
    String? email,
    String? username,
    String? photoURL,
    String? role,
    bool? isBanned,
    bool? canPost,
    List<String>? followers,
    List<String>? following,
    int? followersCount,
    int? followingCount,
    int? friendsCount,
    String? bio,
    String? location,
    String? work,
    String? hobby,
    int? points,
    String? rank,
    bool? isOnline,
    DateTime? lastSeen,
    bool? sharePresence,
  }) {
    return AppUser(
      id: id ?? this.id,
      email: email ?? this.email,
      username: username ?? this.username,
      photoURL: photoURL ?? this.photoURL,
      role: role ?? this.role,
      isBanned: isBanned ?? this.isBanned,
      canPost: canPost ?? this.canPost,
      followers: followers ?? this.followers,
      following: following ?? this.following,
      followersCount: followersCount ?? this.followersCount,
      followingCount: followingCount ?? this.followingCount,
      friendsCount: friendsCount ?? this.friendsCount,
      bio: bio ?? this.bio,
      location: location ?? this.location,
      work: work ?? this.work,
      hobby: hobby ?? this.hobby,
      points: points ?? this.points,
      rank: rank ?? this.rank,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      sharePresence: sharePresence ?? this.sharePresence,
    );
  }
}