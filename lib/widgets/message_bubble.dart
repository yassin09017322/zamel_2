import 'package:zamel_appp/src/platform_file.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'message_status_indicator.dart';
// removed unused import
import 'package:firebase_storage/firebase_storage.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';

import '../models/chat_message.dart';
import '../screens/profile_screen.dart';
import '../services/audio_playback_service.dart';
import '../services/chat_service.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;
  final void Function(ChatMessage)? onReply;

  const MessageBubble({super.key, required this.message, required this.isMine, this.onReply});

  Future<void> _showMessageOptions(BuildContext context) async {
    final options = <Widget>[];

    if (isMine) {
      options.add(ListTile(
        leading: const Icon(Icons.edit_outlined, color: Color(0xFF5B6CFF)),
        title: const Text('تعديل الرسالة'),
        onTap: () async {
          Navigator.pop(context);
          final controller = TextEditingController(text: message.text);
          final updated = await showDialog<String>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('تعديل الرسالة'),
              content: TextField(
                controller: controller,
                autofocus: true,
                maxLines: 4,
                decoration: const InputDecoration(hintText: 'اكتب الرسالة الجديدة'),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
                ElevatedButton(
                  onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
                  child: const Text('حفظ'),
                ),
              ],
            ),
          );

          if (updated != null && updated.trim().isNotEmpty) {
            await ChatService().updateMessage(roomId: message.roomId, messageId: message.firestoreId, newText: updated.trim());
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تعديل الرسالة')));
            }
          }
        },
      ));
    }

    options.add(ListTile(
      leading: const Icon(Icons.share_outlined, color: Color(0xFF5B6CFF)),
      title: const Text('مشاركة الرسالة'),
      onTap: () async {
        Navigator.pop(context);
        final shareText = message.mediaType == ChatMessageType.text ? message.text : message.mediaUrl;
        await Share.share(shareText.isNotEmpty ? shareText : 'رسالة من زامل', subject: 'مشاركة رسالة');
      },
    ));

    options.add(ListTile(
      leading: Icon(message.isPinned ? Icons.push_pin : Icons.push_pin_outlined, color: const Color(0xFF5B6CFF)),
      title: Text(message.isPinned ? 'إلغاء التثبيت' : 'تثبيت الرسالة'),
      onTap: () async {
        Navigator.pop(context);
        await ChatService().pinMessage(roomId: message.roomId, messageId: message.firestoreId, pin: !message.isPinned);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message.isPinned ? 'تم إلغاء التثبيت' : 'تم تثبيت الرسالة')));
        }
      },
    ));

    if (isMine) {
      options.add(ListTile(
        leading: const Icon(Icons.delete_outline, color: Colors.red),
        title: const Text('حذف الرسالة', style: TextStyle(color: Colors.red)),
        onTap: () async {
          Navigator.pop(context);
          final confirm = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('حذف الرسالة'),
              content: const Text('هل تريد حذف هذه الرسالة؟'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('حذف', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          );

          if (confirm == true) {
            await ChatService().deleteMessage(roomId: message.roomId, messageId: message.firestoreId, publicId: message.publicId);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف الرسالة')));
            }
          }
        },
      ));
    } else {
      options.add(ListTile(
        leading: const Icon(Icons.delete_outline, color: Colors.red),
        title: const Text('حذف الرسالة', style: TextStyle(color: Colors.red)),
        onTap: () async {
          Navigator.pop(context);
          final confirm = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('حذف الرسالة'),
              content: const Text('هل تريد حذف هذه الرسالة؟'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('حذف', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          );

          if (confirm == true) {
            await ChatService().deleteMessage(roomId: message.roomId, messageId: message.firestoreId, publicId: message.publicId);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف الرسالة')));
            }
          }
        },
      ));
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(999)),
                ),
                ...options,
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bubbleColor = isMine ? const Color(0xFF5B6CFF) : Colors.grey[200];
    final textColor = isMine ? Colors.white : Colors.black87;
    final align = isMine ? Alignment.centerRight : Alignment.centerLeft;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(isMine ? 18 : 4),
      bottomRight: Radius.circular(isMine ? 4 : 18),
    );

    return Align(
      alignment: align,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        child: GestureDetector(
          onLongPress: () => _showMessageOptions(context),
          onHorizontalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            if (velocity.abs() > 400 && onReply != null) {
              onReply!(message);
            }
          },
          onTap: message.mediaType == ChatMessageType.text ? () => _showMessageOptions(context) : null,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: EdgeInsets.all(message.mediaType == ChatMessageType.text ? 12 : 6),
            decoration: BoxDecoration(color: bubbleColor, borderRadius: radius),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.isPinned)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.push_pin, size: 14, color: textColor.withOpacity(0.8)),
                        const SizedBox(width: 4),
                        Text('مثبت', style: TextStyle(fontSize: 11, color: textColor.withOpacity(0.8), fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                if (message.senderName.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(userId: message.senderId))),
                      child: Text(
                        message.senderName,
                        style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.8), fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),

                if (message.replyToMessageId.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: isMine ? Colors.white24 : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.withOpacity(0.24)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message.replyToSenderName.isNotEmpty ? message.replyToSenderName : 'رسالة',
                          style: TextStyle(fontSize: 11, color: textColor.withOpacity(0.65), fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _buildReplyPreviewText(message),
                          style: TextStyle(fontSize: 13, color: textColor.withOpacity(0.8)),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                if (message.mediaType == ChatMessageType.image && message.mediaUrl.isNotEmpty)
                  GestureDetector(
                    onTap: () => _openFullScreen(context),
                    child: Hero(
                      tag: message.firestoreId,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: CachedNetworkImage(
                          imageUrl: message.mediaUrl,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => _buildPlaceholder(),
                          errorWidget: (context, url, error) => _buildErrorHolder(),
                        ),
                      ),
                    ),
                  )
                else if (message.mediaType == ChatMessageType.video && message.mediaUrl.isNotEmpty)
                  GestureDetector(
                    onTap: () => _openFullScreen(context),
                    child: Hero(
                      tag: message.firestoreId,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(height: 200, width: double.infinity, color: Colors.black87),
                            const Icon(Icons.play_circle_fill, color: Colors.white, size: 60),
                          ],
                        ),
                      ),
                    ),
                  )
                else if (message.mediaType == 'file' && message.mediaUrl.isNotEmpty)
                  _FileMessageWidget(message: message, isMine: isMine)
                else if (message.mediaType == ChatMessageType.audio && message.mediaUrl.isNotEmpty)
                  _AudioMessageWidget(message: message, isMine: isMine)
                else if (message.mediaType == ChatMessageType.call)
                  Container(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.call, color: textColor, size: 20),
                        const SizedBox(width: 8),
                        Text(message.text, style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  )
                else
                  GestureDetector(
                    onTap: message.mediaType == ChatMessageType.text ? () => _showMessageOptions(context) : null,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(message.text.isNotEmpty ? message.text : 'رسالة', style: TextStyle(color: textColor, fontSize: 15)),
                    ),
                  ),

                Padding(
                  padding: const EdgeInsets.only(top: 4, right: 4, left: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        _formatTimestamp(message.timestamp),
                        style: TextStyle(fontSize: 11, color: textColor.withOpacity(0.7)),
                      ),
                      if (isMine) ...[
                      const SizedBox(width: 4),
                      message.status == MessageStatus.pending
                        ? PendingIndicator(size: 14.0, color: textColor.withOpacity(0.9))
                        : Icon(
                          message.status == MessageStatus.failed
                            ? Icons.error_outline_rounded
                            : message.status == MessageStatus.seen || message.status == 'read'
                              ? Icons.done_all
                              : message.status == MessageStatus.delivered
                                ? Icons.done_all
                                : Icons.check,
                          size: 16,
                          color: message.status == MessageStatus.failed
                            ? Colors.redAccent.shade100
                            : message.status == MessageStatus.seen || message.status == 'read'
                              ? Colors.blueAccent.shade100
                              : message.status == MessageStatus.delivered
                                ? Colors.white70
                                : Colors.white54,
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(height: 200, width: double.infinity, color: Colors.black12, child: const Center(child: CircularProgressIndicator(strokeWidth: 2)));
  }

  Widget _buildErrorHolder() {
    return Container(height: 200, width: double.infinity, color: Colors.black12, child: const Center(child: Icon(Icons.broken_image, size: 40, color: Colors.grey)));
  }

  void _openFullScreen(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => _FullScreenMediaScreen(message: message, isMine: isMine)));
  }

  String _buildReplyPreviewText(ChatMessage message) {
    if (message.replyToMediaType == ChatMessageType.text) {
      return message.replyToText.isNotEmpty ? message.replyToText : 'رسالة نصية';
    }
    if (message.replyToMediaType == ChatMessageType.image) return 'صورة';
    if (message.replyToMediaType == ChatMessageType.video) return 'فيديو';
    if (message.replyToMediaType == ChatMessageType.audio) return 'مقطع صوتي';
    if (message.replyToMediaType == 'file') return 'ملف';
    if (message.replyToMediaType == ChatMessageType.call) return 'مكالمة';
    return 'رسالة';
  }

  String _formatTimestamp(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inHours < 1) return '${diff.inMinutes} د';
    if (diff.inDays < 1) return '${diff.inHours} س';
    return '${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
  }
}

class _FullScreenMediaScreen extends StatefulWidget {
  final ChatMessage message;
  final bool isMine;

  const _FullScreenMediaScreen({required this.message, required this.isMine});

  @override
  State<_FullScreenMediaScreen> createState() => _FullScreenMediaScreenState();
}

class _FullScreenMediaScreenState extends State<_FullScreenMediaScreen> {
  VideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();
    if (widget.message.mediaType == ChatMessageType.video) {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(widget.message.mediaUrl))
        ..initialize().then((_) {
          setState(() {});
          _videoController!.play();
        });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _handleAction(String action) async {
    final context = this.context;
    try {
      if (action == 'share') {
        await Share.share(widget.message.mediaUrl, subject: 'مشاركة ملف من زامل');
      } else if (action == 'save') {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('جاري الحفظ...')));
      } else if (action == 'delete') {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('حذف الرسالة'),
            content: const Text('هل أنت متأكد من حذف هذه الرسالة؟ سيتم مسحها من السيرفر تماماً.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(c, true),
                child: const Text('حذف', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );

        if (confirm == true && context.mounted) {
          // تم التعديل: حذف الملف من السيرفر (Storage) أولاً لمنع تسريب المساحة
          if (widget.message.mediaUrl.isNotEmpty) {
            try {
              await FirebaseStorage.instance.refFromURL(widget.message.mediaUrl).delete();
            } catch (e) {
              debugPrint('Storage delete error: $e');
            }
          }
          await ChatService().deleteMessage(
            roomId: widget.message.roomId,
            messageId: widget.message.firestoreId,
            publicId: widget.message.publicId,
          );
              
          if (context.mounted) Navigator.pop(context);
        }
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حدث خطأ أثناء تنفيذ العملية')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.message.mediaType == ChatMessageType.video;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.5),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: _handleAction,
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem(value: 'save', child: Row(children: [Icon(Icons.download), SizedBox(width: 8), Text('حفظ')])),
              const PopupMenuItem(value: 'share', child: Row(children: [Icon(Icons.share), SizedBox(width: 8), Text('مشاركة')])),
              if (widget.isMine)
                const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, color: Colors.red), SizedBox(width: 8), Text('حذف', style: TextStyle(color: Colors.red))])),
            ],
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Center(
        child: Hero(
          tag: widget.message.firestoreId,
          child: isVideo
              ? (_videoController != null && _videoController!.value.isInitialized)
                  ? AspectRatio(
                      aspectRatio: _videoController!.value.aspectRatio,
                      child: Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          VideoPlayer(_videoController!),
                          VideoProgressIndicator(_videoController!, allowScrubbing: true, colors: const VideoProgressColors(playedColor: Color(0xFF5B6CFF))),
                          Center(
                            child: IconButton(
                              iconSize: 64,
                              icon: Icon(_videoController!.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, color: Colors.white.withOpacity(0.8)),
                              onPressed: () => setState(() { _videoController!.value.isPlaying ? _videoController!.pause() : _videoController!.play(); }),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const CircularProgressIndicator()
              : InteractiveViewer(
                  panEnabled: true,
                  minScale: 0.5,
                  maxScale: 4,
                  child: CachedNetworkImage(
                    imageUrl: widget.message.mediaUrl,
                    fit: BoxFit.contain,
                    width: double.infinity,
                    height: double.infinity,
                    placeholder: (context, url) => const CircularProgressIndicator(),
                  ),
                ),
        ),
      ),
    );
  }
}

class _FileMessageWidget extends StatefulWidget {
  final ChatMessage message;
  final bool isMine;

  const _FileMessageWidget({required this.message, required this.isMine});

  @override
  State<_FileMessageWidget> createState() => _FileMessageWidgetState();
}

class _FileMessageWidgetState extends State<_FileMessageWidget> {
  bool _isDownloading = false;

  Future<void> _downloadAndOpenFile() async {
    setState(() => _isDownloading = true);
    try {
      final dir = await getTemporaryDirectory();
      String fileName = widget.message.mediaUrl.split('?').first.split('/').last;
      if (!fileName.contains('.')) fileName = 'document_${DateTime.now().millisecondsSinceEpoch}.pdf';
      
      final dynamic file = File('${dir.path}/$fileName');
      if (!await (file as dynamic).exists()) {
        final response = await http.get(Uri.parse(widget.message.mediaUrl));
        await (file as dynamic).writeAsBytes(response.bodyBytes);
      }

      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('لا يوجد تطبيق لفتح هذا الملف: ${result.message}')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فشل تحميل الملف، تحقق من الإنترنت')));
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isMine ? Colors.white : Colors.black87;
    return GestureDetector(
      onTap: _isDownloading ? null : _downloadAndOpenFile,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: widget.isMine ? Colors.white.withOpacity(0.2) : Colors.black.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: widget.isMine ? Colors.white24 : Colors.white, shape: BoxShape.circle),
              child: _isDownloading 
                  ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blueAccent))
                  : Icon(Icons.insert_drive_file, color: widget.isMine ? Colors.white : Colors.blueAccent, size: 24),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.message.text, style: TextStyle(color: color, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text('اضغط لفتح الملف', style: TextStyle(color: color.withOpacity(0.7), fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// تم التعديل: برمجة مشغل الصوت الحقيقي والمتفاعل بالكامل
class _AudioMessageWidget extends StatefulWidget {
  final ChatMessage message;
  final bool isMine;

  const _AudioMessageWidget({required this.message, required this.isMine});

  @override
  State<_AudioMessageWidget> createState() => _AudioMessageWidgetState();
}

class _AudioMessageWidgetState extends State<_AudioMessageWidget> {
  final AudioPlaybackService _playbackService = AudioPlaybackService.instance;

  @override
  void initState() {
    super.initState();
    _playbackService.addListener(_handlePlaybackStateChanged);
  }

  @override
  void dispose() {
    _playbackService.removeListener(_handlePlaybackStateChanged);
    super.dispose();
  }

  void _handlePlaybackStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _togglePlay() async {
    if (_playbackService.currentUrl == widget.message.mediaUrl && _playbackService.isPlaying) {
      await _playbackService.pause();
    } else {
      await _playbackService.togglePlay(widget.message.mediaUrl);
    }
  }

  Future<void> _setPlaybackRate(double rate) async {
    await _playbackService.setPlaybackRate(rate);
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isMine ? Colors.white : Colors.black87;
    final isPlaying = _playbackService.isPlaying &&
        _playbackService.currentUrl == widget.message.mediaUrl;
    final duration = _playbackService.duration;
    final position = _playbackService.position;
    final playbackRate = _playbackService.playbackRate;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _togglePlay,
          child: CircleAvatar(
            backgroundColor: widget.isMine ? Colors.white24 : Colors.blueAccent.withOpacity(0.1),
            child: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: widget.isMine ? Colors.white : Colors.blueAccent),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SliderTheme(
                data: SliderThemeData(
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  trackHeight: 3,
                  activeTrackColor: color,
                  inactiveTrackColor: color.withOpacity(0.3),
                  thumbColor: color,
                  overlayShape: SliderComponentShape.noOverlay,
                ),
                child: Slider(
                  min: 0,
                  max: duration.inSeconds.toDouble() > 0 ? duration.inSeconds.toDouble() : 1,
                  value: position.inSeconds.toDouble().clamp(0, duration.inSeconds.toDouble() > 0 ? duration.inSeconds.toDouble() : 1),
                  onChanged: (value) async {
                    final seekPosition = Duration(seconds: value.toInt());
                    await _playbackService.seek(seekPosition);
                  },
                ),
              ),
              Row(
                children: [
                  Text(
                    '${position.inMinutes}:${(position.inSeconds % 60).toString().padLeft(2, '0')}',
                    style: TextStyle(color: color, fontSize: 12),
                  ),
                  const Spacer(),
                  PopupMenuButton<double>(
                    tooltip: 'سرعة التشغيل',
                    icon: Icon(
                      Icons.speed_rounded,
                      size: 16,
                      color: color,
                    ),
                    onSelected: (rate) async {
                      await _setPlaybackRate(rate);
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem<double>(value: 1.0, child: Text('1x')),
                      PopupMenuItem<double>(value: 1.5, child: Text('1.5x')),
                      PopupMenuItem<double>(value: 2.0, child: Text('2x')),
                    ],
                    initialValue: playbackRate,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}