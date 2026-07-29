import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:isar/isar.dart';

import '../models/chat_message.dart';
import 'isar_service.dart';

class ChatSyncRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String roomId;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;

  ChatSyncRepository({required this.roomId});

  Future<void> start() async {
    final isar = await IsarService.init();
    
    // الإضافة السحرية الأولى: لو Isar غير متاح (مثلاً في الويب)، أوقف عملية المزامنة المحلية تماماً
    if (isar == null) return;

    _subscription = _firestore
        .collection('chatRooms')
        .doc(roomId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .listen((snapshot) async {
      final messages = snapshot.docs.map((doc) => ChatMessage.fromFirestore(doc, roomId)).toList();
      
      // هنا Isar مضمون إنه موجود لأننا عملنا شرط الحماية فوق
      await isar.writeTxn(() async {
        for (final message in messages) {
          final existing = await isar.chatMessages
              .filter()
              .firestoreIdEqualTo(message.firestoreId)
              .roomIdEqualTo(roomId)
              .findFirst();

          if (existing != null) {
            message.id = existing.id;
          }
          await isar.chatMessages.put(message);
        }
      });
    }, onError: (error) {
      // Logging can be added here.
    });
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  Stream<List<ChatMessage>> watchLocalMessages() {
    return IsarService.init().asStream().asyncExpand((isar) {
      // الإضافة السحرية الثانية: لو Isar غير متاح، رجع Stream فاضي بدل ما تظهر خطأ
      if (isar == null) {
        return const Stream.empty();
      }
      return isar.chatMessages
          .where()
          .roomIdEqualTo(roomId)
          .sortByTimestamp()
          .watch(fireImmediately: true);
    });
  }
}