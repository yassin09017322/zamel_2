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

  // --- الإضافات الجديدة للميزات الاحترافية ---
  final Map<String, dynamic> reactions; // تفاعلات المستخدمين (إيموجي)
  final int replyCount; // عدد التعليقات (الثريد)
  final String parentMessageId; // أيدي الرسالة الأصلية لو كان هذا تعليقاً
  final int mediaDuration; // مدة المقطع الصوتي أو الفيديو بالثواني
  final Map<String, dynamic> extraData; // مساحة حرة لبيانات إضافية زي (الاستطلاعات Polls)
  // ------------------------------------------

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
    // قيم افتراضية للميزات الجديدة لضمان التوافق مع الرسائل القديمة
    this.reactions = const {},
    this.replyCount = 0,
    this.parentMessageId = '',
    this.mediaDuration = 0,
    this.extraData = const {},
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

      // استخراج البيانات الجديدة من فايربيس
      reactions: data['reactions'] as Map<String, dynamic>? ?? {},
      replyCount: data['replyCount'] as int? ?? 0,
      parentMessageId: data['parentMessageId'] as String? ?? '',
      mediaDuration: data['mediaDuration'] as int? ?? 0,
      extraData: data['extraData'] as Map<String, dynamic>? ?? {},
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

      // إرسال البيانات الجديدة لفايربيس
      'reactions': reactions,
      'replyCount': replyCount,
      'parentMessageId': parentMessageId,
      'mediaDuration': mediaDuration,
      'extraData': extraData,
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
