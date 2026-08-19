import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/chat_room.dart';
import '../models/chat_message.dart';
import '../models/message.dart';

class ChatService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<ChatRoom>> chatRoomsForUser(String userId) {
    final query = _firestore
        .collection('chatRooms')
        .where('participants', arrayContains: userId)
        .orderBy('lastTimestamp', descending: true);

    return query.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => ChatRoom.fromFirestore(doc)).toList();
    });
  }

  Future<ChatRoom?> getChatRoom(String roomId) async {
    final doc = await _firestore.collection('chatRooms').doc(roomId).get();
    if (!doc.exists) return null;
    return ChatRoom.fromFirestore(doc);
  }

  Future<String> createOrGetChatRoom({
    required String currentUserId,
    required String currentUsername,
    required String otherUserId,
    required String otherUsername,
  }) async {
    final query = await _firestore
        .collection('chatRooms')
        .where('participants', arrayContains: currentUserId)
        .get();

    for (final doc in query.docs) {
      final participants = List<String>.from(doc.data()['participants'] as List<dynamic>? ?? []);
      if (participants.contains(otherUserId) && participants.length == 2) {
        return doc.id;
      }
    }

    final newRoom = await _firestore.collection('chatRooms').add({
      'participants': [currentUserId, otherUserId],
      'participantNames': [currentUsername, otherUsername],
      'lastMessage': '',
      'lastTimestamp': FieldValue.serverTimestamp(),
    });
    return newRoom.id;
  }

  Future<String> sendMessage({
    required String roomId,
    required String senderId,
    required String senderName,
    required String text,
    required String receiverId,
    String messageId = '',
    String mediaType = 'text',
    String mediaUrl = '',
    String fileName = '',
    String fileType = '',
    int fileSize = 0,
    String status = 'sent',
    bool isDisappearing = false,
    int disappearingDurationSeconds = 0,
    String replyToMessageId = '',
    String replyToSenderName = '',
    String replyToMediaType = ChatMessageType.text,
    String replyToText = '',
  }) async {
    final payload = {
      'senderId': senderId,
      'senderName': senderName,
      'receiverId': receiverId,
      'text': text,
      'mediaType': mediaType,
      'mediaUrl': mediaUrl,
      'fileName': fileName,
      'fileType': fileType,
      'fileSize': fileSize,
      'status': status,
      'replyToMessageId': replyToMessageId,
      'replyToSenderName': replyToSenderName,
      'replyToMediaType': replyToMediaType,
      'replyToText': replyToText,
      'isDisappearing': isDisappearing,
      'disappearingDurationSeconds': disappearingDurationSeconds,
      'createdAt': FieldValue.serverTimestamp(),
      'timestamp': FieldValue.serverTimestamp(),
    };

    // ✅ Consolidated: Write only to /chatRooms (removed redundant /chats)
    final roomRef = _firestore.collection('chatRooms').doc(roomId);
    final resolvedMessageId = messageId.isEmpty ? roomRef.collection('messages').doc().id : messageId;
    final messageRef = roomRef.collection('messages').doc(resolvedMessageId);
    
    await messageRef.set(payload);
    await roomRef.set({
      'lastMessage': text,
      'lastTimestamp': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return resolvedMessageId;
  }

  Future<void> updateMessage({
    required String roomId,
    required String messageId,
    required String newText,
    String? status,
  }) async {
    final payload = {
      'text': newText,
      'isEdited': true,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (status != null) {
      payload['status'] = status;
    }

    // ✅ Consolidated: Update only /chatRooms (removed /chats)
    final messageRef = _firestore.collection('chatRooms').doc(roomId).collection('messages').doc(messageId);
    await messageRef.update(payload);
  }

  Future<void> updateDisappearingState({
    required String roomId,
    required String messageId,
    required bool isDisappearing,
    required int disappearingDurationSeconds,
    required DateTime readAt,
    required DateTime deleteAt,
  }) async {
    final payload = {
      'isDisappearing': isDisappearing,
      'disappearingDurationSeconds': disappearingDurationSeconds,
      'readAt': Timestamp.fromDate(readAt),
      'deleteAt': Timestamp.fromDate(deleteAt),
    };

    // ✅ Consolidated: Update only /chatRooms (removed /chats)
    final messageRef = _firestore.collection('chatRooms').doc(roomId).collection('messages').doc(messageId);
    await messageRef.update(payload);
  }

  Future<void> pinMessage({required String roomId, required String messageId, required bool pin}) async {
    final payload = {
      'isPinned': pin,
      'pinnedAt': pin ? FieldValue.serverTimestamp() : null,
    };

    // ✅ Consolidated: Update only /chatRooms (removed /chats)
    final messageRef = _firestore.collection('chatRooms').doc(roomId).collection('messages').doc(messageId);
    await messageRef.update(payload);
  }

  Future<void> deleteMessage({required String roomId, required String messageId}) async {
    // ✅ Consolidated: Delete only from /chatRooms (removed /chats)
    final messageRef = _firestore.collection('chatRooms').doc(roomId).collection('messages').doc(messageId);
    await messageRef.delete();
  }

  Stream<List<Message>> messagesStream(String roomId) {
    final query = _firestore
        .collection('chatRooms')
        .doc(roomId)
        .collection('messages')
        .orderBy('createdAt', descending: false);

    return query.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => Message.fromFirestore(doc)).toList();
    });
  }
}
