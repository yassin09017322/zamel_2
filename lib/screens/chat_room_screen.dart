import 'dart:async';
import 'package:zamel_appp/src/platform_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart' as fp;
import 'package:provider/provider.dart';

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
import '../screens/call_screen.dart';
import '../widgets/message_bubble.dart';

class ChatRoomScreen extends StatefulWidget {
  final AppUser currentUser;
  final String roomId;

  const ChatRoomScreen({super.key, required this.currentUser, required this.roomId});

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

  bool _sending = false;
  bool _isTyping = false;
  bool _isRecording = false;
  bool _isInputFocused = false;
  bool _showScrollToBottom = false;
  
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
        setState(() => _isInputFocused = _messageFocusNode.hasFocus);
      }
    });
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

  void _markMessagesAsRead(List<ChatMessage> messages) {
    for (final message in messages) {
      if (message.senderId != widget.currentUser.id && message.status != MessageStatus.read) {
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
        }
      }
    }
  }

  Future<void> _uploadAndSendMedia(File? file, String mediaType, String textPlaceholder, {Uint8List? webBytes, String? webFileName, String? folder, String? publicIdOverride, String? fileType, int? fileSize}) async {
    setState(() => _sending = true);
    try {
      final fileName = webFileName ?? '${DateTime.now().millisecondsSinceEpoch}_${file?.path.split('/').last ?? 'file'}';
      final resolvedPublicId = publicIdOverride ?? '${folder ?? 'chat'}/${DateTime.now().millisecondsSinceEpoch}';
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
            resourceType: mediaType == ChatMessageType.video ? 'video' : 'image',
          );
        } else if (file != null) {
          downloadUrl = await _cloudinaryService.uploadFile(
            file,
            isVideo: mediaType == ChatMessageType.video,
            folder: 'chat',
            publicId: publicId,
            resourceType: mediaType == ChatMessageType.video ? 'video' : 'image',
          );
        }
      }

      if (downloadUrl.isEmpty) {
        throw Exception('فشل الرفع');
      }

      String initialStatus = MessageStatus.sent;
      if (_otherUserId != null && _otherUserId!.isNotEmpty) {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(_otherUserId).get();
        if (userDoc.exists && (userDoc.data()?['isOnline'] == true)) {
          initialStatus = MessageStatus.delivered;
        }
      }

      final docRef = FirebaseFirestore.instance.collection('chatRooms').doc(widget.roomId).collection('messages').doc();
      final message = ChatMessage()
        ..firestoreId = docRef.id
        ..roomId = widget.roomId
        ..senderId = widget.currentUser.id
        ..senderName = widget.currentUser.username
        ..receiverId = _otherUserId ?? ''
        ..text = textPlaceholder
        ..mediaUrl = downloadUrl
        ..mediaType = mediaType
        ..publicId = publicId
        ..fileName = mediaType == 'file' ? fileName : ''
        ..fileType = mediaType == 'file' ? (fileType ?? '') : ''
        ..fileSize = mediaType == 'file' ? (fileSize ?? 0) : 0
        ..status = initialStatus
        ..timestamp = DateTime.now();

      await docRef.set(message.toFirestore());
      await FirebaseFirestore.instance.collection('chatRooms').doc(widget.roomId).update({
        'lastMessage': textPlaceholder,
        'lastTimestamp': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فشل رفع الملف، تأكد من اتصالك')));
    } finally {
      setState(() => _sending = false);
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
        final mediaType = isVideo ? ChatMessageType.video : ChatMessageType.image;
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

  Future<void> _startRecording() async {
    try {
      final canRecord = await _audioService.checkPermission();
      if (!canRecord) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('صلاحية الميكروفون مطلوبة')));
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

      if (shouldSend != true) return;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('جاري إرسال التسجيل الصوتي...')));
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
        await _uploadAndSendMedia(File(path), ChatMessageType.audio, '🎤 مقطع صوتي');
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
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFF8FAFF), Color(0xFFEDE9FE)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.10), blurRadius: 24, offset: const Offset(0, 10)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(color: const Color(0xFF5B6CFF).withOpacity(0.28), borderRadius: BorderRadius.circular(999)),
              ),
              const SizedBox(height: 12),
              Text('إرسال شيء جديد', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 18),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 18,
                runSpacing: 18,
                children: [
                  _buildAttachmentIcon(Icons.insert_drive_file_rounded, const Color(0xFF5B6CFF), 'مستند', _pickDocument),
                  _buildAttachmentIcon(Icons.camera_alt_rounded, const Color(0xFFEC4899), 'كاميرا', () => _pickMedia(ImageSource.camera)),
                  _buildAttachmentIcon(Icons.insert_photo_rounded, const Color(0xFF8B5CF6), 'المعرض', () => _pickMedia(ImageSource.gallery)),
                  _buildAttachmentIcon(Icons.videocam_rounded, const Color(0xFFF59E0B), 'فيديو', () => _pickMedia(ImageSource.gallery, isVideo: true)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAttachmentIcon(IconData icon, Color color, String label, VoidCallback onTap) {
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
                gradient: LinearGradient(colors: [color.withOpacity(0.95), color.withOpacity(0.7)]),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: color.withOpacity(0.22), blurRadius: 12, offset: const Offset(0, 8))],
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _buildOtherUserPresenceStatus() {
    if (_otherUserId == null || _otherUserId!.isEmpty) {
      return const Text('آخر ظهور: غير متاح', style: TextStyle(fontSize: 12, color: Colors.white70));
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(_otherUserId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null || !snapshot.data!.exists) {
          return const Text('آخر ظهور: غير متاح', style: TextStyle(fontSize: 12, color: Colors.white70));
        }

        final data = snapshot.data!.data() ?? <String, dynamic>{};
        final settingsProvider = context.watch<SettingsProvider>();
        final sharePresence = settingsProvider.sharePresence;
        final online = data['isOnline'] == true;
        DateTime? lastSeen;
        final lastSeenValue = data['lastSeen'];
        if (lastSeenValue is Timestamp) {
          lastSeen = lastSeenValue.toDate();
        } else if (lastSeenValue is DateTime) {
          lastSeen = lastSeenValue;
        }

        final statusText = sharePresence
            ? (online ? 'متصل الآن' : _formatLastSeen(lastSeen))
            : 'معلومات التواجد مخفية';

        return Text(
          statusText,
          style: TextStyle(fontSize: 12, color: online ? Colors.greenAccent.shade100 : Colors.white70),
        );
      },
    );
  }

  String _formatLastSeen(DateTime? timestamp) {
    if (timestamp == null) {
      return 'آخر ظهور: غير متاح';
    }
    final difference = DateTime.now().difference(timestamp);
    if (difference.inMinutes < 1) return 'آخر ظهور الآن';
    if (difference.inHours < 1) return 'آخر ظهور منذ ${difference.inMinutes} د';
    if (difference.inDays < 1) return 'آخر ظهور منذ ${difference.inHours} س';
    return 'آخر ظهور منذ ${difference.inDays} يوم';
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
                    color: Colors.white.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Center(child: Icon(Icons.forum_rounded, color: Colors.white, size: 23)),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('دردشة خاصة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
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
                      orElse: () => room.participantNames.isNotEmpty ? room.participantNames.first : 'مستخدم',
                    );

                    return Row(
                      children: [
                        _buildTopAction(Icons.call_outlined, 'مكالمة صوتية', () => _startCall(_otherUserId!, otherUserName, 'audio')),
                        _buildTopAction(Icons.videocam_outlined, 'مكالمة فيديو', () => _startCall(_otherUserId!, otherUserName, 'video')),
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
                            colors: [Colors.white.withOpacity(0.92), Colors.white.withOpacity(0.72)],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                          borderRadius: BorderRadius.circular(32),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 26, offset: const Offset(0, 14)),
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
                                    .map((snapshot) => snapshot.docs.map((doc) => ChatMessage.fromFirestore(doc, widget.roomId)).toList())
                                : _chatSyncRepository?.watchLocalMessages(),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState == ConnectionState.waiting) {
                                return const Center(child: CircularProgressIndicator());
                              }

                              final messages = snapshot.data ?? [];
                              if (messages.isEmpty) {
                                return const Center(child: Text('لا توجد رسائل بعد. ابدأ المحادثة!'));
                              }

                              if (mounted) {
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (mounted) {
                                    _markMessagesAsRead(messages);
                                  }
                                });
                              }

                              return ListView.builder(
                                controller: _scrollController,
                                physics: const BouncingScrollPhysics(),
                                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                                itemCount: messages.length,
                                itemBuilder: (context, index) {
                                  final message = messages[index];
                                  final isMe = message.senderId == widget.currentUser.id;
                                  final showDateSeparator = index == 0 || !_isSameDay(messages[index - 1].timestamp, message.timestamp);
                                  return Column(
                                    children: [
                                      if (showDateSeparator)
                                        Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 10),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF5B6CFF).withOpacity(0.12),
                                              borderRadius: BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              _formatDateLabel(message.timestamp),
                                              style: const TextStyle(fontSize: 11, color: Color(0xFF5B6CFF), fontWeight: FontWeight.w700),
                                            ),
                                          ),
                                        ),
                                      MessageBubble(message: message, isMine: isMe),
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
                                  gradient: const LinearGradient(colors: [Color(0xFF5B6CFF), Color(0xFF8B5CF6)]),
                                  shape: BoxShape.circle,
                                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.16), blurRadius: 16, offset: const Offset(0, 8))],
                                ),
                                child: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 28),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
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
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 4))],
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.mic_rounded, color: Colors.red, size: 18),
                              const SizedBox(width: 8),
                              const Expanded(child: Text('جاري التسجيل...', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF5B6CFF)))),
                              IconButton(onPressed: _stopRecordingAndSend, icon: const Icon(Icons.send_rounded, color: Color(0xFF5B6CFF))),
                            ],
                          ),
                        ),
                      Directionality(
                        textDirection: TextDirection.rtl,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [Colors.white.withOpacity(0.95), Colors.white.withOpacity(0.88)]),
                            borderRadius: BorderRadius.circular(26),
                            border: Border.all(color: _isInputFocused ? const Color(0xFF5B6CFF).withOpacity(0.35) : Colors.white.withOpacity(0.7)),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 16, offset: const Offset(0, 8)),
                            ],
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              _buildComposerIcon(Icons.emoji_emotions_outlined, () {}, isPrimary: false),
                              Expanded(
                                child: TextField(
                                  controller: _messageController,
                                  focusNode: _messageFocusNode,
                                  maxLines: 5,
                                  minLines: 1,
                                  onChanged: (text) => setState(() => _isTyping = text.trim().isNotEmpty),
                                  style: const TextStyle(fontSize: 15),
                                  decoration: InputDecoration(
                                    hintText: _isRecording ? 'جاري التسجيل...' : 'مراسلة...',
                                    hintStyle: TextStyle(color: _isRecording ? Colors.red : Colors.grey.shade600),
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                                  ),
                                ),
                              ),
                              _buildComposerIcon(Icons.attach_file_rounded, _showAttachmentBottomSheet, isPrimary: false),
                              if (!_isTyping && !_isRecording)
                                _buildComposerIcon(Icons.camera_alt_rounded, () => _pickMedia(ImageSource.camera), isPrimary: false),
                              if (_isTyping && !_isRecording)
                                _buildComposerIcon(Icons.send_rounded, _sending ? null : _sendText, isPrimary: true),
                              if (!_isTyping && !_isRecording)
                                GestureDetector(
                                  onLongPress: _startRecording,
                                  onLongPressUp: _stopRecordingAndSend,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 220),
                                    width: 48,
                                    height: 48,
                                    margin: const EdgeInsets.only(left: 4),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(colors: _isRecording ? [Colors.red, Colors.redAccent] : const [Color(0xFF5B6CFF), Color(0xFF8B5CF6)]),
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.14), blurRadius: 10, offset: const Offset(0, 6))],
                                    ),
                                    child: _sending
                                        ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2))
                                        : Icon(Icons.mic_rounded, color: Colors.white, size: 24),
                                  ),
                                ),
                              if (_isTyping && !_isRecording)
                                const SizedBox.shrink(),
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

  Widget _buildTopAction(IconData icon, String tooltip, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: IconButton(
        tooltip: tooltip,
        icon: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.16), borderRadius: BorderRadius.circular(14)),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildComposerIcon(IconData icon, VoidCallback? onPressed, {required bool isPrimary}) {
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
              color: isPrimary ? const Color(0xFF5B6CFF) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 22, color: isPrimary ? Colors.white : const Color(0xFF5B6CFF)),
          ),
        ),
      ),
    );
  }

  bool _isSameDay(DateTime first, DateTime second) {
    return first.year == second.year && first.month == second.month && first.day == second.day;
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

    if (mounted) {
      setState(() {
        _sending = true;
        _isTyping = false;
      });
    }

    try {
      String initialStatus = MessageStatus.sent;
      if (_otherUserId != null && _otherUserId!.isNotEmpty) {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(_otherUserId).get();
        if (userDoc.exists && (userDoc.data()?['isOnline'] == true)) {
          initialStatus = MessageStatus.delivered;
        }
      }

      await _chatService.sendMessage(
        roomId: widget.roomId,
        senderId: widget.currentUser.id,
        senderName: widget.currentUser.username,
        receiverId: _otherUserId ?? '',
        text: text,
        status: initialStatus,
      );

      final querySnapshot = await FirebaseFirestore.instance.collection('chatRooms').doc(widget.roomId).collection('messages').orderBy('timestamp', descending: true).limit(1).get();
      if (querySnapshot.docs.isNotEmpty) {
        await FirebaseFirestore.instance.collection('chatRooms').doc(widget.roomId).collection('messages').doc(querySnapshot.docs.first.id).update({'status': initialStatus});
        await FirebaseFirestore.instance.collection('chats').doc(widget.roomId).collection('messages').doc(querySnapshot.docs.first.id).update({'status': initialStatus});
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فشل إرسال الرسالة')));
      }
    } finally {
      if (mounted) {
        _messageController.clear();
        setState(() {
          _sending = false;
          _isTyping = false;
        });
      }
    }
  }

  Future<void> _startCall(String otherUserId, String otherUserName, String type) async {
    try {
      final session = await CallService.instance.initiateCall(
        chatId: widget.roomId, callerId: widget.currentUser.id, callerName: widget.currentUser.username, receiverId: otherUserId, receiverName: otherUserName, type: type,
      );
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CallScreen(session: session)));
    } catch (_) {}
  }
}