import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart' as fp;
import 'package:provider/provider.dart';
import 'package:isar/isar.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../widgets/emoji_picker.dart';
import '../widgets/sticker_picker.dart';
import '../models/app_user.dart';
import '../models/chat_message.dart';
import '../models/chat_room.dart';
import '../providers/settings_provider.dart';
import '../services/audio_service.dart';
import '../services/call_service.dart';
import '../services/chat_service.dart';
import '../services/chat_sync_repository.dart';
import '../services/media_service.dart';
import '../services/isar_service.dart';
import '../screens/call_screen.dart';
import '../widgets/message_bubble.dart';

class ChatRoomScreen extends StatefulWidget {
  final AppUser currentUser;
  final String roomId;

  const ChatRoomScreen({
    super.key,
    required this.currentUser,
    required this.roomId,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ChatService _chatService = ChatService();
  final ImagePicker _imagePicker = ImagePicker();
  final AudioCommentService _audioService = AudioCommentService();
  final MediaService _mediaService = MediaService();

  ChatSyncRepository? _chatSyncRepository;
  final ScrollController _scrollController = ScrollController();
  final FocusNode _messageFocusNode = FocusNode();
  Timer? _pendingTimeoutTimer;
  Timer? _presenceRefreshTimer;
  Timer? _disappearingCleanupTimer;
  int _selectedDisappearingDurationSeconds = 0;

  bool _showEmojiPicker = false;
  bool _showStickerPicker = false;

  bool _sending = false;
  bool _isTyping = false;
  bool _isRecording = false;
  bool _isInputFocused = false;
  bool _showScrollToBottom = false;
  bool _isTextEmpty = true;

  ChatMessage? _replyingTo;
  String? _otherUserId;
  String? _otherUserName;
  String? _lastVisibleMessagesHash;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _chatSyncRepository = ChatSyncRepository(roomId: widget.roomId);
      _chatSyncRepository?.start();
    }
    
    _messageController.addListener(() {
      if (mounted) {
        setState(() {
          _isTextEmpty = _messageController.text.trim().isEmpty;
        });
      }
    });

    _scrollController.addListener(_handleScroll);
    
    _messageFocusNode.addListener(() {
      if (mounted) {
        if (_messageFocusNode.hasFocus && (_showEmojiPicker || _showStickerPicker)) {
          setState(() {
            _showEmojiPicker = false;
            _showStickerPicker = false;
          });
        }
        setState(() => _isInputFocused = _messageFocusNode.hasFocus);
      }
    });

    _pendingTimeoutTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => unawaited(_markPendingAsFailedAfterTimeout()),
    );
    _presenceRefreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => setState(() {}),
    );
    _disappearingCleanupTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(_cleanupExpiredDisappearingMessages()),
    );
    _loadRoomInfo();
  }

  Future<void> _loadRoomInfo() async {
    try {
      final room = await _chatService.getChatRoom(widget.roomId);
      if (room != null && mounted) {
        setState(() {
          _otherUserId = room.participants.firstWhere(
            (id) => id != widget.currentUser.id,
            orElse: () => '',
          );
          _otherUserName = room.participantNames.firstWhere(
            (name) => name != widget.currentUser.username,
            orElse: () => 'الدردشة',
          );
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _pendingTimeoutTimer?.cancel();
    _presenceRefreshTimer?.cancel();
    _disappearingCleanupTimer?.cancel();
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _messageFocusNode.dispose();
    _messageController.dispose();
    _audioService.dispose();
    if (!kIsWeb) {
      _chatSyncRepository?.stop();
    }
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients || !mounted) return;
    final maxExtent = _scrollController.position.maxScrollExtent;
    final nearBottom = _scrollController.offset >= maxExtent - 220;
    if (_showScrollToBottom != !nearBottom) {
      setState(() => _showScrollToBottom = !nearBottom);
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0.0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _clearReply() {
    setState(() {
      _replyingTo = null;
    });
  }

  void _handleEmojiSelected(String emoji) {
    if (emoji == '\u{0008}') {
      final text = _messageController.text;
      if (text.isNotEmpty) {
        _messageController.text = text.substring(0, text.length - 1);
      }
    } else {
      _messageController.text += emoji;
    }
    setState(() => _isTextEmpty = _messageController.text.trim().isEmpty);
  }

  void _toggleEmojiPicker() {
    if (_showEmojiPicker) {
      setState(() => _showEmojiPicker = false);
      _messageFocusNode.requestFocus();
    } else {
      _messageFocusNode.unfocus();
      setState(() {
        _showEmojiPicker = true;
        _showStickerPicker = false;
      });
    }
  }

  Future<void> _sendTextMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    setState(() => _sending = true);
    _messageController.clear();

    final String tempMessageId = 'local_${DateTime.now().microsecondsSinceEpoch}';

    final ChatMessage localMessage = ChatMessage()
      ..firestoreId = tempMessageId
      ..roomId = widget.roomId
      ..senderId = widget.currentUser.id
      ..senderName = widget.currentUser.username
      ..receiverId = _otherUserId ?? ''
      ..text = text
      ..mediaType = ChatMessageType.text
      ..status = MessageStatus.pending
      ..replyToMessageId = _replyingTo?.firestoreId ?? ''
      ..replyToSenderName = _replyingTo?.senderName ?? ''
      ..replyToMediaType = _replyingTo?.mediaType ?? ChatMessageType.text
      ..replyToText = _replyingTo?.text ?? ''
      ..isDisappearing = _selectedDisappearingDurationSeconds > 0
      ..disappearingDurationSeconds = _selectedDisappearingDurationSeconds
      ..timestamp = DateTime.now();

    await _saveLocalMessage(localMessage);
    
    if (mounted) {
      _clearReply();
      _scrollToBottom();
    }

    try {
      final cloudMessageId = await _chatService.sendMessage(
        roomId: widget.roomId,
        senderId: widget.currentUser.id,
        senderName: widget.currentUser.username,
        receiverId: _otherUserId ?? '',
        messageId: tempMessageId,
        text: text,
        mediaType: ChatMessageType.text,
        status: MessageStatus.sent,
        isDisappearing: _selectedDisappearingDurationSeconds > 0,
        disappearingDurationSeconds: _selectedDisappearingDurationSeconds,
        replyToMessageId: localMessage.replyToMessageId,
        replyToSenderName: localMessage.replyToSenderName,
        replyToMediaType: localMessage.replyToMediaType,
        replyToText: localMessage.replyToText,
      );
      _monitorMessageCommit(cloudMessageId);
    } catch (error) {
      await _updateLocalMessageStatus(tempMessageId, MessageStatus.failed);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فشل إرسال الرسالة')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _uploadAndSendMedia(
    File? file,
    String mediaType,
    String textPlaceholder, {
    Uint8List? webBytes,
    String? webFileName,
    String? folder,
    String? fileType,
    int? fileSize,
  }) async {
    final String tempMessageId = 'local_${DateTime.now().microsecondsSinceEpoch}';
    final ChatMessage localMessage = ChatMessage()
      ..firestoreId = tempMessageId
      ..roomId = widget.roomId
      ..senderId = widget.currentUser.id
      ..senderName = widget.currentUser.username
      ..receiverId = _otherUserId ?? ''
      ..text = textPlaceholder
      ..mediaType = mediaType
      ..status = MessageStatus.pending
      ..replyToMessageId = _replyingTo?.firestoreId ?? ''
      ..replyToSenderName = _replyingTo?.senderName ?? ''
      ..replyToMediaType = _replyingTo?.mediaType ?? ChatMessageType.text
      ..replyToText = _replyingTo?.text ?? ''
      ..isDisappearing = _selectedDisappearingDurationSeconds > 0
      ..disappearingDurationSeconds = _selectedDisappearingDurationSeconds
      ..timestamp = DateTime.now();

    await _saveLocalMessage(localMessage);
    if (mounted) {
      _clearReply();
    }

    try {
      final fileName =
          webFileName ??
          '${DateTime.now().millisecondsSinceEpoch}_${file?.path.split('/').last ?? 'file'}';
      String downloadUrl = '';

      if (mediaType == 'file') {
        if (kIsWeb && webBytes != null) {
          downloadUrl = await _mediaService.uploadBytes(
            webBytes,
            fileName,
            isVideo: false,
          );
        } else if (file != null) {
          downloadUrl = await _mediaService.uploadFile(
            file,
            isVideo: false,
          );
        }
      } else if (mediaType == ChatMessageType.audio) {
        if (kIsWeb && webBytes != null) {
          downloadUrl = await _mediaService.uploadBytes(
            webBytes,
            fileName,
            isVideo: false,
          );
        } else if (file != null) {
          downloadUrl = await _mediaService.uploadFile(
            file,
            isVideo: false,
          );
        }
      } else {
        if (kIsWeb && webBytes != null) {
          downloadUrl = await _mediaService.uploadBytes(
            webBytes,
            fileName,
            isVideo: mediaType == ChatMessageType.video,
          );
        } else if (file != null) {
          downloadUrl = await _mediaService.uploadFile(
            file,
            isVideo: mediaType == ChatMessageType.video,
          );
        }
      }

      if (downloadUrl.isEmpty) {
        throw Exception('فشل الرفع');
      }

      final initialStatus = MessageStatus.sent;

      final cloudMessageId = await _chatService.sendMessage(
        roomId: widget.roomId,
        senderId: widget.currentUser.id,
        senderName: widget.currentUser.username,
        receiverId: _otherUserId ?? '',
        messageId: tempMessageId,
        text: textPlaceholder,
        mediaType: mediaType,
        mediaUrl: downloadUrl,
        fileName: mediaType == 'file' ? fileName : '',
        fileType: mediaType == 'file' ? (fileType ?? '') : '',
        fileSize: mediaType == 'file' ? (fileSize ?? 0) : 0,
        status: initialStatus,
        isDisappearing: _selectedDisappearingDurationSeconds > 0,
        disappearingDurationSeconds: _selectedDisappearingDurationSeconds,
        replyToMessageId: localMessage.replyToMessageId,
        replyToSenderName: localMessage.replyToSenderName,
        replyToMediaType: localMessage.replyToMediaType,
        replyToText: localMessage.replyToText,
      );

      _monitorMessageCommit(cloudMessageId);
    } catch (error) {
      await _updateLocalMessageStatus(tempMessageId, MessageStatus.failed);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فشل رفع الملف، تأكد من اتصالك')),
      );
    }
  }

  Future<void> _pickMedia(ImageSource source, {bool isVideo = false}) async {
    if (source == ImageSource.camera) {
      try {
        final XFile? file = isVideo
            ? await _imagePicker.pickVideo(source: source)
            : await _imagePicker.pickImage(source: source, imageQuality: 70);

        if (file == null) return;

        if (kIsWeb) {
          final bytes = await file.readAsBytes();
          await _uploadAndSendMedia(
            null,
            isVideo ? ChatMessageType.video : ChatMessageType.image,
            isVideo ? '🎥 فيديو' : '📷 صورة',
            webBytes: bytes,
            webFileName: file.name,
          );
        } else {
          await _uploadAndSendMedia(
            File(file.path),
            isVideo ? ChatMessageType.video : ChatMessageType.image,
            isVideo ? '🎥 فيديو' : '📷 صورة',
          );
        }
      } catch (e) {
        debugPrint('Error picking media from camera: $e');
      }
    } else {
      await _pickMediaFromGallery(isVideo: isVideo);
    }
  }

  Future<void> _pickMediaFromGallery({required bool isVideo}) async {
    try {
      final result = await fp.FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: isVideo ? fp.FileType.media : fp.FileType.image,
        withData: kIsWeb,
      );

      if (result == null || result.files.isEmpty) return;

      if (mounted) {
        setState(() => _sending = true);
      }

      for (final pickedFile in result.files) {
        if (!mounted) break;
        if (pickedFile.bytes == null && pickedFile.path == null) continue;

        final fileType = pickedFile.extension ?? '';
        final mediaType = isVideo
            ? ChatMessageType.video
            : ChatMessageType.image;
        final textPlaceholder = isVideo ? '🎥 فيديو' : '📷 صورة';

        if (kIsWeb) {
          await _uploadAndSendMedia(
            null,
            mediaType,
            textPlaceholder,
            webBytes: pickedFile.bytes,
            webFileName: pickedFile.name,
            fileType: fileType,
            fileSize: pickedFile.size,
          );
        } else if (pickedFile.path != null) {
          await _uploadAndSendMedia(
            File(pickedFile.path!),
            mediaType,
            textPlaceholder,
            fileType: fileType,
            fileSize: pickedFile.size,
          );
        }
      }
    } catch (e) {
      debugPrint('Error picking media from gallery: $e');
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _pickDocument() async {
    try {
      final result = await fp.FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: fp.FileType.any,
        withData: kIsWeb,
      );

      if (result == null || result.files.isEmpty) return;

      if (mounted) {
        setState(() => _sending = true);
      }

      for (final pickedFile in result.files) {
        if (!mounted) break;
        if (pickedFile.bytes == null && pickedFile.path == null) continue;

        if (kIsWeb) {
          await _uploadAndSendMedia(
            null,
            ChatMessageType.file,
            '📄 ملف مستند',
            webBytes: pickedFile.bytes,
            webFileName: pickedFile.name,
            fileType: pickedFile.extension,
            fileSize: pickedFile.size,
          );
        } else if (pickedFile.path != null) {
          await _uploadAndSendMedia(
            File(pickedFile.path!),
            ChatMessageType.file,
            '📄 ملف مستند',
            fileType: pickedFile.extension,
            fileSize: pickedFile.size,
          );
        }
      }
    } catch (e) {
      debugPrint('Error picking documents: $e');
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _saveLocalMessage(ChatMessage message) async {
    final isar = await IsarService.init();
    if (isar == null) return;

    await isar.writeTxn(() async {
      await isar.chatMessages.put(message);
    });
  }

  Future<void> _deleteLocalMessage(String firestoreId) async {
    final isar = await IsarService.init();
    if (isar == null) return;

    await isar.writeTxn(() async {
      final existing = await isar.chatMessages
          .where()
          .firestoreIdEqualTo(firestoreId)
          .build()
          .findFirst();

      if (existing != null && existing.roomId == widget.roomId) {
        await isar.chatMessages.delete(existing.id);
      }
    });
  }

  Future<void> _updateLocalMessageStatus(
    String firestoreId,
    String status, {
    String? mediaUrl,
  }) async {
    final isar = await IsarService.init();
    if (isar == null) return;

    await isar.writeTxn(() async {
      final existing = await isar.chatMessages
          .where()
          .firestoreIdEqualTo(firestoreId)
          .build()
          .findFirst();

      if (existing == null || existing.roomId != widget.roomId) return;
      existing.status = status;
      if (mediaUrl != null && mediaUrl.isNotEmpty) {
        existing.mediaUrl = mediaUrl;
      }
      await isar.chatMessages.put(existing);
    });
  }

  Future<void> _monitorMessageCommit(String firestoreId) async {
    try {
      final docRef = FirebaseFirestore.instance
          .collection('chatRooms')
          .doc(widget.roomId)
          .collection('messages')
          .doc(firestoreId);
      StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? sub;
      sub = docRef.snapshots().listen((snapshot) async {
        try {
          if (!snapshot.metadata.hasPendingWrites) {
            await _updateLocalMessageStatus(firestoreId, MessageStatus.sent);
            await sub?.cancel();
            sub = null;
          }
        } catch (_) {}
      });
    } catch (_) {}
  }

  Future<void> _markMessagesAsDelivered(List<ChatMessage> messages) async {
    for (final message in messages) {
      try {
        if (message.senderId == widget.currentUser.id) continue;
        if (message.firestoreId.isEmpty) continue;
        if (message.firestoreId.startsWith('local_')) continue;
        if (message.status == MessageStatus.delivered ||
            message.status == MessageStatus.seen ||
            message.status == MessageStatus.read) continue;

        if (message.status == MessageStatus.sent) {
          final batch = FirebaseFirestore.instance.batch();
          final roomRef = FirebaseFirestore.instance
              .collection('chatRooms')
              .doc(widget.roomId)
              .collection('messages')
              .doc(message.firestoreId);
          final chatRef = FirebaseFirestore.instance
              .collection('chats')
              .doc(widget.roomId)
              .collection('messages')
              .doc(message.firestoreId);
          batch.update(roomRef, {'status': MessageStatus.delivered});
          batch.update(chatRef, {'status': MessageStatus.delivered});
          await batch.commit();
          await _updateLocalMessageStatus(message.firestoreId, MessageStatus.delivered);
        }
      } catch (_) {
      }
    }
  }

  Future<void> _markPendingAsFailedAfterTimeout() async {
    final isar = await IsarService.init();
    if (isar == null) return;

    final threshold = DateTime.now().subtract(const Duration(hours: 48));
    final pendingMessages = await isar.chatMessages.where().build().findAll();

    for (final message in pendingMessages) {
      if (message.roomId != widget.roomId) continue;
      if (message.status == MessageStatus.pending && message.timestamp.isBefore(threshold)) {
        await _updateLocalMessageStatus(message.firestoreId, MessageStatus.failed);
      }
    }
  }

  Future<void> _cleanupExpiredDisappearingMessages() async {
    final isar = await IsarService.init();
    if (isar == null) return;

    final now = DateTime.now();
    final messages = await isar.chatMessages.where().build().findAll();

    for (final message in messages) {
      if (message.roomId != widget.roomId) continue;
      if (!message.isDisappearing ||
          message.deleteAt == DateTime.fromMillisecondsSinceEpoch(0) ||
          message.deleteAt.isAfter(now)) {
        continue;
      }

      await _deleteLocalMessage(message.firestoreId);
      await _chatService.deleteMessage(
        roomId: widget.roomId,
        messageId: message.firestoreId,
      );
    }
  }

  Future<void> _startRecording() async {
    try {
      final canRecord = await _audioService.checkPermission();
      if (!canRecord) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('صلاحية الميكروفون مطلوبة')),
        );
        return;
      }

      final path = await _audioService.startRecording();
      setState(() => _isRecording = path != null);
    } catch (e) {
      debugPrint('Error starting record: $e');
    }
  }

  Future<void> _stopRecordingAndSend() async {
    try {
      final path = await _audioService.stopRecording();
      setState(() => _isRecording = false);
      if (!mounted) return;
      if (path == null) return;

      final shouldSend = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('مراجعة التسجيل الصوتي'),
          content: const Text('هل تريد إرسال التسجيل الصوتي الآن؟'),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.pop(context, false);
              },
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () async {
                if (!mounted) return;
                await _audioService.play(path);
              },
              child: const Text('استماع'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context, true);
              },
              child: const Text('إرسال'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      if (shouldSend != true) return;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('جاري إرسال التسجيل الصوتي...')),
        );
      }

      if (kIsWeb) {
        final uploadResult = await _audioService.uploadAudioFile(path);
        if (uploadResult != null && uploadResult['url'] != null) {
          await _chatService.sendMessage(
            roomId: widget.roomId,
            senderId: widget.currentUser.id,
            senderName: widget.currentUser.username,
            receiverId: _otherUserId ?? '',
            text: '🎤 مقطع صوتي',
            mediaType: ChatMessageType.audio,
            mediaUrl: uploadResult['url'] as String,
            status: MessageStatus.sent,
          );
        }
      } else {
        await _uploadAndSendMedia(
          File(path),
          ChatMessageType.audio,
          '🎤 مقطع صوتي',
        );
      }
    } catch (e) {
      setState(() => _isRecording = false);
    }
  }

  void _showAttachmentBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 24,
            runSpacing: 24,
            children: [
              _buildAttachmentIcon(Icons.insert_drive_file_rounded, const Color(0xFF5B6CFF), 'مستند', _pickDocument),
              _buildAttachmentIcon(Icons.camera_alt_rounded, const Color(0xFF10B981), 'كاميرا', () {
                Navigator.pop(context);
                _pickMedia(ImageSource.camera, isVideo: false);
              }),
              _buildAttachmentIcon(Icons.image, const Color(0xFFF59E0B), 'المعرض', () {
                Navigator.pop(context);
                _pickMediaFromGallery(isVideo: false);
              }),
              _buildAttachmentIcon(Icons.videocam, const Color(0xFFE94057), 'فيديو', () {
                Navigator.pop(context);
                _pickMediaFromGallery(isVideo: true);
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAttachmentIcon(IconData icon, Color color, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F6FA),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 1,
          iconTheme: const IconThemeData(color: Colors.black87),
          title: Row(
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFF5B6CFF).withOpacity(0.2),
                child: const Icon(Icons.person, color: Color(0xFF5B6CFF)),
              ),
              const SizedBox(width: 12),
              Text(
                _otherUserName ?? 'الدردشة',
                style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('chatRooms')
                      .doc(widget.roomId)
                      .collection('messages')
                      .orderBy('timestamp', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return const Center(
                        child: Text(
                          'لا توجد رسائل بعد.. كن أول من يبدأ المحادثة 👋',
                          style: TextStyle(color: Colors.grey, fontSize: 15),
                        ),
                      );
                    }

                    final docs = snapshot.data!.docs;

                    return ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final data = docs[index].data() as Map<String, dynamic>;
                        
                        final message = ChatMessage()
                          ..firestoreId = docs[index].id
                          ..roomId = data['roomId'] ?? ''
                          ..senderId = data['senderId'] ?? ''
                          ..senderName = data['senderName'] ?? ''
                          ..text = data['text'] ?? ''
                          ..mediaType = data['mediaType'] ?? 'text'
                          ..mediaUrl = data['mediaUrl'] ?? ''
                          ..status = data['status'] ?? 'sent'
                          ..timestamp = (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now()
                          ..replyToMessageId = data['replyToMessageId'] ?? ''
                          ..replyToSenderName = data['replyToSenderName'] ?? ''
                          ..replyToMediaType = data['replyToMediaType'] ?? 'text'
                          ..replyToText = data['replyToText'] ?? '';

                        final isMine = message.senderId == widget.currentUser.id;

                        return MessageBubble(
                          message: message,
                          isMine: isMine,
                          onReply: (msg) {
                            setState(() => _replyingTo = msg);
                            _messageFocusNode.requestFocus();
                          },
                        );
                      },
                    );
                  },
                ),
              ),

              if (_replyingTo != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    border: const Border(left: BorderSide(color: Color(0xFF5B6CFF), width: 4)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'الرد على ${_replyingTo!.senderName}',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF5B6CFF), fontSize: 13),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _replyingTo!.text.isNotEmpty ? _replyingTo!.text : 'مرفق',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.black54, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20, color: Colors.black54),
                        onPressed: _clearReply,
                      ),
                    ],
                  ),
                ),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -2)),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            IconButton(
                              icon: Icon(
                                _showEmojiPicker ? Icons.keyboard : Icons.emoji_emotions_outlined,
                                color: Colors.grey[600],
                              ),
                              onPressed: _toggleEmojiPicker,
                            ),
                            Expanded(
                              child: TextField(
                                controller: _messageController,
                                focusNode: _messageFocusNode,
                                maxLines: 5,
                                minLines: 1,
                                decoration: InputDecoration(
                                  hintText: _isRecording ? 'جاري التسجيل...' : 'اكتب رسالة...',
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                readOnly: _isRecording,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.attach_file, color: Colors.grey),
                              onPressed: _showAttachmentBottomSheet,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        if (!_isTextEmpty) {
                          _sendTextMessage();
                        } else {
                          if (_isRecording) {
                            _stopRecordingAndSend();
                          } else {
                            _startRecording();
                          }
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(bottom: 2),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _isTextEmpty
                              ? (_isRecording ? Colors.red : const Color(0xFF2EC7A5))
                              : const Color(0xFF5B6CFF),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isTextEmpty
                              ? (_isRecording ? Icons.stop_rounded : Icons.mic_rounded)
                              : Icons.send_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              if (_showEmojiPicker)
                EmojiPicker(
                  onEmojiSelected: _handleEmojiSelected,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
