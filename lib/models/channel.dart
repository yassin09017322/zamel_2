import 'package:cloud_firestore/cloud_firestore.dart';

class Channel {
  final String id;
  final String name;
  final String description;
  final String adminId;
  final String adminName;
  final String imageUrl;
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

  final DateTime createdAt;
  final DateTime updatedAt;

  const Channel({
    required this.id,
    required this.name,
    required this.description,
    required this.adminId,
    required this.adminName,
    required this.imageUrl,
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
    required this.createdAt,
    required this.updatedAt,
  });

  factory Channel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data() ?? <String, dynamic>{};

    return Channel(
      id: snapshot.id,
      name: data['name'] as String? ?? '',
      description: data['description'] as String? ?? '',
      adminId: data['adminId'] as String? ?? '',
      adminName: data['adminName'] as String? ?? '',
      imageUrl: data['imageUrl'] as String? ?? '',
      isActive: data['isActive'] as bool? ?? true,
      isPrivate: data['isPrivate'] as bool? ?? false,
      isReadOnly: data['isReadOnly'] as bool? ?? false,
      accessType: _normalizeAccessType(data['accessType'] as String? ?? (data['isPrivate'] == true ? 'private' : 'public')),
      isMembersHidden: data['isMembersHidden'] as bool? ?? false,
      isAccountsDisabled: data['isAccountsDisabled'] as bool? ?? false,
      pinnedMessageId: data['pinnedMessageId'] as String? ?? '',
      moderators: List<String>.from(data['moderators'] ?? []),
      memberIds: List<String>.from(data['memberIds'] ?? []),
      guestIds: List<String>.from(data['guestIds'] ?? []),
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
