import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/channel.dart';
import '../models/channel_message.dart';
import '../providers/auth_provider.dart';
import '../services/channel_service.dart';
import '../services/media_service.dart';

class ChannelScreen extends StatefulWidget {
  final String channelId;
  const ChannelScreen({super.key, required this.channelId});

  @override
  State<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends State<ChannelScreen> {
  final ChannelService _channelService = ChannelService();
  final MediaService _mediaService = MediaService();
  final TextEditingController _textController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  bool _isPublishing = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
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
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return const Center(child: Text('تعذر تحميل القناة'));
          }

          final channel = snapshot.data!;

          return Column(
            children: [
              Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: CachedNetworkImage(
                        imageUrl: channel.imageUrl,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => const SizedBox(
                          width: 72,
                          height: 72,
                          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          width: 72,
                          height: 72,
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.broken_image_outlined),
                        ),
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
              Expanded(
                child: StreamBuilder<List<ChannelMessage>>(
                  stream: _channelService.messagesStream(widget.channelId),
                  builder: (context, messagesSnapshot) {
                    if (messagesSnapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (messagesSnapshot.hasError) {
                      return Center(child: Text('تعذر تحميل المنشورات: ${messagesSnapshot.error}'));
                    }

                    final messages = messagesSnapshot.data ?? [];
                    if (messages.isEmpty) {
                      return const Center(child: Text('لا توجد منشورات في هذه القناة')); 
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      itemCount: messages.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, index) {
                        final message = messages[index];
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(message.senderName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(height: 6),
                                if (message.text.isNotEmpty) Text(message.text),
                                if (message.mediaUrl.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  CachedNetworkImage(imageUrl: message.mediaUrl),
                                ],
                                const SizedBox(height: 8),
                                Text(
                                  '${message.createdAt.day}/${message.createdAt.month}/${message.createdAt.year}',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ],
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
                          decoration: const InputDecoration(
                            hintText: 'اكتب منشوراً أو ضع رابطاً',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _isPublishing ? null : () => _pickAndPublishMedia(context, currentUser?.id ?? ''),
                        icon: const Icon(Icons.image_outlined),
                      ),
                      IconButton(
                        onPressed: _isPublishing ? null : () => _pickAndPublishMedia(context, currentUser?.id ?? '', isVideo: true),
                        icon: const Icon(Icons.videocam_outlined),
                      ),
                      IconButton(
                        onPressed: _isPublishing ? null : () => _publishTextMessage(currentUser),
                        icon: const Icon(Icons.send),
                      ),
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
    if (text.isEmpty) {
      return;
    }

    setState(() => _isPublishing = true);
    try {
      await _channelService.publishMessage(
        channelId: widget.channelId,
        senderId: currentUser.id,
        senderName: currentUser.username,
        text: text,
      );
      _textController.clear();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فشل نشر المنشور')),
      );
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  Future<void> _pickAndPublishMedia(BuildContext context, String currentUserId, {bool isVideo = false}) async {
    final result = await FilePicker.platform.pickFiles(
      type: isVideo ? FileType.video : FileType.image,
      allowCompression: true,
      withData: kIsWeb,
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final uploadTarget = file.path != null ? File(file.path!) : null;

    setState(() => _isPublishing = true);
    try {
      final uploadedUrl = kIsWeb
          ? await _mediaService.uploadBytes(
              file.bytes!,
              file.name,
              isVideo: isVideo,
            )
          : await _mediaService.uploadFile(uploadTarget!, isVideo: isVideo);

      await _channelService.publishMessage(
        channelId: widget.channelId,
        senderId: currentUserId,
        senderName: context.read<AuthProvider>().currentUser?.username ?? 'admin',
        text: _textController.text.trim(),
        mediaUrl: uploadedUrl,
        mediaType: isVideo ? 'video' : 'image',
      );

      _textController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نشر المحتوى بنجاح')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل رفع المحتوى: $error')),
      );
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }
}
