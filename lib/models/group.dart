import 'package:cloud_firestore/cloud_firestore.dart';

class Group {
  final String id;
  final String name;
  final String description;
  final String imageUrl;
  final String ownerId;
  final String ownerName;
  final bool isPrivate;
  final DateTime createdAt;
  final int memberCount;
  final List<String> memberIds;
  final List<String> moderators;

  const Group({
    required this.id,
    required this.name,
    required this.description,
    required this.imageUrl,
    required this.ownerId,
    required this.ownerName,
    required this.isPrivate,
    required this.createdAt,
    required this.memberCount,
    required this.memberIds,
    required this.moderators,
  });

  factory Group.fromFirestore(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data() ?? <String, dynamic>{};
    final createdAt = data['createdAt'];
    final memberIds = _normalizeIdList(data['memberIds']);
    final moderators = _normalizeIdList(data['moderators']);
    final computedMemberCount = (data['memberCount'] as num?)?.toInt() ?? memberIds.length;

    return Group(
      id: snapshot.id,
      name: data['name'] as String? ?? '',
      description: data['description'] as String? ?? '',
      imageUrl: data['imageUrl'] as String? ?? '',
      ownerId: data['ownerId'] as String? ?? '',
      ownerName: data['ownerName'] as String? ?? '',
      isPrivate: data['isPrivate'] == true,
      createdAt: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
      memberCount: computedMemberCount > memberIds.length ? computedMemberCount : memberIds.length,
      memberIds: memberIds,
      moderators: moderators,
    );
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
}
