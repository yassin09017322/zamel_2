import 'package:cloud_firestore/cloud_firestore.dart' hide Index;
import 'package:isar/isar.dart';

part 'chat_message.g.dart';

class ChatMessageType {
  static const String text = 'text';
  static const String image = 'image';
  static const String video = 'video';
  static const String audio = 'audio';
  static const String file = 'file';
  static const String call = 'call';
}

class MessageStatus {
  static const String pending = 'pending';
  static const String sent = 'sent';
  static const String delivered = 'delivered';
  static const String seen = 'seen';
  static const String read = 'read';
  static const String failed = 'failed';
}

@Collection()
class ChatMessage {
  Id id = Isar.autoIncrement;

  @Index()
  String firestoreId = '';

  @Index()
  String roomId = '';

  String senderId = '';
  String senderName = '';
  String text = '';
  String mediaUrl = '';
  String mediaType = ChatMessageType.text;
  String publicId = '';
  String fileName = '';
  String fileType = '';
  int fileSize = 0;
  String receiverId = '';
  String replyToMessageId = '';
  String replyToSenderName = '';
  String replyToMediaType = ChatMessageType.text;
  String replyToText = '';

  String status = MessageStatus.sent;
  bool isPinned = false;
  bool isEdited = false;
  bool isDisappearing = false;
  int disappearingDurationSeconds = 0;
  DateTime readAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime deleteAt = DateTime.fromMillisecondsSinceEpoch(0);

  @Index()
  DateTime timestamp = DateTime.now();

  ChatMessage();

  factory ChatMessage.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc, String roomId) {
    final data = doc.data() ?? <String, dynamic>{};
    final mediaUrl = (data['mediaUrl'] as String?) ?? (data['imageUrl'] as String?) ?? '';
    final mediaType = (data['mediaType'] as String?) ??
        (mediaUrl.isNotEmpty ? ChatMessageType.image : ChatMessageType.text);

    final message = ChatMessage()
      ..firestoreId = doc.id
      ..roomId = roomId
      ..senderId = data['senderId'] as String? ?? ''
      ..senderName = data['senderName'] as String? ?? ''
      ..text = data['text'] as String? ?? ''
      ..mediaUrl = mediaUrl
      ..mediaType = mediaType
      ..publicId = data['publicId'] as String? ?? ''
      ..fileName = data['fileName'] as String? ?? ''
      ..fileType = data['fileType'] as String? ?? ''
      ..fileSize = data['fileSize'] is int ? data['fileSize'] as int : 0
      ..receiverId = data['receiverId'] as String? ?? ''
      ..replyToMessageId = data['replyToMessageId'] as String? ?? ''
      ..replyToSenderName = data['replyToSenderName'] as String? ?? ''
      ..replyToMediaType = data['replyToMediaType'] as String? ?? ChatMessageType.text
      ..replyToText = data['replyToText'] as String? ?? ''
      ..status = data['status'] as String? ?? MessageStatus.sent
      ..isPinned = data['isPinned'] == true
      ..isEdited = data['isEdited'] == true
      ..isDisappearing = data['isDisappearing'] == true
      ..disappearingDurationSeconds = data['disappearingDurationSeconds'] is int
          ? data['disappearingDurationSeconds'] as int
          : 0
      ..readAt = _parseTimestamp(
        data['readAt'],
        fallback: DateTime.fromMillisecondsSinceEpoch(0),
      )
      ..deleteAt = _parseTimestamp(
        data['deleteAt'],
        fallback: DateTime.fromMillisecondsSinceEpoch(0),
      )
      ..timestamp = _parseTimestamp(
        data['createdAt'] ?? data['timestamp'],
        fallback: DateTime.now(),
      );

    return message;
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final message = ChatMessage();
    message.firestoreId = json['firestoreId'] as String? ?? '';
    message.roomId = json['roomId'] as String? ?? '';
    message.senderId = json['senderId'] as String? ?? '';
    message.senderName = json['senderName'] as String? ?? '';
    message.text = json['text'] as String? ?? '';
    message.mediaUrl = json['mediaUrl'] as String? ?? '';
    message.mediaType = json['mediaType'] as String? ?? ChatMessageType.text;
    message.publicId = json['publicId'] as String? ?? '';
    message.fileName = json['fileName'] as String? ?? '';
    message.fileType = json['fileType'] as String? ?? '';
    message.fileSize = json['fileSize'] is int ? json['fileSize'] as int : 0;
    message.receiverId = json['receiverId'] as String? ?? '';
    message.replyToMessageId = json['replyToMessageId'] as String? ?? '';
    message.replyToSenderName = json['replyToSenderName'] as String? ?? '';
    message.replyToMediaType = json['replyToMediaType'] as String? ?? ChatMessageType.text;
    message.replyToText = json['replyToText'] as String? ?? '';
    message.status = json['status'] as String? ?? MessageStatus.sent;
    message.isPinned = json['isPinned'] == true;
    message.isEdited = json['isEdited'] == true;
    message.isDisappearing = json['isDisappearing'] == true;
    message.disappearingDurationSeconds = json['disappearingDurationSeconds'] is int
        ? json['disappearingDurationSeconds'] as int
        : 0;
    message.readAt = _parseTimestamp(
      json['readAt'],
      fallback: DateTime.fromMillisecondsSinceEpoch(0),
    );
    message.deleteAt = _parseTimestamp(
      json['deleteAt'],
      fallback: DateTime.fromMillisecondsSinceEpoch(0),
    );
    message.timestamp = _parseTimestamp(
      json['timestamp'],
      fallback: DateTime.now(),
    );
    return message;
  }

  Map<String, dynamic> toJson() {
    return {
      'firestoreId': firestoreId,
      'roomId': roomId,
      'senderId': senderId,
      'senderName': senderName,
      'text': text,
      'mediaUrl': mediaUrl,
      'mediaType': mediaType,
      'publicId': publicId,
      'fileName': fileName,
      'fileType': fileType,
      'fileSize': fileSize,
      'receiverId': receiverId,
      'replyToMessageId': replyToMessageId,
      'replyToSenderName': replyToSenderName,
      'replyToMediaType': replyToMediaType,
      'replyToText': replyToText,
      'status': status,
      'isPinned': isPinned,
      'isEdited': isEdited,
      'isDisappearing': isDisappearing,
      'disappearingDurationSeconds': disappearingDurationSeconds,
      'readAt': readAt.toUtc().toIso8601String(),
      'deleteAt': deleteAt.toUtc().toIso8601String(),
      'timestamp': timestamp.toUtc().toIso8601String(),
    };
  }

  Map<String, dynamic> toFirestore() {
    return {
      'senderId': senderId,
      'senderName': senderName,
      'text': text,
      'mediaUrl': mediaUrl,
      'mediaType': mediaType,
      'publicId': publicId,
      'fileName': fileName,
      'fileType': fileType,
      'fileSize': fileSize,
      'receiverId': receiverId,
      'replyToMessageId': replyToMessageId,
      'replyToSenderName': replyToSenderName,
      'replyToMediaType': replyToMediaType,
      'replyToText': replyToText,
      'status': status,
      'isPinned': isPinned,
      'isEdited': isEdited,
      'isDisappearing': isDisappearing,
      'disappearingDurationSeconds': disappearingDurationSeconds,
      if (isDisappearing && disappearingDurationSeconds > 0) ...{
        'readAt': readAt == DateTime.fromMillisecondsSinceEpoch(0)
            ? null
            : Timestamp.fromDate(readAt),
        'deleteAt': deleteAt == DateTime.fromMillisecondsSinceEpoch(0)
            ? null
            : Timestamp.fromDate(deleteAt),
      },
      'createdAt': Timestamp.fromDate(timestamp),
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }

  static DateTime _parseTimestamp(
    dynamic value, {
    DateTime? fallback,
  }) {
    final resolvedFallback = fallback ?? DateTime.fromMillisecondsSinceEpoch(0);

    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (_) {
        return resolvedFallback;
      }
    }
    return resolvedFallback;
  }
}