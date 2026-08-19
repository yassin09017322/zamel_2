import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zamel_appp/models/channel.dart';

void main() {
  test('channel access metadata is parsed and preserved', () {
    final snapshot = FakeDocumentSnapshot({
      'name': 'Test Channel',
      'description': 'desc',
      'adminId': 'admin-1',
      'adminName': 'Owner',
      'imageUrl': '',
      'isActive': true,
      'isPrivate': true,
      'isReadOnly': false,
      'pinnedMessageId': '',
      'moderators': ['admin-1', 'mod-1'],
      'memberIds': ['member-1'],
      'guestIds': ['guest-1'],
      'isMembersHidden': true,
      'isAccountsDisabled': true,
      'createdAt': Timestamp.fromDate(DateTime(2024, 1, 1)),
      'updatedAt': Timestamp.fromDate(DateTime(2024, 1, 2)),
    }, 'channels/test');

    final channel = Channel.fromFirestore(snapshot);

    expect(channel.guestIds, ['guest-1']);
    expect(channel.isMembersHidden, isTrue);
    expect(channel.isAccountsDisabled, isTrue);
    expect(channel.memberIds, ['member-1']);
  });
}

class FakeDocumentSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  FakeDocumentSnapshot(this._data, this._id);

  final Map<String, dynamic> _data;
  final String _id;

  @override
  Map<String, dynamic>? data() => _data;

  @override
  String get id => _id;

  @override
  bool get exists => true;

  @override
  dynamic get(Object field) => _data[field as String];

  @override
  dynamic operator [](Object field) => _data[field as String];

  @override
  DocumentReference<Map<String, dynamic>> get reference => throw UnimplementedError();

  @override
  SnapshotMetadata get metadata => throw UnimplementedError();
}
