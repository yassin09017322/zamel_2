import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

import '../services/call_service.dart';

class CallScreen extends StatefulWidget {
  final CallSession session;

  const CallScreen({super.key, required this.session});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  bool _audioEnabled = true;
  bool _videoEnabled = true;
  bool _speakerEnabled = false;
  bool _isMinimized = false;
  bool _showQuickNote = false;

  // متغير جديد للتحكم في نوع المكالمة (للتبديل بين الصوت والفيديو)
  late bool _isVideoCall;

  String _connectionStatus = 'جارٍ الاتصال...';
  Duration _callDuration = Duration.zero;
  DateTime? _connectedAt;
  bool _isConnected = false;
  bool _isSwitchingMedia = false;
  late RTCVideoRenderer _localRenderer;
  late RTCVideoRenderer _remoteRenderer;
  Timer? _durationTimer;
  Timer? _offlineRingTimer; // مؤقت للرنين المتقطع
  StreamSubscription<MediaStream?>? _remoteStreamSubscription;
  StreamSubscription<String>? _statusSubscription;
  StreamSubscription<String>? _mediaTypeSubscription;

  bool _isRinging = false;

  @override
  void initState() {
    super.initState();
    _localRenderer = RTCVideoRenderer();
    _remoteRenderer = RTCVideoRenderer();

    // تحديد نوع المكالمة عند البدء
    _isVideoCall = widget.session.type == 'video';

    _initializeRenderers();

    // Ringback belongs to the caller; incoming ringing is owned by CallKit.
    if (widget.session.isCaller) {
      _playRingtone();
    }

    _remoteStreamSubscription = widget.session.remoteStreamStream.listen((
      stream,
    ) {
      if (!mounted) return;
      _remoteRenderer.srcObject = stream;
      if (stream != null) {
        _stopRingtone();
        setState(() {
          _connectionStatus = 'متصل';
        });
      }
    });

    _statusSubscription = widget.session.statusStream.listen((status) {
      if (!mounted) return;
      final normalized = status.toLowerCase();

      if (normalized != 'connected') {
        _isConnected = false;
        _stopCallTimer();
      }

      if (normalized == 'connected') {
        _stopRingtone();

        if (!_isConnected) {
          _isConnected = true;
          _connectedAt = DateTime.now();
          _callDuration = Duration.zero;
          _startCallTimer();
        }

        setState(() {
          _connectionStatus = 'متصل';
        });
      } else if (normalized == 'accepted') {
        _stopRingtone();
        setState(() {
          _connectionStatus = 'جارٍ تهيئة الاتصال...';
        });
      } else if (normalized == 'calling' || normalized == 'ringing') {
        _playRingtone();
        setState(() {
          _connectionStatus = 'جارٍ الاتصال...';
        });
      } else if (normalized == 'ended' ||
          normalized == 'rejected' ||
          normalized == 'canceled' ||
          normalized == 'missed') {
        _stopRingtone();
        setState(() {
          _connectionStatus = 'تم إنهاء المكالمة';
        });
        Navigator.of(context).maybePop();
      }
    });
    _mediaTypeSubscription = widget.session.mediaTypeStream.listen((type) {
      if (!mounted || (type != 'audio' && type != 'video')) return;
      setState(() {
        _isVideoCall = type == 'video';
        _videoEnabled = _isVideoCall;
      });
    });

    // تم إزالة استدعاء _startCallTimer() من هنا حتى لا يبدأ العد قبل الرد
  }

  void _playRingtone() {
    if (!_isRinging) {
      _isRinging = true;

      // التعديل 2: محاكاة صوت "طوط... طوط..." للمتصل
      if (widget.session.isReceiverOnline) {
        _playOfflineBeep(); // نغمة أولى
        _offlineRingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
          if (_isRinging) {
            _playOfflineBeep();
          } else {
            timer.cancel();
          }
        });
      } else {
        // الطرف الآخر غير متصل: رنين متقطع أبطأ
        _playOfflineBeep();
        _offlineRingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
          if (_isRinging) {
            _playOfflineBeep();
          } else {
            timer.cancel();
          }
        });
      }
    }
  }

  void _playOfflineBeep() {
    FlutterRingtonePlayer().play(
      android: AndroidSounds.notification,
      ios: IosSounds.glass,
      volume: 0.3,
    );
  }

  void _stopRingtone() {
    if (_isRinging) {
      _isRinging = false;
      _offlineRingTimer?.cancel();
      FlutterRingtonePlayer().stop();
    }
  }

  void _startCallTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        final connectedAt = _connectedAt;
        _callDuration = connectedAt == null
            ? Duration.zero
            : DateTime.now().difference(connectedAt);
      });
    });
  }

  void _stopCallTimer() {
    _durationTimer?.cancel();
    _durationTimer = null;
    _connectedAt = null;
    _callDuration = Duration.zero;
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _initializeRenderers() async {
    try {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();
      if (!mounted) return;
      _localRenderer.srcObject = widget.session.localStream;
      setState(() {});
    } catch (_) {
      if (mounted) {
        setState(() {
          _connectionStatus = 'تعذر تهيئة الشاشة';
        });
      }
    }
  }

  Future<void> _toggleAudio() async {
    await widget.session.toggleMute();
    if (mounted) {
      setState(() {
        _audioEnabled = !_audioEnabled;
      });
    }
  }

  Future<void> _toggleVideo() async {
    await widget.session.toggleCamera();
    if (mounted) {
      setState(() {
        _videoEnabled = !_videoEnabled;
      });
    }
  }

  // التعديل 3: دالة التبديل الجذري بين المكالمة الصوتية والفيديو
  Future<void> _switchCallType() async {
    if (_isSwitchingMedia) return;
    final enableVideo = !_isVideoCall;
    setState(() => _isSwitchingMedia = true);
    try {
      await widget.session.switchMediaType(enableVideo: enableVideo);
      if (!mounted) return;
      _localRenderer.srcObject = widget.session.localStream;
      setState(() {
        _isVideoCall = enableVideo;
        _videoEnabled = enableVideo;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تبديل نوع المكالمة: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSwitchingMedia = false);
    }
  }

  Future<void> _toggleSpeaker() async {
    try {
      await Helper.setSpeakerphoneOn(!_speakerEnabled);
    } catch (_) {}
    if (mounted) {
      setState(() {
        _speakerEnabled = !_speakerEnabled;
      });
    }
  }

  void _toggleMinimize() {
    setState(() {
      _isMinimized = !_isMinimized;
    });
  }

  void _toggleQuickNote() {
    setState(() {
      _showQuickNote = !_showQuickNote;
    });
  }

  @override
  void dispose() {
    _stopRingtone();
    _stopCallTimer();
    _remoteStreamSubscription?.cancel();
    _statusSubscription?.cancel();
    _mediaTypeSubscription?.cancel();
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    unawaited(widget.session.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool hasRemote = _remoteRenderer.srcObject != null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: _isVideoCall
                  ? hasRemote
                        ? RTCVideoView(
                            _remoteRenderer,
                            objectFit: RTCVideoViewObjectFit
                                .RTCVideoViewObjectFitCover,
                          )
                        : Container(
                            color: Colors.black,
                            alignment: Alignment.center,
                            child: const Text(
                              'جارٍ الاتصال...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                              ),
                            ),
                          )
                  : Container(
                      color: Colors.black,
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.call, color: Colors.white, size: 88),
                          const SizedBox(height: 12),
                          Text(
                            'مكالمة صوتية مع ${widget.session.receiverName}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
            ),
            if (_isVideoCall)
              Positioned(
                top: 16,
                left: 16,
                child: Container(
                  width: 140,
                  height: 220,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: _localRenderer.srcObject == null || !_videoEnabled
                      ? const Center(
                          child: Icon(
                            Icons.videocam_off,
                            color: Colors.white70,
                            size: 40,
                          ),
                        )
                      : RTCVideoView(
                          _localRenderer,
                          mirror: true,
                          objectFit:
                              RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        ),
                ),
              ),
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      widget.session.receiverName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isVideoCall ? 'مكالمة فيديو' : 'مكالمة صوتية',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _connectionStatus,
                      style: const TextStyle(
                        color: Colors.lightBlueAccent,
                        fontSize: 13,
                      ),
                    ),
                    if (_isConnected) ...[
                      const SizedBox(height: 4),
                      Text(
                        _formatDuration(_callDuration),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (!_isMinimized)
              Positioned(
                top: 16,
                left: 16,
                child: IconButton(
                  onPressed: _toggleMinimize,
                  icon: const Icon(Icons.minimize, color: Colors.white),
                  style: IconButton.styleFrom(backgroundColor: Colors.black54),
                ),
              ),
            if (_showQuickNote)
              Positioned(
                bottom: 140,
                left: 24,
                right: 24,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.chat_bubble_outline,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'ملاحظة سريعة: يمكنكم متابعة المكالمة دون فقدان الاتصال.',
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Positioned(
              bottom: 34,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _MuteCallButton(
                    isEnabled: _audioEnabled,
                    onPressed: _toggleAudio,
                  ),
                  _CallActionButton(
                    icon: _speakerEnabled ? Icons.volume_up : Icons.volume_off,
                    color: _speakerEnabled ? Colors.blue : Colors.white,
                    onPressed: _toggleSpeaker,
                  ),
                  // الزر المسؤول عن التبديل بين الكاميرا والصوت (الترقية / التخفيض)
                  _CallActionButton(
                    icon: _isVideoCall ? Icons.videocam : Icons.videocam_off,
                    color: _isVideoCall ? Colors.blue : Colors.grey.shade700,
                    onPressed: _switchCallType,
                  ),
                  _CallActionButton(
                    icon: Icons.call_end,
                    color: Colors.red,
                    onPressed: () async {
                      await CallService.instance.endCall(widget.session.callId);
                      if (mounted) Navigator.of(context).pop();
                    },
                  ),
                  if (_isVideoCall)
                    _CallActionButton(
                      icon: Icons.cameraswitch,
                      color: Colors.white,
                      onPressed: () async {
                        await widget.session.switchCamera();
                        setState(() {});
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _CallActionButton({
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return RawMaterialButton(
      onPressed: onPressed,
      shape: const CircleBorder(),
      fillColor: color,
      constraints: const BoxConstraints.tightFor(width: 60, height: 60),
      child: Icon(icon, color: Colors.white),
    );
  }
}

class _MuteCallButton extends StatelessWidget {
  final bool isEnabled;
  final VoidCallback onPressed;

  const _MuteCallButton({required this.isEnabled, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final label = isEnabled ? 'كتم الميكروفون' : 'تشغيل الميكروفون';
    final backgroundColor = isEnabled ? Colors.blue : Colors.red.shade700;

    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: backgroundColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: backgroundColor.withOpacity(0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: Icon(
                  isEnabled ? Icons.mic : Icons.mic_off,
                  key: ValueKey(isEnabled),
                  color: Colors.white,
                  size: 30,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
