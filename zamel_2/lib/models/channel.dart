import 'package:cloud_firestore/cloud_firestore.dart';

class Channel {
  final String id;
  final String name;
  final String description;
  final String adminId;
  final String adminName;
  final String imageUrl;
  final bool isActive;
  
  // --- الإضافات الجديدة للميزات الاحترافية ---
  final bool isPrivate; // هل القناة عامة أم خاصة؟
  final bool isReadOnly; // هل القناة للقراءة فقط (للمشرفين) أم للنقاش؟
  final String pinnedMessageId; // أيدي الرسالة المثبتة أعلى القناة
  final List<String> moderators; // قائمة المشرفين في القناة
  // ------------------------------------------
  
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
    // قيم افتراضية للميزات الجديدة عشان التوافق مع البيانات القديمة
    this.isPrivate = false, 
    this.isReadOnly = false, 
    this.pinnedMessageId = '', 
    this.moderators = const [], 
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
      
      // استخراج البيانات الجديدة من فايربيس
      isPrivate: data['isPrivate'] as bool? ?? false,
      isReadOnly: data['isReadOnly'] as bool? ?? false,
      pinnedMessageId: data['pinnedMessageId'] as String? ?? '',
      moderators: List<String>.from(data['moderators'] ?? []),
      
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
      
      // إرسال البيانات الجديدة لفايربيس
      'isPrivate': isPrivate,
      'isReadOnly': isReadOnly,
      'pinnedMessageId': pinnedMessageId,
      'moderators': moderators,
      
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
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
