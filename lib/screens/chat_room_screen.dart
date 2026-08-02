import 'dart:async';
import 'package:zamel_appp/src/platform_file.dart';
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

import '../config.dart';
import '../models/app_user.dart';
import '../models/chat_message.dart';
import '../models/chat_room.dart';
import '../providers/settings_provider.dart';
import '../services/audio_service.dart';
import '../services/call_service.dart';
import '../services/chat_service.dart';
import '../services/chat_sync_repository.dart';
import '../services/cloudinary_service.dart';
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
  final CloudinaryService _cloudinaryService = CloudinaryService(
    cloudName: AppConfig.cloudinaryCloudName,
    uploadPreset: AppConfig.cloudinaryUploadPreset,
  );

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

  ChatMessage? _replyingTo;
  String? _otherUserId;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _chatSyncRepository = ChatSyncRepository(roomId: widget.roomId);
      _chatSyncRepository?.start();
    }
    _scrollController.addListener(_handleScroll);
    _messageFocusNode.addListener(() {
      if (mounted) {
        // Close any picker when the keyboard/input gains focus
        if (_messageFocusNode.hasFocus &&
            (_showEmojiPicker || _showStickerPicker)) {
          _showEmojiPicker = false;
          _showStickerPicker = false;
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
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _markMessagesAsRead(List<ChatMessage> messages) async {
    final now = DateTime.now();
    for (final message in messages) {
      if (message.senderId != widget.currentUser.id &&
          message.status != MessageStatus.read &&
          message.status != MessageStatus.seen) {
        final docId = message.firestoreId;
        if (docId.isNotEmpty) {
          FirebaseFirestore.instance
              .collection('chatRooms')
              .doc(widget.roomId)
              .collection('messages')
              .doc(docId)
              .update({'status': MessageStatus.seen})
              .catchError((_) {});

          FirebaseFirestore.instance
              .collection('chats')
              .doc(widget.roomId)
              .collection('messages')
              .doc(docId)
              .update({'status': MessageStatus.seen})
              .catchError((_) {});

          if (message.isDisappearing &&
              message.disappearingDurationSeconds > 0 &&
              message.readAt == DateTime.fromMillisecondsSinceEpoch(0)) {
            final updatedReadAt = now;
            final updatedDeleteAt = now.add(
              Duration(seconds: message.disappearingDurationSeconds),
            );

            await _chatService.updateDisappearingState(
              roomId: widget.roomId,
              messageId: docId,
              isDisappearing: true,
              disappearingDurationSeconds: message.disappearingDurationSeconds,
              readAt: updatedReadAt,
              deleteAt: updatedDeleteAt,
            );

            final isar = await IsarService.init();
            if (isar != null) {
              await isar.writeTxn(() async {
                final existing = await isar.chatMessages
                    .where()
                    .firestoreIdEqualTo(docId)
                    .build()
                    .findFirst();

                if (existing != null && existing.roomId == widget.roomId) {
                  existing.readAt = updatedReadAt;
                  existing.deleteAt = updatedDeleteAt;
                  await isar.chatMessages.put(existing);
                }
              });
            }
          }
        }
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
    String? publicIdOverride,
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
      final resolvedPublicId =
          publicIdOverride ??
          '${folder ?? 'chat'}/${DateTime.now().millisecondsSinceEpoch}';
      String downloadUrl = '';
      String publicId = resolvedPublicId;

      if (mediaType == 'file') {
        if (kIsWeb && webBytes != null) {
          downloadUrl = await _cloudinaryService.uploadBytes(
            webBytes,
            fileName,
            isVideo: false,
            folder: 'chat_files',
            publicId: publicId,
            resourceType: 'raw',
          );
        } else if (file != null) {
          downloadUrl = await _cloudinaryService.uploadFile(
            file,
            isVideo: false,
            folder: 'chat_files',
            publicId: publicId,
            resourceType: 'raw',
          );
        }
      } else if (mediaType == ChatMessageType.audio) {
        if (kIsWeb && webBytes != null) {
          downloadUrl = await _cloudinaryService.uploadBytes(
            webBytes,
            fileName,
            isVideo: false,
            folder: 'chat_audio',
            publicId: publicId,
            resourceType: 'video',
          );
        } else if (file != null) {
          downloadUrl = await _cloudinaryService.uploadFile(
            file,
            isVideo: false,
            folder: 'chat_audio',
            publicId: publicId,
            resourceType: 'video',
          );
        }
      } else {
        if (kIsWeb && webBytes != null) {
          downloadUrl = await _cloudinaryService.uploadBytes(
            webBytes,
            fileName,
            isVideo: mediaType == ChatMessageType.video,
            folder: 'chat',
            publicId: publicId,
            resourceType: mediaType == ChatMessageType.video
                ? 'video'
                : 'image',
          );
        } else if (file != null) {
          downloadUrl = await _cloudinaryService.uploadFile(
            file,
            isVideo: mediaType == ChatMessageType.video,
            folder: 'chat',
            publicId: publicId,
            resourceType: mediaType == ChatMessageType.video
                ? 'video'
                : 'image',
          );
        }
      }

      if (downloadUrl.isEmpty) {
        throw Exception('فشل الرفع');
      }

      // Write 'sent' to Firestore; keep local UI pending until commit confirmation.
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
        publicId: publicId,
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

      // Monitor commit and update local status when Firestore write is confirmed
      _monitorMessageCommit(cloudMessageId);
    } catch (error) {
      await _updateLocalMessageStatus(tempMessageId, MessageStatus.failed);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فشل رفع الملف، تأكد من اتصالك')),
      );
    } finally {
      // no local upload state remaining
    }
  }

  // --- دوال التقاط الصور والفيديو ---
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

        // Only update if the message is currently 'sent' (i.e., was sent by sender)
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
        // ignore individual failures
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
        publicId: message.publicId,
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
                Navigator.pop(context, true);
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
            publicId: uploadResult['publicId'] as String,
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
      useSafeArea: true,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF8FAFF), Color(0xFFEDE9FE)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFF5B6CFF).withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'إرفاق',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        _buildAttachmentIcon(
                          Icons.insert_drive_file_rounded,
                          const Color(0xFF5B6CFF),
                          'مستند',
                          _pickDocument,
                        ),
                        _buildAttachmentIcon(
                          Icons.camera_alt_rounded,
                          const Color(0xFFEC4899),
                          'كاميرا',
                          () => _pickMedia(ImageSource.camera),
                        ),
                        _buildAttachmentIcon(
                          Icons.insert_photo_rounded,
                          const Color(0xFF8B5CF6),
                          'المعرض',
                          () => _pickMedia(ImageSource.gallery),
                        ),
                        _buildAttachmentIcon(
                          Icons.videocam_rounded,
                          const Color(0xFFF59E0B),
                          'فيديو',
                          () => _pickMedia(ImageSource.gallery, isVideo: true),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAttachmentIcon(
    IconData icon,
    Color color,
    String label,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
      child: SizedBox(
        width: 84,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    color.withValues(alpha: 0.95),
                    color.withValues(alpha: 0.7),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.22),
                    blurRadius: 12,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOtherUserPresenceStatus() {
    if (_otherUserId == null || _otherUserId!.isEmpty) {
      return const Text(
        'آخر ظهور: غير متاح',
        style: TextStyle(fontSize: 12, color: Colors.white70),
      );
    }

    return StreamBuilder<DatabaseEvent>(
      stream: FirebaseDatabase.instance.ref().child('presence/$_otherUserId').onValue,
      builder: (context, snapshot) {
        final data = snapshot.data?.snapshot.value as Map<dynamic, dynamic>? ?? <dynamic, dynamic>{};
        final settingsProvider = context.watch<SettingsProvider>();
        final sharePresence = settingsProvider.sharePresence;
        final online = data['online'] == true;
        DateTime? lastSeen;
        final lastSeenValue = data['lastSeen'];
        if (lastSeenValue is int) {
          lastSeen = DateTime.fromMillisecondsSinceEpoch(lastSeenValue);
        }

        final statusText = sharePresence
            ? (online ? 'متصل الآن' : _formatLastSeen(lastSeen))
            : 'معلومات التواجد مخفية';

        return Text(
          statusText,
          style: TextStyle(
            fontSize: 12,
            color: online ? Colors.greenAccent.shade100 : Colors.white70,
          ),
        );
      },
    );
  }

  String _formatLastSeen(DateTime? timestamp) {
    if (timestamp == null) {
      return 'آخر ظهور: غير متاح';
    }

    final now = DateTime.now();
    final timeAgo = timeago.format(timestamp, locale: 'ar', clock: now);
    return 'آخر ظهور $timeAgo';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(92),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF5B6CFF), Color(0xFF7C3AED)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            automaticallyImplyLeading: true,
            titleSpacing: 0,
            title: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.forum_rounded,
                      color: Colors.white,
                      size: 23,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'دردشة خاصة',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    _buildOtherUserPresenceStatus(),
                  ],
                ),
              ],
            ),
            actions: [
              if (_otherUserId != null && _otherUserId!.isNotEmpty)
                FutureBuilder<ChatRoom?>(
                  future: ChatService().getChatRoom(widget.roomId),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData || snapshot.data == null) {
                      return const SizedBox.shrink();
                    }

                    final room = snapshot.data!;
                    final otherUserName = room.participantNames.firstWhere(
                      (name) => name != widget.currentUser.username,
                      orElse: () => room.participantNames.isNotEmpty
                          ? room.participantNames.first
                          : 'مستخدم',
                    );

                    return Row(
                      children: [
                        _buildTopAction(
                          Icons.call_outlined,
                          'مكالمة صوتية',
                          () =>
                              _startCall(_otherUserId!, otherUserName, 'audio'),
                        ),
                        _buildTopAction(
                          Icons.videocam_outlined,
                          'مكالمة فيديو',
                          () =>
                              _startCall(_otherUserId!, otherUserName, 'video'),
                        ),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF8FAFF), Color(0xFFF3E8FF), Color(0xFFEDE9FE)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withValues(alpha: 0.92),
                              Colors.white.withValues(alpha: 0.72),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                          borderRadius: BorderRadius.circular(32),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 26,
                              offset: const Offset(0, 14),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(32),
                          child: StreamBuilder<List<ChatMessage>>(
                            stream: kIsWeb
                                ? FirebaseFirestore.instance
                                      .collection('chatRooms')
                                      .doc(widget.roomId)
                                      .collection('messages')
                                      .orderBy('timestamp', descending: false)
                                      .snapshots()
                                      .map(
                                        (snapshot) => snapshot.docs
                                            .map(
                                              (doc) =>
                                                  ChatMessage.fromFirestore(
                                                    doc,
                                                    widget.roomId,
                                                  ),
                                            )
                                            .toList(),
                                      )
                                : _chatSyncRepository?.watchLocalMessages(),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }

                              final messages = snapshot.data ?? [];
                              if (messages.isEmpty) {
                                return const Center(
                                  child: Text(
                                    'لا توجد رسائل بعد. ابدأ المحادثة!',
                                  ),
                                );
                              }

                              if (mounted) {
                                WidgetsBinding.instance.addPostFrameCallback((_) async {
                                  if (!mounted) return;
                                  // First, mark incoming messages as delivered (device received them).
                                  await _markMessagesAsDelivered(messages);
                                  // Then, mark as read/seen when conversation is visible.
                                  if (!mounted) return;
                                  await _markMessagesAsRead(messages);
                                });
                              }

                              return ListView.builder(
                                controller: _scrollController,
                                physics: const BouncingScrollPhysics(),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                  horizontal: 12,
                                ),
                                itemCount: messages.length,
                                itemBuilder: (context, index) {
                                  final message = messages[index];
                                  final isMe =
                                      message.senderId == widget.currentUser.id;
                                  final showDateSeparator =
                                      index == 0 ||
                                      !_isSameDay(
                                        messages[index - 1].timestamp,
                                        message.timestamp,
                                      );
                                  return Column(
                                    children: [
                                      if (showDateSeparator)
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(
                                                0xFF5B6CFF,
                                              ).withValues(alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              _formatDateLabel(
                                                message.timestamp,
                                              ),
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFF5B6CFF),
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ),
                                      MessageBubble(
                                        message: message,
                                        isMine: isMe,
                                        onReply: _activateReply,
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 18,
                      bottom: 18,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 220),
                        opacity: _showScrollToBottom ? 1 : 0,
                        child: IgnorePointer(
                          ignoring: !_showScrollToBottom,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _scrollToBottom,
                              borderRadius: BorderRadius.circular(999),
                              child: Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF5B6CFF),
                                      Color(0xFF8B5CF6),
                                    ],
                                  ),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.16,
                                      ),
                                      blurRadius: 16,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  color: Colors.white,
                                  size: 28,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_showEmojiPicker)
                      EmojiPicker(onEmojiSelected: (e) => _onEmojiSelected(e)),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Column(
                    children: [
                      if (_isRecording)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.mic_rounded,
                                color: Colors.red,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'جاري التسجيل...',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF5B6CFF),
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: _stopRecordingAndSend,
                                icon: const Icon(
                                  Icons.send_rounded,
                                  color: Color(0xFF5B6CFF),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_replyingTo != null)
                        _buildReplyPreview(),
                      Directionality(
                        textDirection: TextDirection.rtl,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.white.withValues(alpha: 0.95),
                                Colors.white.withValues(alpha: 0.88),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(26),
                            border: Border.all(
                              color: _isInputFocused
                                  ? const Color(
                                      0xFF5B6CFF,
                                    ).withValues(alpha: 0.35)
                                  : Colors.white.withValues(alpha: 0.7),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.07),
                                blurRadius: 16,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _messageController,
                                  focusNode: _messageFocusNode,
                                  maxLines: 5,
                                  minLines: 1,
                                  onChanged: (text) => setState(
                                    () => _isTyping = text.trim().isNotEmpty,
                                  ),
                                  onSubmitted: (_) {
                                    if (!_isRecording) {
                                      _sendText();
                                    }
                                  },
                                  style: const TextStyle(fontSize: 15),
                                  decoration: InputDecoration(
                                    hintText: _isRecording
                                        ? 'جاري التسجيل...'
                                        : 'مراسلة...',
                                    hintStyle: TextStyle(
                                      color: _isRecording
                                          ? Colors.red
                                          : Colors.grey.shade600,
                                    ),
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                      horizontal: 4,
                                    ),
                                    prefixIcon: Padding(
                                      padding: const EdgeInsets.only(right: 4),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _buildDisappearingDurationPicker(),
                                          _buildComposerIcon(
                                            Icons.emoji_emotions_outlined,
                                            _toggleEmojiPicker,
                                            isPrimary: false,
                                          ),
                                          _buildComposerIcon(
                                            Icons.sticky_note_2_outlined,
                                            _openStickerBottomSheet,
                                            isPrimary: false,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              _buildComposerIcon(
                                Icons.attach_file_rounded,
                                _showAttachmentBottomSheet,
                                isPrimary: false,
                              ),
                              const SizedBox(width: 4),
                              _buildDynamicSendButton(),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopAction(
    IconData icon,
    String tooltip,
    VoidCallback onPressed,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: IconButton(
        tooltip: tooltip,
        icon: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildDisappearingDurationPicker() {
    const options = <MapEntry<int, String>>[
      MapEntry(0, 'بدون اختفاء'),
      MapEntry(30, '30 ثانية'),
      MapEntry(60, '1 دقيقة'),
      MapEntry(300, '5 دقائق'),
      MapEntry(3600, '1 ساعة'),
      MapEntry(86400, '24 ساعة'),
      MapEntry(604800, '1 أسبوع'),
      MapEntry(2592000, '1 شهر'),
      MapEntry(31536000, '1 سنة'),
    ];

    return PopupMenuButton<int>(
      tooltip: 'إعداد اختفاء الرسالة',
      icon: Icon(
        Icons.timer_outlined,
        color: _selectedDisappearingDurationSeconds > 0
            ? const Color(0xFF5B6CFF)
            : Colors.grey.shade700,
        size: 20,
      ),
      onSelected: (value) {
        if (mounted) {
          setState(() => _selectedDisappearingDurationSeconds = value);
        }
      },
      itemBuilder: (context) => options
          .map(
            (option) => PopupMenuItem<int>(
              value: option.key,
              child: Text(option.value),
            ),
          )
          .toList(),
    );
  }

  Widget _buildDynamicSendButton() {
    final shouldShowSend = !_isRecording && _isTyping && !_sending;
    final buttonIcon = shouldShowSend ? Icons.send_rounded : Icons.mic_rounded;

    return GestureDetector(
      onLongPress: shouldShowSend ? null : _startRecording,
      onLongPressUp: shouldShowSend ? null : _stopRecordingAndSend,
      onTap: shouldShowSend ? _sendText : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _isRecording
                ? [Colors.red, Colors.redAccent]
                : const [Color(0xFF5B6CFF), Color(0xFF8B5CF6)],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: _sending
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.2,
                ),
              )
            : Icon(buttonIcon, color: Colors.white, size: 24),
      ),
    );
  }

  Widget _buildComposerIcon(
    IconData icon,
    VoidCallback? onPressed, {
    required bool isPrimary,
  }) {
    final bool isDisabled = onPressed == null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isPrimary
                  ? (isDisabled
                        ? Colors.grey.shade400
                        : const Color(0xFF5B6CFF))
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              icon,
              size: 22,
              color: isPrimary
                  ? (isDisabled ? Colors.white70 : Colors.white)
                  : const Color(0xFF5B6CFF),
            ),
          ),
        ),
      ),
    );
  }

  bool _isSameDay(DateTime first, DateTime second) {
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }

  void _toggleEmojiPicker() {
    if (!mounted) return;
    setState(() {
      _showEmojiPicker = !_showEmojiPicker;
      if (_showEmojiPicker) {
        _showStickerPicker = false;
        _messageFocusNode.unfocus();
      } else {
        // show keyboard again
        FocusScope.of(context).requestFocus(_messageFocusNode);
      }
    });
  }

  void _openStickerBottomSheet() {
    if (!mounted) return;
    _messageFocusNode.unfocus();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.65,
          child: StickerPicker(
            onStickerSelected: (url) {
              Navigator.pop(context);
              _sendSticker(url);
            },
          ),
        );
      },
    );
  }

  void _onEmojiSelected(String emoji) {
    final text = _messageController.text;
    final sel = _messageController.selection;
    final base = sel.start.clamp(0, text.length);

    // map code unit offset to grapheme cluster index
    int clusterIndexForOffset(int offset) {
      final chars = text.characters;
      int acc = 0;
      int idx = 0;
      for (final ch in chars) {
        acc += ch.length;
        if (acc > offset) break;
        idx++;
      }
      return idx;
    }

    final chars = text.characters;
    final beforeCount = clusterIndexForOffset(base);
    final beforeClusters = chars.take(beforeCount).toString();
    final afterClusters = chars.skip(beforeCount).toString();

    if (emoji == '\u{0008}') {
      // backspace: remove previous grapheme cluster
      if (beforeCount == 0) return;
      final newBefore = chars.take(beforeCount - 1).toString();
      final newText = newBefore + afterClusters;
      _messageController.text = newText;
      _messageController.selection = TextSelection.collapsed(
        offset: newBefore.length,
      );
      setState(() => _isTyping = newText.trim().isNotEmpty);
      return;
    }

    final newText = beforeClusters + emoji + afterClusters;
    _messageController.text = newText;
    final newCursor = (beforeClusters + emoji).length;
    _messageController.selection = TextSelection.collapsed(offset: newCursor);
    setState(() => _isTyping = newText.trim().isNotEmpty);
  }

  String _formatDateLabel(DateTime timestamp) {
    final now = DateTime.now();
    if (_isSameDay(timestamp, now)) return 'اليوم';
    final yesterday = now.subtract(const Duration(days: 1));
    if (_isSameDay(timestamp, yesterday)) return 'أمس';
    return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
  }

  Future<void> _sendText() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final localMessageId = 'local_${DateTime.now().microsecondsSinceEpoch}';
    final localMessage = ChatMessage()
      ..firestoreId = localMessageId
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
      _messageController.clear();
      _clearReply();
      setState(() => _isTyping = false);
    }

    unawaited(
      _pushTextToCloudInBackground(localMessageId, localMessage),
    );
  }

  Future<void> _pushTextToCloudInBackground(
    String localMessageId,
    ChatMessage localMessage,
  ) async {
    try {
      // Always keep local message as PENDING until the Firestore write is committed to server.
      // Firestore local persistence will accept the write locally and report `hasPendingWrites` metadata.
      // We write status=sent to Firestore so recipients don't see a local-only pending state,
      // but we keep sender UI as pending until commit confirmation.
      final initialStatus = MessageStatus.sent;

      final cloudMessageId = await _chatService.sendMessage(
        roomId: widget.roomId,
        senderId: widget.currentUser.id,
        senderName: widget.currentUser.username,
        receiverId: _otherUserId ?? '',
        messageId: localMessageId,
        text: localMessage.text,
        status: initialStatus,
        isDisappearing: localMessage.isDisappearing,
        disappearingDurationSeconds: localMessage.disappearingDurationSeconds,
        replyToMessageId: localMessage.replyToMessageId,
        replyToSenderName: localMessage.replyToSenderName,
        replyToMediaType: localMessage.replyToMediaType,
        replyToText: localMessage.replyToText,
      );
      // Monitor commit state: only promote local UI from PENDING -> SENT when Firestore confirms commit.
      _monitorMessageCommit(cloudMessageId);
      if (!mounted) return;
    } catch (_) {
      await _updateLocalMessageStatus(localMessageId, MessageStatus.failed);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فشل إرسال الرسالة')),
      );
    }
  }

  Future<void> _sendSticker(String sticker) async {
    if (sticker.isEmpty) return;
    if (mounted) {
      setState(() {
        _sending = true;
        _showStickerPicker = false;
      });
    }

    try {
      final initialStatus = MessageStatus.sent;
      final cloudMessageId = await _chatService.sendMessage(
        roomId: widget.roomId,
        senderId: widget.currentUser.id,
        senderName: widget.currentUser.username,
        receiverId: _otherUserId ?? '',
        text: sticker,
        status: initialStatus,
        replyToMessageId: _replyingTo?.firestoreId ?? '',
        replyToSenderName: _replyingTo?.senderName ?? '',
        replyToMediaType: _replyingTo?.mediaType ?? ChatMessageType.text,
        replyToText: _replyingTo?.text ?? '',
      );
      _monitorMessageCommit(cloudMessageId);
    } catch (_) {
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('فشل إرسال الملصق')));
      }
    } finally {
      if (mounted) {
        _clearReply();
        setState(() {
          _sending = false;
          _isTyping = false;
        });
      }
    }
  }

  Widget _buildReplyPreview() {
    final replied = _replyingTo!;
    final previewText = replied.mediaType == ChatMessageType.text
        ? replied.text
        : replied.mediaType == ChatMessageType.image
            ? 'صورة'
            : replied.mediaType == ChatMessageType.video
                ? 'فيديو'
                : replied.mediaType == ChatMessageType.audio
                    ? 'مقطع صوتي'
                    : replied.mediaType == 'file'
                        ? 'ملف'
                        : replied.mediaType == ChatMessageType.call
                            ? 'مكالمة'
                            : 'رسالة';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'الرد على ${replied.senderName}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF5B6CFF),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  previewText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.black87.withOpacity(0.85),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 22, color: Colors.grey),
            onPressed: _clearReply,
          ),
        ],
      ),
    );
  }

  void _activateReply(ChatMessage message) {
    if (!mounted) return;
    setState(() {
      _replyingTo = message;
      _messageFocusNode.requestFocus();
    });
  }

  void _clearReply() {
    if (!mounted) return;
    setState(() {
      _replyingTo = null;
    });
  }

  Future<void> _startCall(
    String otherUserId,
    String otherUserName,
    String type,
  ) async {
    try {
      final session = await CallService.instance.initiateCall(
        chatId: widget.roomId,
        callerId: widget.currentUser.id,
        callerName: widget.currentUser.username,
        receiverId: otherUserId,
        receiverName: otherUserName,
        type: type,
      );
      if (!mounted) return;
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => CallScreen(session: session)));
    } catch (_) {}
  }
}
