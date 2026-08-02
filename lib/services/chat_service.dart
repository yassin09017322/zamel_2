import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;

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
    String publicId = '',
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
      'publicId': publicId,
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

    final legacyRef = _firestore.collection('chatRooms').doc(roomId);
    final resolvedMessageId = messageId.isEmpty ? legacyRef.collection('messages').doc().id : messageId;
    final legacyMessageRef = legacyRef.collection('messages').doc(resolvedMessageId);
    await legacyMessageRef.set(payload);
    await legacyRef.update({
      'lastMessage': text,
      'lastTimestamp': FieldValue.serverTimestamp(),
    });

    final chatRef = _firestore.collection('chats').doc(roomId);
    final chatMessageRef = chatRef.collection('messages').doc(resolvedMessageId);
    await chatMessageRef.set(payload);
    await chatRef.update({
      'lastMessage': text,
      'lastTimestamp': FieldValue.serverTimestamp(),
    });

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

    final messageRef = _firestore.collection('chatRooms').doc(roomId).collection('messages').doc(messageId);
    final chatMessageRef = _firestore.collection('chats').doc(roomId).collection('messages').doc(messageId);
    await messageRef.update(payload);
    await chatMessageRef.update(payload);
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

    final messageRef = _firestore.collection('chatRooms').doc(roomId).collection('messages').doc(messageId);
    final chatMessageRef = _firestore.collection('chats').doc(roomId).collection('messages').doc(messageId);
    await messageRef.update(payload);
    await chatMessageRef.update(payload);
  }

  Future<void> pinMessage({required String roomId, required String messageId, required bool pin}) async {
    final payload = {
      'isPinned': pin,
      'pinnedAt': pin ? FieldValue.serverTimestamp() : null,
    };

    final messageRef = _firestore.collection('chatRooms').doc(roomId).collection('messages').doc(messageId);
    final chatMessageRef = _firestore.collection('chats').doc(roomId).collection('messages').doc(messageId);
    await messageRef.update(payload);
    await chatMessageRef.update(payload);
  }

  Future<void> deleteMessage({required String roomId, required String messageId, String? publicId}) async {
    final messageRef = _firestore.collection('chatRooms').doc(roomId).collection('messages').doc(messageId);
    final chatMessageRef = _firestore.collection('chats').doc(roomId).collection('messages').doc(messageId);
    await messageRef.delete();
    await chatMessageRef.delete();

    if (publicId != null && publicId.isNotEmpty) {
      try {
        final projectId = Firebase.app().options.projectId;
        final functionUrl = 'https://us-central1-$projectId.cloudfunctions.net/deleteCloudinaryAsset';
        await http.post(
          Uri.parse(functionUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'publicId': publicId, 'resourceType': 'auto'}),
        );
      } catch (_) {}
    }
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
