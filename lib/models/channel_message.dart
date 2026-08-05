import 'package:cloud_firestore/cloud_firestore.dart';

class ChannelMessage {
  final String id;
  final String channelId;
  final String senderId;
  final String senderName;
  final String text;
  final String mediaUrl;
  final String mediaType;
  final String thumbnailUrl;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;

  const ChannelMessage({
    required this.id,
    required this.channelId,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.mediaUrl,
    required this.mediaType,
    required this.thumbnailUrl,
    required this.createdAt,
    required this.updatedAt,
    required this.isDeleted,
  });

  factory ChannelMessage.fromFirestore(DocumentSnapshot<Map<String, dynamic>> snapshot, String channelId) {
    final data = snapshot.data() ?? <String, dynamic>{};

    return ChannelMessage(
      id: snapshot.id,
      channelId: channelId,
      senderId: data['senderId'] as String? ?? '',
      senderName: data['senderName'] as String? ?? '',
      text: data['text'] as String? ?? '',
      mediaUrl: data['mediaUrl'] as String? ?? '',
      mediaType: data['mediaType'] as String? ?? 'text',
      thumbnailUrl: data['thumbnailUrl'] as String? ?? '',
      createdAt: _coerceTimestamp(data['createdAt']),
      updatedAt: _coerceTimestamp(data['updatedAt']),
      isDeleted: data['isDeleted'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'channelId': channelId,
      'senderId': senderId,
      'senderName': senderName,
      'text': text,
      'mediaUrl': mediaUrl,
      'mediaType': mediaType,
      'thumbnailUrl': thumbnailUrl,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'isDeleted': isDeleted,
    };
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
