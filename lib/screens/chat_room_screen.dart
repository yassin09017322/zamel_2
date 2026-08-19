import 'dart:async';
import 'dart:typed_data';
import 'dart:io' as io; // ✅ تم إضافة مكتبة الملفات الحقيقية هنا

import 'package:zamel_appp/src/platform_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
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

  bool get _hasCamera => !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
       defaultTargetPlatform == TargetPlatform.iOS);

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

  Future<void> retryUpload(ChatMessage failedMessage) async {
    if (failedMessage.mediaUrl.isEmpty || failedMessage.status != MessageStatus.failed) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا يمكن إعادة محاولة هذه الرسالة')),
        );
      }
      return;
    }

    try {
      await _updateLocalMessageStatus(
        failedMessage.firestoreId,
        MessageStatus.pending,
      );
      await _updateUploadProgress(failedMessage.firestoreId, 0.0);

      final fileName = failedMessage.fileName.isEmpty 
        ? '${DateTime.now().millisecondsSinceEpoch}_media' 
        : failedMessage.fileName;
      
      bool isVideo = failedMessage.mediaType == ChatMessageType.video;
      String downloadUrl = '';

      if (kIsWeb) {
        throw Exception('لا يمكن إعادة محاولة الرفع من المتصفح. حاول تحديث الصفحة وأرسل الملف مرة أخرى.');
      } else {
        // ✅ استخدام النوع الديناميكي لملف io.File الحقيقي
        dynamic localRealFile = io.File(failedMessage.mediaUrl);
        downloadUrl = await _mediaService.uploadFileWithProgress(
          localRealFile, 
          isVideo: isVideo,
          explicitFileName: fileName,
          onProgress: (progress) {
            _updateUploadProgress(failedMessage.firestoreId, progress.percentComplete);
          },
        );
      }

      if (downloadUrl.isEmpty) throw Exception('فشل الرفع عبر المحرك');

      await _updateLocalMessageStatus(
        failedMessage.firestoreId,
        MessageStatus.sent,
        mediaUrl: downloadUrl,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إعادة الرفع بنجاح')),
        );
      }
    } catch (error) {
      debugPrint('Retry upload error: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشلت إعادة المحاولة: $error')),
        );
      }
      try {
        await _updateLocalMessageError(failedMessage.firestoreId, error.toString());
      } catch (_) {}
    }
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

  void _toggleStickerPicker() {
    if (_showStickerPicker) {
      setState(() => _showStickerPicker = false);
      _messageFocusNode.requestFocus();
    } else {
      _messageFocusNode.unfocus();
      setState(() {
        _showStickerPicker = true;
        _showEmojiPicker = false;
      });
    }
  }

  Future<void> _sendStickerMessage(String stickerUrl) async {
    setState(() {
      _showStickerPicker = false;
    });

    final String tempMessageId = 'local_${DateTime.now().microsecondsSinceEpoch}';

    final ChatMessage localMessage = ChatMessage()
      ..firestoreId = tempMessageId
      ..roomId = widget.roomId
      ..senderId = widget.currentUser.id
      ..senderName = widget.currentUser.username
      ..receiverId = _otherUserId ?? ''
      ..text = 'ملصق'
      ..mediaType = 'sticker'
      ..mediaUrl = stickerUrl
      ..status = MessageStatus.pending
      ..timestamp = DateTime.now();

    try {
      await _saveLocalMessage(localMessage);
    } catch (_) {}

    if (mounted) {
      _scrollToBottom();
    }

    try {
      final cloudMessageId = await _chatService.sendMessage(
        roomId: widget.roomId,
        senderId: widget.currentUser.id,
        senderName: widget.currentUser.username,
        receiverId: _otherUserId ?? '',
        messageId: tempMessageId,
        text: 'ملصق',
        mediaType: 'sticker',
        mediaUrl: stickerUrl,
        status: MessageStatus.sent,
      );
      _monitorMessageCommit(cloudMessageId);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل إرسال الملصق: $error')),
        );
      }
      try {
        await _updateLocalMessageStatus(tempMessageId, MessageStatus.failed);
      } catch (_) {}
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

    try {
      await _saveLocalMessage(localMessage);
    } catch (_) {}

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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل الإرسال: $error')),
        );
      }
      try {
        await _updateLocalMessageStatus(tempMessageId, MessageStatus.failed);
      } catch (_) {}
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  // ✅ استخدام dynamic بدل File لتفادي أخطاء الويب
  Future<void> _uploadAndSendMedia(
    dynamic file,
    String mediaType,
    String textPlaceholder, {
    Uint8List? webBytes,
    String? webFileName,
    String? folder,
    String? fileType,
    int? fileSize,
  }) async {
    final String tempMessageId = 'local_${DateTime.now().microsecondsSinceEpoch}';
    
    String getFileName() {
      if (webFileName != null) return webFileName;
      if (file != null) return file.path.split('/').last;
      return '';
    }

    final ChatMessage localMessage = ChatMessage()
      ..firestoreId = tempMessageId
      ..roomId = widget.roomId
      ..senderId = widget.currentUser.id
      ..senderName = widget.currentUser.username
      ..receiverId = _otherUserId ?? ''
      ..text = textPlaceholder
      ..mediaType = mediaType
      ..fileName = getFileName()
      ..fileType = fileType ?? ''
      ..fileSize = fileSize ?? (file != null ? await file.length() : 0)
      ..status = MessageStatus.pending
      ..uploadProgress = 0.0
      ..uploadStartedAt = DateTime.now()
      ..replyToMessageId = _replyingTo?.firestoreId ?? ''
      ..replyToSenderName = _replyingTo?.senderName ?? ''
      ..replyToMediaType = _replyingTo?.mediaType ?? ChatMessageType.text
      ..replyToText = _replyingTo?.text ?? ''
      ..isDisappearing = _selectedDisappearingDurationSeconds > 0
      ..disappearingDurationSeconds = _selectedDisappearingDurationSeconds
      ..timestamp = DateTime.now();

    try {
      await _saveLocalMessage(localMessage);
    } catch (_) {}
    
    if (mounted) {
      _clearReply();
      _scrollToBottom();
    }

    try {
      final fileName = getFileName().isEmpty ? '${DateTime.now().millisecondsSinceEpoch}_media_file' : getFileName();
      String downloadUrl = '';
      
      bool isVideo = (mediaType == ChatMessageType.video);
      
      if (kIsWeb && webBytes != null) {
        downloadUrl = await _mediaService.uploadBytes(
          webBytes, 
          fileName, 
          isVideo: isVideo
        );
      } else if (file != null) {
        downloadUrl = await _mediaService.uploadFileWithProgress(
          file, // سيتم تمرير ملف حقيقي هنا بنجاح
          isVideo: isVideo,
          explicitFileName: fileName,
          onProgress: (progress) {
            _updateUploadProgress(tempMessageId, progress.percentComplete);
          },
        );
      } else {
        throw Exception('لم يتم العثور على ملف صالح للرفع');
      }

      if (downloadUrl.isEmpty) throw Exception('فشل الرفع عبر المحرك');

      String actualMediaType = mediaType;
      String actualFileType = fileType ?? '';
      
      if (mediaType == ChatMessageType.file) {
        final lowerFileName = fileName.toLowerCase();
        if (lowerFileName.endsWith('.pdf')) {
          actualFileType = 'pdf';
        } else if (lowerFileName.endsWith('.doc') || lowerFileName.endsWith('.docx')) {
          actualFileType = 'word';
        } else if (lowerFileName.endsWith('.xls') || lowerFileName.endsWith('.xlsx')) {
          actualFileType = 'excel';
        } else if (lowerFileName.endsWith('.ppt') || lowerFileName.endsWith('.pptx')) {
          actualFileType = 'powerpoint';
        } else if (lowerFileName.endsWith('.zip') || lowerFileName.endsWith('.rar') || lowerFileName.endsWith('.7z')) {
          actualFileType = 'archive';
        }
      }

      final cloudMessageId = await _chatService.sendMessage(
        roomId: widget.roomId,
        senderId: widget.currentUser.id,
        senderName: widget.currentUser.username,
        receiverId: _otherUserId ?? '',
        messageId: tempMessageId,
        text: textPlaceholder,
        mediaType: actualMediaType,
        mediaUrl: downloadUrl,
        fileName: actualMediaType == ChatMessageType.file ? fileName : '',
        fileType: actualMediaType == ChatMessageType.file ? actualFileType : '',
        fileSize: fileSize ?? 0,
        status: MessageStatus.sent,
        isDisappearing: _selectedDisappearingDurationSeconds > 0,
        disappearingDurationSeconds: _selectedDisappearingDurationSeconds,
        replyToMessageId: localMessage.replyToMessageId,
        replyToSenderName: localMessage.replyToSenderName,
        replyToMediaType: localMessage.replyToMediaType,
        replyToText: localMessage.replyToText,
      );

      await _updateLocalMessageStatus(
        tempMessageId,
        MessageStatus.sent,
        mediaUrl: downloadUrl,
      );
      
      _monitorMessageCommit(cloudMessageId);
    } catch (error) {
      debugPrint('Upload error: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل رفع الملف: $error')),
        );
      }
      try {
        await _updateLocalMessageStatus(
          tempMessageId,
          MessageStatus.failed,
        );
        await _updateLocalMessageError(tempMessageId, error.toString());
      } catch (_) {}
    }
  }

  Future<void> _pickMedia(ImageSource source, {bool isVideo = false}) async {
    if (source == ImageSource.camera && !_hasCamera) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الكاميرا غير مدعومة على هذا الجهاز')));
      }
      return;
    }

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
        // ✅ استخدام النوع الديناميكي
        dynamic localRealFile = io.File(file.path);
        await _uploadAndSendMedia(
          localRealFile,
          isVideo ? ChatMessageType.video : ChatMessageType.image,
          isVideo ? '🎥 فيديو' : '📷 صورة',
        );
      }
    } catch (e) {
      debugPrint('Error picking media from camera: $e');
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
          // ✅ استخدام النوع الديناميكي
          dynamic localRealFile = io.File(pickedFile.path!);
          await _uploadAndSendMedia(
            localRealFile,
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
          // ✅ استخدام النوع الديناميكي
          dynamic localRealFile = io.File(pickedFile.path!);
          await _uploadAndSendMedia(
            localRealFile,
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
      if (status == MessageStatus.sent || status == MessageStatus.failed) {
        existing.uploadProgress = status == MessageStatus.sent ? 1.0 : 0.0;
      }
      await isar.chatMessages.put(existing);
    });
  }

  Future<void> _updateUploadProgress(String firestoreId, double progress) async {
    final isar = await IsarService.init();
    if (isar == null) return;

    try {
      await isar.writeTxn(() async {
        final existing = await isar.chatMessages
            .where()
            .firestoreIdEqualTo(firestoreId)
            .build()
            .findFirst();

        if (existing == null || existing.roomId != widget.roomId) return;
        existing.uploadProgress = progress.clamp(0.0, 1.0);
        await isar.chatMessages.put(existing);
      });
      
      if (mounted) {
        setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _updateLocalMessageError(String firestoreId, String errorReason) async {
    final isar = await IsarService.init();
    if (isar == null) return;

    try {
      await isar.writeTxn(() async {
        final existing = await isar.chatMessages
            .where()
            .firestoreIdEqualTo(firestoreId)
            .build()
            .findFirst();

        if (existing == null || existing.roomId != widget.roomId) return;
        existing.uploadErrorReason = errorReason;
        await isar.chatMessages.put(existing);
      });
      
      if (mounted) {
        setState(() {});
      }
    } catch (_) {}
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
          await FirebaseFirestore.instance
              .collection('chatRooms')
              .doc(widget.roomId)
              .collection('messages')
              .doc(message.firestoreId)
              .update({'status': MessageStatus.delivered});
          
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('مراجعة التسجيل الصوتي', style: TextStyle(fontWeight: FontWeight.bold)),
          content: const Text('هل تريد إرسال التسجيل الصوتي الآن؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () async {
                if (!mounted) return;
                await _audioService.play(path);
              },
              child: const Text('استماع', style: TextStyle(color: Color(0xFF5B6CFF))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5B6CFF),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('إرسال', style: TextStyle(color: Colors.white)),
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
        // ✅ استخدام النوع الديناميكي
        dynamic localRealFile = io.File(path);
        await _uploadAndSendMedia(
          localRealFile,
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
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, -5))
            ]
          ),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 28,
            runSpacing: 28,
            children: [
              _buildAttachmentIcon(Icons.insert_drive_file_rounded, const Color(0xFF5B6CFF), 'مستند', _pickDocument),
              if (_hasCamera)
                _buildAttachmentIcon(Icons.camera_alt_rounded, const Color(0xFF10B981), 'كاميرا', () {
                  Navigator.pop(context);
                  _pickMedia(ImageSource.camera, isVideo: false);
                }),
              _buildAttachmentIcon(Icons.image_rounded, const Color(0xFFF59E0B), 'المعرض', () {
                Navigator.pop(context);
                _pickMediaFromGallery(isVideo: false);
              }),
              _buildAttachmentIcon(Icons.videocam_rounded, const Color(0xFFE94057), 'فيديو', () {
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
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1), 
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 10),
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
        ],
      ),
    );
  }

  Widget _buildPinnedBanner(Map<String, dynamic> data) {
    String text = data['text'] ?? '';
    String mediaType = data['mediaType'] ?? 'text';
    String senderName = data['senderName'] ?? '';
    
    String preview = text;
    if (mediaType == 'image') preview = '📷 صورة';
    else if (mediaType == 'video') preview = '🎥 فيديو';
    else if (mediaType == 'audio') preview = '🎤 مقطع صوتي';
    else if (mediaType == 'file') preview = '📄 ملف';
    else if (mediaType == 'sticker') preview = 'ملصق';
    else if (mediaType == 'call') preview = '📞 مكالمة';
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.push_pin, color: Color(0xFF5B6CFF), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'رسالة مثبتة',
                  style: TextStyle(
                    color: Color(0xFF5B6CFF),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  preview.isNotEmpty ? preview : 'مرفق',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FD),
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(65),
          child: AppBar(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            elevation: 1,
            shadowColor: Colors.black.withOpacity(0.3),
            iconTheme: const IconThemeData(color: Colors.black87),
            titleSpacing: 0,
            title: Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFF5B6CFF).withOpacity(0.15),
                  child: const Icon(Icons.person, color: Color(0xFF5B6CFF), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _otherUserName ?? 'دردشة خاصة',
                        style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      if (_otherUserId != null && _otherUserId!.isNotEmpty)
                        StreamBuilder<DatabaseEvent>(
                          stream: FirebaseDatabase.instance.ref().child('presence/$_otherUserId').onValue,
                          builder: (context, snapshot) {
                            bool isOnline = false;
                            if (snapshot.hasData && snapshot.data?.snapshot.value != null) {
                              final data = snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
                              isOnline = data['online'] == true;
                            }
                            return Text(
                              isOnline ? 'متصل الآن' : 'غير متصل',
                              style: TextStyle(
                                color: isOnline ? const Color(0xFF2EC7A5) : Colors.grey,
                                fontSize: 12,
                                fontWeight: isOnline ? FontWeight.bold : FontWeight.w500,
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.phone_outlined, color: Color(0xFF5B6CFF), size: 24),
                onPressed: () async {
                  if (_otherUserId == null) return;
                  try {
                    final session = await CallService.instance.initiateCall(
                      chatId: widget.roomId,
                      callerId: widget.currentUser.id,
                      callerName: widget.currentUser.username,
                      receiverId: _otherUserId!,
                      receiverName: _otherUserName ?? 'الدردشة',
                      type: 'audio',
                    );
                    if (mounted && session != null) {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => CallScreen(session: session)));
                    }
                  } catch (e) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر بدء المكالمة: $e')));
                  }
                },
              ),
              Padding(
                padding: const EdgeInsets.only(left: 6.0),
                child: IconButton(
                  icon: const Icon(Icons.videocam_outlined, color: Color(0xFF5B6CFF), size: 26),
                  onPressed: () async {
                    if (_otherUserId == null) return;
                    try {
                      final session = await CallService.instance.initiateCall(
                        chatId: widget.roomId,
                        callerId: widget.currentUser.id,
                        callerName: widget.currentUser.username,
                        receiverId: _otherUserId!,
                        receiverName: _otherUserName ?? 'الدردشة',
                        type: 'video',
                      );
                      if (mounted && session != null) {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => CallScreen(session: session)));
                      }
                    } catch (e) {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر بدء المكالمة: $e')));
                    }
                  },
                ),
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
                      return const Center(
                        child: CircularProgressIndicator(color: Color(0xFF5B6CFF)),
                      );
                    }
                    
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'تعذر تحميل الرسائل 😢',
                          style: TextStyle(color: Colors.red.shade400, fontWeight: FontWeight.bold),
                        ),
                      );
                    }

                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: const Color(0xFF5B6CFF).withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.chat_bubble_outline_rounded, size: 64, color: Color(0xFF5B6CFF)),
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              'لا توجد رسائل بعد..',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'كن أول من يبدأ المحادثة 👋',
                              style: TextStyle(color: Colors.grey, fontSize: 15),
                            ),
                          ],
                        ),
                      );
                    }

                    final docs = snapshot.data!.docs;
                    final pinnedDocs = docs.where((d) {
                      final data = d.data() as Map<String, dynamic>;
                      return data['isPinned'] == true;
                    }).toList();

                    return Column(
                      children: [
                        if (pinnedDocs.isNotEmpty)
                          _buildPinnedBanner(pinnedDocs.first.data() as Map<String, dynamic>),
                          
                        Expanded(
                          child: ListView.builder(
                            controller: _scrollController,
                            reverse: true,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
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
                                ..replyToText = data['replyToText'] ?? ''
                                ..isPinned = data['isPinned'] ?? false;

                              final isMine = message.senderId == widget.currentUser.id;

                              return MessageBubble(
                                message: message,
                                isMine: isMine,
                                onReply: (msg) {
                                  setState(() => _replyingTo = msg);
                                  _messageFocusNode.requestFocus();
                                },
                                onRetry: isMine && message.status == MessageStatus.failed
                                  ? (msg) => retryUpload(msg)
                                  : null,
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

              if (_replyingTo != null)
                Container(
                  margin: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 2))
                    ],
                    border: const Border(right: BorderSide(color: Color(0xFF5B6CFF), width: 5)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'الرد على ${_replyingTo!.senderName}',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF5B6CFF), fontSize: 13),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _replyingTo!.text.isNotEmpty ? _replyingTo!.text : 'مرفق',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.black54, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle),
                        child: IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20, color: Colors.black54),
                          onPressed: _clearReply,
                        ),
                      ),
                    ],
                  ),
                ),

              Container(
                padding: const EdgeInsets.only(left: 8, right: 8, top: 8, bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, -5)),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F2F5), 
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: Colors.grey.withOpacity(0.1)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            IconButton(
                              icon: Icon(
                                _showEmojiPicker ? Icons.keyboard_rounded : Icons.emoji_emotions_outlined,
                                color: Colors.grey[600],
                              ),
                              onPressed: _toggleEmojiPicker,
                            ),
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              icon: Icon(
                                _showStickerPicker ? Icons.keyboard_rounded : Icons.sticky_note_2_outlined,
                                color: Colors.grey[600],
                              ),
                              onPressed: _toggleStickerPicker,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _messageController,
                                focusNode: _messageFocusNode,
                                maxLines: 5,
                                minLines: 1,
                                style: const TextStyle(fontSize: 15),
                                decoration: InputDecoration(
                                  hintText: _isRecording ? 'جاري التسجيل...' : 'اكتب رسالة...',
                                  hintStyle: TextStyle(color: Colors.grey.shade500),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                readOnly: _isRecording,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.attach_file_rounded, color: Colors.grey),
                              onPressed: _showAttachmentBottomSheet,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () async {
                        if (!_isTextEmpty) {
                          await _sendTextMessage();
                        } else {
                          if (_isRecording) {
                            await _stopRecordingAndSend();
                          } else {
                            await _startRecording();
                          }
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutBack,
                        margin: const EdgeInsets.only(bottom: 2),
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: _isTextEmpty
                              ? (_isRecording ? Colors.redAccent : const Color(0xFF2EC7A5))
                              : const Color(0xFF5B6CFF),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: (_isTextEmpty
                                      ? (_isRecording ? Colors.redAccent : const Color(0xFF2EC7A5))
                                      : const Color(0xFF5B6CFF))
                                  .withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            )
                          ],
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
              if (_showStickerPicker)
                StickerPicker(
                  onStickerSelected: (dynamic sticker) async {
                    if (sticker is String) {
                       await _sendStickerMessage(sticker);
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
