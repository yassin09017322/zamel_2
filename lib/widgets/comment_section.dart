import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../models/comment.dart';
import '../screens/profile_screen.dart';
import '../services/audio_service.dart';

class CommentSection extends StatefulWidget {
  final List<Comment> comments;
  final void Function(Comment comment)? onReply;

  const CommentSection({super.key, required this.comments, this.onReply});

  @override
  State<CommentSection> createState() => _CommentSectionState();
}

class _CommentSectionState extends State<CommentSection> {
  final AudioCommentService _audioService = AudioCommentService();
  String? _activeAudioUrl;
  bool _isAudioPlaying = false;
  Duration _audioPosition = Duration.zero;
  late final StreamSubscription<Duration> _positionSub;
  late final StreamSubscription<PlayerState> _stateSub;

  @override
  void initState() {
    super.initState();
    _positionSub = _audioService.positionStream.listen((position) {
      if (!mounted) return;
      setState(() => _audioPosition = position);
    });
    _stateSub = _audioService.playerStateStream.listen((state) {
      if (!mounted) return;
      if (state == PlayerState.completed || state == PlayerState.stopped || state == PlayerState.paused) {
        setState(() {
          _isAudioPlaying = false;
          if (state == PlayerState.completed) {
            _audioPosition = Duration.zero;
          }
        });
      } else if (state == PlayerState.playing) {
        setState(() => _isAudioPlaying = true);
      }
    });
  }

  @override
  void dispose() {
    _positionSub.cancel();
    _stateSub.cancel();
    _audioService.dispose();
    super.dispose();
  }

  Future<void> _toggleAudioPlayback(Comment comment) async {
    if (comment.audioUrl.isEmpty) return;

    if (_activeAudioUrl == comment.audioUrl && _isAudioPlaying) {
      await _audioService.pause();
      if (mounted) setState(() => _isAudioPlaying = false);
      return;
    }

    await _audioService.stop();
    await _audioService.play(comment.audioUrl);
    if (mounted) {
      setState(() {
        _activeAudioUrl = comment.audioUrl;
        _audioPosition = Duration.zero;
        _isAudioPlaying = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: widget.comments.map((comment) {
        final isAudio = comment.type == 'audio' || comment.audioUrl.isNotEmpty || comment.text.startsWith('[AUDIO]');
        final active = _activeAudioUrl == comment.audioUrl;
        final duration = Duration(seconds: comment.duration > 0 ? comment.duration : 30);

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(userId: comment.userId))),
                      child: Text(comment.username, style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    const Spacer(),
                    Text(_formatTime(comment.timestamp), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
                if (comment.replyToUsername.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text('رد على ${comment.replyToUsername}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                  ),
                ],
                const SizedBox(height: 10),
                if (isAudio)
                  InkWell(
                    onTap: () async {
                      try {
                        await _toggleAudioPlayback(comment);
                      } catch (_) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر تشغيل الصوت')));
                        }
                      }
                    },
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF5B6CFF).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                active && _isAudioPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                                color: const Color(0xFF5B6CFF),
                                size: 28,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  comment.text.isNotEmpty && !comment.text.startsWith('[AUDIO]') ? comment.text : 'تعليق صوتي',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F1A3A)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          LinearProgressIndicator(
                            value: active ? (_audioPosition.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0) : 0.0,
                            backgroundColor: Colors.white,
                            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF5B6CFF)),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            active ? '${_formatDuration(_audioPosition)} / ${_formatDuration(duration)}' : '0:00 / ${_formatDuration(duration)}',
                            style: const TextStyle(color: Color(0xFF5B6CFF), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Text(comment.text, style: const TextStyle(color: Colors.black87, height: 1.4)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    TextButton(
                      onPressed: () {
                        widget.onReply?.call(comment);
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF5B6CFF),
                      ),
                      child: const Text('رد'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _formatTime(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inHours < 1) return '${diff.inMinutes} د';
    if (diff.inDays < 1) return '${diff.inHours} س';
    return '${date.day}/${date.month}/${date.year}';
  }
}
