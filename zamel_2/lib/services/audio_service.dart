import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart' as audioplayers;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import 'media_service.dart';
import 'package:zamel_appp/src/platform_file.dart' as io;
import 'web_audio_stub.dart' if (dart.library.html) 'web_audio.dart';

class AudioCommentService {
  final AudioRecorder _mobileRecorder = AudioRecorder();
  final audioplayers.AudioPlayer _player = audioplayers.AudioPlayer();
  final MediaService _mediaService = MediaService();

  bool _isRecording = false;
  String? _recordingPath;
  Timer? _timer;
  int _durationSeconds = 0;
  Uint8List? _webRecordedBytes;

  bool get isRecording => _isRecording;
  int get durationSeconds => _durationSeconds;
  String? get recordingPath => _recordingPath;

  Stream<Duration> get positionStream => _player.onPositionChanged;
  Stream<audioplayers.PlayerState> get playerStateStream => _player.onPlayerStateChanged;

  Future<bool> checkPermission() async {
    // التعديل هنا: حماية التطبيق من التجميد في حالة الويب
    if (kIsWeb) {
      return true; // المتصفح سيتولى طلب الصلاحية تلقائياً
    }
    
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<String?> startRecording() async {
    final hasPermission = await checkPermission();
    if (!hasPermission) return null;

    if (kIsWeb) {
      _webRecordedBytes = null;
      _recordingPath = 'comment.webm';
      _durationSeconds = 0;
      _isRecording = true;
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _durationSeconds++;
      });
      await WebAudioRecorder.start();
      return _recordingPath;
    }

    final tempDir = await getTemporaryDirectory();
    final filePath = '${tempDir.path}/comment_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _mobileRecorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: filePath,
    );
    _recordingPath = filePath;
    _durationSeconds = 0;
    _isRecording = true;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _durationSeconds++;
    });
    return filePath;
  }

  Future<String?> stopRecording() async {
    if (!_isRecording) return null;
    _timer?.cancel();
    _timer = null;

    if (kIsWeb) {
      _webRecordedBytes = await WebAudioRecorder.stop();
      _isRecording = false;
      return _recordingPath;
    }

    final path = await _mobileRecorder.stop();
    _isRecording = false;
    if (path == null || path.isEmpty) return null;
    _recordingPath = path;
    return path;
  }

  Future<Map<String, dynamic>?> uploadAudioFile(String filePath) async {
    if (kIsWeb) {
      final bytes = _webRecordedBytes;
      if (bytes == null || bytes.isEmpty) return null;

      final uploadedUrl = await _mediaService.uploadBytes(
        bytes,
        filePath.endsWith('.webm') ? 'comment.webm' : 'comment.wav',
        isVideo: false,
      );
      return {'url': uploadedUrl};
    }

    final dynamic file = io.File(filePath);
    if (!await (file as dynamic).exists()) return null;

    final uploadedUrl = await _mediaService.uploadFile(
      file,
      isVideo: false,
    );

    return {'url': uploadedUrl};
  }

  Future<void> play(String url) async {
    if (url.isEmpty) return;

    if (url.startsWith('http://') || url.startsWith('https://')) {
      await _player.play(audioplayers.UrlSource(url));
      return;
    }

    if (kIsWeb) return;

    await _player.play(audioplayers.DeviceFileSource(url));
  }

  Future<void> pause() async {
    await _player.pause();
  }

  Future<void> stop() async {
    await _player.stop();
  }

  Future<void> dispose() async {
    _timer?.cancel();
    await _player.stop();
    await _player.dispose();
    await _mobileRecorder.dispose();
  }
}
