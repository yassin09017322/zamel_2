import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

class AudioPlaybackService {
  static final AudioPlaybackService instance = AudioPlaybackService._();

  final AudioPlayer _player = AudioPlayer();
  final List<VoidCallback> _listeners = <VoidCallback>[];

  String _currentUrl = '';
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  double _playbackRate = 1.0;

  factory AudioPlaybackService() => instance;

  AudioPlaybackService._() {
    _player.onPlayerStateChanged.listen((state) {
      _isPlaying = state == PlayerState.playing;
      _notifyListeners();
    });

    _player.onDurationChanged.listen((newDuration) {
      _duration = newDuration;
      _notifyListeners();
    });

    _player.onPositionChanged.listen((newPosition) {
      _position = newPosition;
      _notifyListeners();
    });

    _player.onPlayerComplete.listen((_) {
      _position = Duration.zero;
      _isPlaying = false;
      _notifyListeners();
    });
  }

  String get currentUrl => _currentUrl;
  bool get isPlaying => _isPlaying;
  Duration get duration => _duration;
  Duration get position => _position;
  double get playbackRate => _playbackRate;

  void addListener(VoidCallback listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners() {
    final callbacks = List<VoidCallback>.from(_listeners);
    for (final callback in callbacks) {
      callback();
    }
  }

  Future<void> togglePlay(String url) async {
    if (_currentUrl == url && _isPlaying) {
      await pause();
      return;
    }

    if (_currentUrl == url) {
      await resume();
      return;
    }

    _currentUrl = url;
    _position = Duration.zero;
    await _player.stop();
    await _player.play(UrlSource(url));
    await _player.setPlaybackRate(_playbackRate);
  }

  Future<void> pause() async {
    await _player.pause();
  }

  Future<void> resume() async {
    if (_currentUrl.isNotEmpty) {
      await _player.resume();
      await _player.setPlaybackRate(_playbackRate);
    }
  }

  Future<void> seek(Duration position) async {
    _position = position;
    await _player.seek(position);
    _notifyListeners();
  }

  Future<void> setPlaybackRate(double rate) async {
    _playbackRate = rate;
    await _player.setPlaybackRate(rate);
    _notifyListeners();
  }

  Future<void> stop() async {
    await _player.stop();
    _isPlaying = false;
    _notifyListeners();
  }
}
