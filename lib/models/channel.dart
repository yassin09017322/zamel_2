import 'package:cloud_firestore/cloud_firestore.dart';

class Channel {
  final String id;
  final String name;
  final String description;
  final String adminId;
  final String adminName;
  final String imageUrl;
  final String coverImageUrl;
  final String handle;
  final String category;
  final bool isActive;

  final bool isPrivate;
  final bool isReadOnly;
  final String accessType;
  final bool isMembersHidden;
  final bool isAccountsDisabled;
  final String pinnedMessageId;
  final List<String> moderators;
  final List<String> memberIds;
  final List<String> guestIds;
  final List<String> followerIds;
  final int followersCount;
  final Map<String, Map<String, bool>> adminPermissions;

  final DateTime createdAt;
  final DateTime updatedAt;

  const Channel({
    required this.id,
    required this.name,
    required this.description,
    required this.adminId,
    required this.adminName,
    required this.imageUrl,
    this.coverImageUrl = '',
    this.handle = '',
    this.category = 'عام',
    required this.isActive,
    this.isPrivate = false,
    this.isReadOnly = false,
    this.accessType = 'public',
    this.isMembersHidden = false,
    this.isAccountsDisabled = false,
    this.pinnedMessageId = '',
    this.moderators = const [],
    this.memberIds = const [],
    this.guestIds = const [],
    this.followerIds = const [],
    this.followersCount = 0,
    this.adminPermissions = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  factory Channel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data() ?? <String, dynamic>{};
    final followerIds = _normalizeIdList(data['followers']);
    final computedFollowersCount =
        data['followersCount'] is num
            ? (data['followersCount'] as num).toInt()
            : followerIds.length;

    return Channel(
      id: snapshot.id,
      name: data['name'] as String? ?? '',
      description: data['description'] as String? ?? '',
      adminId: data['adminId'] as String? ?? '',
      adminName: data['adminName'] as String? ?? '',
      imageUrl: data['imageUrl'] as String? ?? '',
      coverImageUrl: data['coverImageUrl'] as String? ?? '',
      handle: (data['handle'] as String? ?? '').trim().isNotEmpty
          ? (data['handle'] as String? ?? '').trim()
          : _deriveHandleFromName(data['name'] as String? ?? ''),
      category: (data['category'] as String? ?? '').trim().isNotEmpty
          ? (data['category'] as String? ?? '').trim()
          : 'عام',
      isActive: data['isActive'] as bool? ?? true,
      isPrivate: data['isPrivate'] as bool? ?? false,
      isReadOnly: data['isReadOnly'] as bool? ?? false,
      accessType: _normalizeAccessType(data['accessType'] as String? ?? (data['isPrivate'] == true ? 'private' : 'public')),
      isMembersHidden: data['isMembersHidden'] as bool? ?? false,
      isAccountsDisabled: data['isAccountsDisabled'] as bool? ?? false,
      pinnedMessageId: data['pinnedMessageId'] as String? ?? '',
      moderators: _normalizeIdList(data['moderators']),
      memberIds: _normalizeIdList(data['memberIds']),
      guestIds: _normalizeIdList(data['guestIds']),
      followerIds: followerIds,
      followersCount: computedFollowersCount > followerIds.length ? computedFollowersCount : followerIds.length,
      adminPermissions: _parseAdminPermissions(data['adminPermissions']),
      createdAt: _coerceTimestamp(data['createdAt']),
      updatedAt: _coerceTimestamp(data['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'description': description,
      'adminId': adminId,
      'adminName': adminName,
      'imageUrl': imageUrl,
      'isActive': isActive,
      'isPrivate': isPrivate,
      'isReadOnly': isReadOnly,
      'accessType': _normalizeAccessType(accessType),
      'isMembersHidden': isMembersHidden,
      'isAccountsDisabled': isAccountsDisabled,
      'pinnedMessageId': pinnedMessageId,
      'moderators': moderators,
      'memberIds': memberIds,
      'guestIds': guestIds,
      'adminPermissions': _serializeAdminPermissions(adminPermissions),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  static String _normalizeAccessType(String? value) {
    final normalized = (value ?? 'public').trim().toLowerCase();
    if (normalized == 'private' || normalized == 'guest-only' || normalized == 'guestonly' || normalized == 'guests') {
      return normalized == 'private' ? 'private' : 'guest-only';
    }
    return 'public';
  }

  static List<String> _normalizeIdList(dynamic rawValue) {
    final seen = <String>{};
    final result = <String>[];
    if (rawValue is! List) return result;

    for (final value in rawValue) {
      if (value is String) {
        final normalized = value.trim();
        if (normalized.isEmpty || seen.contains(normalized)) continue;
        seen.add(normalized);
        result.add(normalized);
      }
    }

    return result;
  }

  static String _deriveHandleFromName(String name) {
    final normalized = name.trim();
    if (normalized.isEmpty) return '@channel';
    return '@${normalized.replaceAll(RegExp(r'\s+'), '').toLowerCase()}';
  }

  static Map<String, Map<String, bool>> _parseAdminPermissions(dynamic value) {
    final result = <String, Map<String, bool>>{};
    if (value is! Map) return result;

    for (final entry in value.entries) {
      final userId = entry.key.toString().trim();
      if (userId.isEmpty || entry.value is! Map) continue;
      final permissions = <String, bool>{};
      for (final permissionEntry in (entry.value as Map).entries) {
        final permissionKey = permissionEntry.key.toString().trim();
        if (permissionKey.isEmpty) continue;
        permissions[permissionKey] = permissionEntry.value == true;
      }
      if (permissions.isNotEmpty) result[userId] = permissions;
    }
    return result;
  }

  static Map<String, Map<String, bool>> _serializeAdminPermissions(
    Map<String, Map<String, bool>> permissions,
  ) {
    final result = <String, Map<String, bool>>{};
    for (final entry in permissions.entries) {
      if (entry.key.trim().isEmpty) continue;
      result[entry.key.trim()] = Map<String, bool>.from(entry.value);
    }
    return result;
  }

  static DateTime _coerceTimestamp(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    return DateTime.now();
  }
}
