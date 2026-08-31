import 'dart:io';
import 'package:zamel_appp/src/platform_file.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../models/channel.dart';
import '../models/channel_message.dart';
import '../providers/auth_provider.dart';
import '../services/channel_service.dart';
import '../services/media_service.dart';
import '../services/audio_service.dart';

class ChannelScreen extends StatefulWidget {
  final String channelId;
  const ChannelScreen({super.key, required this.channelId});

  @override
  State<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends State<ChannelScreen> {
  final ChannelService _channelService = ChannelService();
  final MediaService _mediaService = MediaService();
  final AudioCommentService _audioService = AudioCommentService();
  
  final TextEditingController _textController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  
  bool _isPublishing = false;
  bool _isRecording = false;

  @override
  void dispose() {
    _textController.dispose();
    _audioService.dispose();
    super.dispose();
  }

  // --- دوال التسجيل الصوتي ---
  Future<void> _startRecording() async {
    try {
      final canRecord = await _audioService.checkPermission();
      if (!canRecord) {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('صلاحية الميكروفون مطلوبة')));
        return;
      }
      final path = await _audioService.startRecording();
      setState(() => _isRecording = path != null);
    } catch (e) {
      debugPrint('Error starting record: $e');
    }
  }

  Future<void> _stopRecordingAndSend(String currentUserId, String currentUserName) async {
    try {
      final path = await _audioService.stopRecording();
      setState(() => _isRecording = false);
      if (!mounted || path == null) return;

      final shouldSend = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('مراجعة التسجيل الصوتي'),
          content: const Text('هل تريد إرسال التسجيل الصوتي للقناة؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
            TextButton(onPressed: () async => await _audioService.play(path), child: const Text('استماع')),
            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5B6CFF)), onPressed: () => Navigator.pop(context, true), child: const Text('إرسال')),
          ],
        ),
      );

      if (shouldSend != true) return;
      
      setState(() => _isPublishing = true);
      String uploadedUrl = '';
      if (kIsWeb) {
        final res = await _audioService.uploadAudioFile(path);
        if (res != null) uploadedUrl = res['url'] as String;
      } else {
        uploadedUrl = await _mediaService.uploadFile(File(path), isVideo: false, explicitFileName: 'audio_${DateTime.now().millisecondsSinceEpoch}.m4a');
      }

      if (uploadedUrl.isNotEmpty) {
        await _channelService.publishMessage(channelId: widget.channelId, senderId: currentUserId, senderName: currentUserName, text: '🎤 مقطع صوتي', mediaUrl: uploadedUrl, mediaType: 'audio');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الإرسال: $e')));
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  // --- خيارات الضغط المطول ---
  void _showLongPressOptions(BuildContext context, ChannelMessage message, String currentUserId, bool isAdmin) {
    if (currentUserId.isEmpty) return;
    final emojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(30)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isAdmin) ...[
              ListTile(
                leading: const Icon(Icons.push_pin, color: Colors.blue),
                title: const Text('تثبيت الرسالة', style: TextStyle(fontWeight: FontWeight.bold)),
                onTap: () {
                  _channelService.pinMessage(channelId: widget.channelId, messageId: message.id);
                  Navigator.pop(ctx);
                },
              ),
              const Divider(),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: emojis.map((emoji) => GestureDetector(
                  onTap: () {
                    Navigator.pop(ctx);
                    _channelService.toggleReaction(channelId: widget.channelId, messageId: message.id, emoji: emoji, userId: currentUserId);
                  },
                  child: Text(emoji, style: const TextStyle(fontSize: 32)),
                )).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReactionsWidget(ChannelMessage message, String currentUserId) {
    return Wrap(
      spacing: 6, runSpacing: 6,
      children: message.reactions.entries.map((entry) {
        final emoji = entry.key;
        final users = List<String>.from(entry.value);
        final count = users.length;
        final iReacted = users.contains(currentUserId);
        if (count == 0) return const SizedBox.shrink();

        return InkWell(
          onTap: currentUserId.isNotEmpty ? () {
            _channelService.toggleReaction(channelId: widget.channelId, messageId: message.id, emoji: emoji, userId: currentUserId);
          } : null,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: iReacted ? const Color(0xFF5B6CFF).withOpacity(0.1) : Colors.grey.shade100,
              border: Border.all(color: iReacted ? const Color(0xFF5B6CFF).withOpacity(0.5) : Colors.grey.shade300),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 4),
                Text(count.toString(), style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: iReacted ? const Color(0xFF5B6CFF) : Colors.black87)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  void _openCommentsSheet(ChannelMessage message) {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (context) => _CommentsSheet(channelId: widget.channelId, parentMessage: message));
  }

  Widget _buildPinnedMessageBanner(Channel channel) {
    return FutureBuilder<ChannelMessage?>(
      future: _channelService.getMessage(channelId: widget.channelId, messageId: channel.pinnedMessageId),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) return const SizedBox.shrink();
        final msg = snapshot.data!;
        
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: Colors.blue.shade50, border: Border(bottom: BorderSide(color: Colors.blue.shade100))),
          child: Row(
            children: [
              const Icon(Icons.push_pin, size: 16, color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(child: Text(msg.text.isNotEmpty ? msg.text : 'رسالة مثبتة', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blue))),
              IconButton(icon: const Icon(Icons.close, size: 16), onPressed: () => _channelService.unpinMessage(channelId: widget.channelId))
            ],
          ),
        );
      },
    );
  }

  // --- 🔥 دالة إنشاء الاستطلاع ---
  void _showCreatePollDialog(String userId, String userName) {
    final questionController = TextEditingController();
    final option1Controller = TextEditingController();
    final option2Controller = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('إنشاء استطلاع رأي', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: questionController, decoration: const InputDecoration(labelText: 'السؤال', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: option1Controller, decoration: const InputDecoration(labelText: 'الخيار الأول', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(controller: option2Controller, decoration: const InputDecoration(labelText: 'الخيار الثاني', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              const Text('ملاحظة: يدعم الاستطلاع حالياً خيارين أساسيين.', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5B6CFF)),
            onPressed: () {
              final q = questionController.text.trim();
              final o1 = option1Controller.text.trim();
              final o2 = option2Controller.text.trim();
              
              if (q.isNotEmpty && o1.isNotEmpty && o2.isNotEmpty) {
                _channelService.publishPoll(channelId: widget.channelId, senderId: userId, senderName: userName, question: q, options: [o1, o2]);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نشر الاستطلاع')));
              }
            },
            child: const Text('نشر الاستطلاع', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // --- 🔥 تصميم شكل الاستطلاع للمستخدم ---
  Widget _buildPollWidget(ChannelMessage message, String currentUserId) {
    final extraData = message.extraData;
    final question = extraData['pollQuestion'] as String? ?? 'استطلاع';
    final options = List<dynamic>.from(extraData['pollOptions'] ?? []);
    
    int totalVotes = 0;
    for (var opt in options) {
      totalVotes += List<String>.from(opt['votes'] ?? []).length;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF5B6CFF).withOpacity(0.3))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.poll, color: Color(0xFF5B6CFF)),
              const SizedBox(width: 8),
              Expanded(child: Text(question, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
            ],
          ),
          const SizedBox(height: 12),
          ...options.map((opt) {
            final optionId = opt['id'] as String;
            final text = opt['text'] as String;
            final votes = List<String>.from(opt['votes'] ?? []);
            final voteCount = votes.length;
            final percentage = totalVotes == 0 ? 0.0 : (voteCount / totalVotes);
            final iVoted = votes.contains(currentUserId);

            return GestureDetector(
              onTap: currentUserId.isNotEmpty ? () {
                _channelService.voteOnPoll(channelId: widget.channelId, messageId: message.id, optionId: optionId, userId: currentUserId);
              } : null,
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: Stack(
                  children: [
                    Container(height: 40, width: double.infinity, decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8))),
                    FractionallySizedBox(
                      widthFactor: percentage,
                      child: Container(height: 40, decoration: BoxDecoration(color: iVoted ? const Color(0xFF5B6CFF).withOpacity(0.3) : const Color(0xFF5B6CFF).withOpacity(0.1), borderRadius: BorderRadius.circular(8))),
                    ),
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(child: Text(text, style: TextStyle(fontWeight: iVoted ? FontWeight.bold : FontWeight.normal))),
                            Text('${(percentage * 100).toInt()}%', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
          const SizedBox(height: 4),
          Text('$totalVotes أصوات', style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final currentUser = authProvider.currentUser;
    final isAdmin = currentUser?.role == 'admin';

    return Scaffold(
      appBar: AppBar(title: const Text('القناة')),
      body: FutureBuilder<Channel?>(
        future: _channelService.getChannel(widget.channelId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError || snapshot.data == null) return const Center(child: Text('تعذر تحميل القناة'));

          final channel = snapshot.data!;

          return Column(
            children: [
              Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(18)),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: CachedNetworkImage(
                        imageUrl: channel.imageUrl, width: 72, height: 72, fit: BoxFit.cover,
                        placeholder: (_, __) => const SizedBox(width: 72, height: 72, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
                        errorWidget: (_, __, ___) => Container(width: 72, height: 72, color: Colors.grey.shade200, child: const Icon(Icons.broken_image_outlined)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(channel.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                          const SizedBox(height: 4),
                          Text(channel.description, style: const TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              if (channel.pinnedMessageId.isNotEmpty) 
                _buildPinnedMessageBanner(channel),

              Expanded(
                child: StreamBuilder<List<ChannelMessage>>(
                  stream: _channelService.messagesStream(widget.channelId),
                  builder: (context, messagesSnapshot) {
                    if (messagesSnapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                    if (messagesSnapshot.hasError) return Center(child: Text('تعذر تحميل المنشورات: ${messagesSnapshot.error}'));

                    final messages = messagesSnapshot.data ?? [];
                    if (messages.isEmpty) return const Center(child: Text('لا توجد منشورات في هذه القناة')); 

                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      itemCount: messages.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, index) {
                        final message = messages[index];
                        
                        return GestureDetector(
                          onLongPress: () => _showLongPressOptions(context, message, currentUser?.id ?? '', isAdmin),
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(message.senderName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 6),
                                  
                                  // 🔥 التحقق إذا كانت الرسالة استطلاع يتم رسمه، وإلا رسالة عادية
                                  if (message.extraData['isPoll'] == true)
                                    _buildPollWidget(message, currentUser?.id ?? '')
                                  else ...[
                                    if (message.text.isNotEmpty && message.mediaType != 'audio') Text(message.text),
                                    if (message.mediaUrl.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      if (message.mediaType == 'image')
                                        ClipRRect(borderRadius: BorderRadius.circular(8), child: CachedNetworkImage(imageUrl: message.mediaUrl))
                                      else if (message.mediaType == 'video')
                                        Container(
                                          height: 200, width: double.infinity,
                                          decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)),
                                          child: const Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 50)),
                                        )
                                      else if (message.mediaType == 'audio')
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.mic, color: Color(0xFF5B6CFF)),
                                              const SizedBox(width: 8),
                                              const Text('مقطع صوتي', style: TextStyle(fontWeight: FontWeight.bold)),
                                              const Spacer(),
                                              IconButton(
                                                icon: const Icon(Icons.play_arrow_rounded, color: Color(0xFF5B6CFF)),
                                                onPressed: () => _audioService.play(message.mediaUrl), 
                                              )
                                            ],
                                          ),
                                        )
                                    ],
                                  ],

                                  const SizedBox(height: 8),
                                  Text('${message.createdAt.day}/${message.createdAt.month}/${message.createdAt.year}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                  
                                  const Divider(height: 24),
                                  Row(
                                    children: [
                                      if (message.reactions.isNotEmpty)
                                        Expanded(child: _buildReactionsWidget(message, currentUser?.id ?? '')),
                                      if (message.reactions.isEmpty) const Spacer(),
                                      
                                      InkWell(
                                        onTap: () => _openCommentsSheet(message),
                                        borderRadius: BorderRadius.circular(20),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade100,
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.mode_comment_outlined, size: 18, color: Colors.black54),
                                              const SizedBox(width: 6),
                                              Text(
                                                message.replyCount > 0 ? '${message.replyCount} تعليق' : 'تعليق',
                                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              if (isAdmin)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border(top: BorderSide(color: Colors.grey.shade300)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          minLines: 1,
                          maxLines: 4,
                          decoration: InputDecoration(
                            hintText: _isRecording ? 'جاري التسجيل...' : 'اكتب منشوراً أو ضع رابطاً',
                            border: const OutlineInputBorder(),
                            filled: _isRecording,
                            fillColor: Colors.red.withOpacity(0.1),
                          ),
                          readOnly: _isRecording,
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        onPressed: _isPublishing ? null : () {
                          if (_isRecording) {
                            _stopRecordingAndSend(currentUser?.id ?? '', currentUser?.username ?? 'admin');
                          } else {
                            _startRecording();
                          }
                        },
                        icon: Icon(_isRecording ? Icons.stop_circle : Icons.mic_none, color: _isRecording ? Colors.red : Colors.black87),
                      ),
                      if (!_isRecording) ...[
                        IconButton(
                          onPressed: _isPublishing ? null : () => _pickAndPublishMedia(context, currentUser?.id ?? ''),
                          icon: const Icon(Icons.image_outlined),
                        ),
                        // 🔥 زر الاستطلاع الجديد
                        IconButton(
                          onPressed: _isPublishing ? null : () => _showCreatePollDialog(currentUser?.id ?? '', currentUser?.username ?? 'admin'),
                          icon: const Icon(Icons.poll_outlined),
                        ),
                        IconButton(
                          onPressed: _isPublishing ? null : () => _publishTextMessage(currentUser),
                          icon: const Icon(Icons.send),
                        ),
                      ]
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _publishTextMessage(dynamic currentUser) async {
    if (currentUser == null) return;
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isPublishing = true);
    try {
      await _channelService.publishMessage(channelId: widget.channelId, senderId: currentUser.id, senderName: currentUser.username, text: text);
      _textController.clear();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فشل نشر المنشور')));
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  Future<void> _pickAndPublishMedia(BuildContext context, String currentUserId, {bool isVideo = false}) async {
    final result = await FilePicker.platform.pickFiles(type: isVideo ? FileType.video : FileType.image, allowCompression: true, withData: kIsWeb);
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final uploadTarget = file.path != null ? File(file.path!) : null;

    setState(() => _isPublishing = true);
    try {
      final uploadedUrl = kIsWeb
          ? await _mediaService.uploadBytes(file.bytes!, file.name, isVideo: isVideo)
          : await _mediaService.uploadFile(uploadTarget!, isVideo: isVideo, explicitFileName: file.name);

      await _channelService.publishMessage(
        channelId: widget.channelId, senderId: currentUserId, senderName: context.read<AuthProvider>().currentUser?.username ?? 'admin',
        text: _textController.text.trim(), mediaUrl: uploadedUrl, mediaType: isVideo ? 'video' : 'image',
      );
      _textController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نشر المحتوى بنجاح')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل رفع المحتوى: $error')));
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }
}

// --- 🔥 واجهة عرض وإضافة التعليقات (Bottom Sheet) ---
class _CommentsSheet extends StatefulWidget {
  final String channelId;
  final ChannelMessage parentMessage;

  const _CommentsSheet({required this.channelId, required this.parentMessage});

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final ChannelService _channelService = ChannelService();
  final TextEditingController _commentController = TextEditingController();
  bool _isPublishing = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _sendComment(String userId, String userName) async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isPublishing = true);
    try {
      await _channelService.publishComment(
        channelId: widget.channelId,
        parentMessageId: widget.parentMessage.id,
        senderId: userId,
        senderName: userName,
        text: text,
      );
      _commentController.clear();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final currentUser = authProvider.currentUser;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75, 
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10))),
          ),
          const Text('التعليقات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.format_quote, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(child: Text(widget.parentMessage.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.black54))),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<List<ChannelMessage>>(
              stream: _channelService.commentsStream(widget.channelId, widget.parentMessage.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (snapshot.hasError) return const Center(child: Text('تعذر تحميل التعليقات'));

                final comments = snapshot.data ?? [];
                if (comments.isEmpty) return const Center(child: Text('كن أول من يعلق!'));

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: comments.length,
                  itemBuilder: (context, index) {
                    final comment = comments[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: const Color(0xFF5B6CFF).withOpacity(0.2),
                            child: Text(comment.senderName.substring(0, 1).toUpperCase(), style: const TextStyle(color: Color(0xFF5B6CFF), fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(comment.senderName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                      const Spacer(),
                                      Text(timeago.format(comment.createdAt, locale: 'ar'), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(comment.text, style: const TextStyle(fontSize: 14)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 8, left: 12, right: 12, top: 8),
            decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))]),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    decoration: InputDecoration(
                      hintText: 'اكتب تعليقاً...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _isPublishing || currentUser == null ? null : () => _sendComment(currentUser.id, currentUser.username),
                  icon: _isPublishing 
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send, color: Color(0xFF5B6CFF)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
