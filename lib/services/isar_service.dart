import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:isar/isar.dart';

import '../models/chat_message.dart'; // تأكد أن هذا المسار يطابق مكان ملفك

class IsarService {
  static Isar? _isar;

  // تعديل بسيط: خلينا النوع Future<Isar?> عشان نقدر نرجع null في الويب
  static Future<Isar?> init() async {
    // إذا كنا على الويب، تخطى Isar تماماً وارجع null
    if (kIsWeb) return null;

    // إذا كانت قاعدة البيانات مفتوحة مسبقاً، قم بإرجاعها
    if (_isar != null) return _isar!;
    
    if (Isar.instanceNames.isNotEmpty) {
      _isar = Isar.getInstance();
      if (_isar != null) return _isar!;
    }

    // جلب المسار سيحدث فقط في الموبايل
    final dir = await getApplicationSupportDirectory();
    
    // فتح قاعدة البيانات آمن الآن لأنه لن يعمل إلا على الموبايل
    _isar = await Isar.open(
      [ChatMessageSchema],
      directory: dir.path, 
    );

    return _isar;
  }

  static Future<void> close() async {
    await _isar?.close();
    _isar = null;
  }
}