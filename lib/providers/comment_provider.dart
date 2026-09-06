import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/comment.dart';
import '../services/audio_service.dart';
import '../services/comment_service.dart';
import '../services/media_service.dart';

class CommentProvider extends ChangeNotifier {
  final CommentService _service;
  final AudioCommentService audioService;
  final String postId;

  final List<Comment> _comments = <Comment>[];
  final Map<String, List<Comment>> _replies = <String, List<Comment>>{};
  final Map<String, DocumentSnapshot<Map<String, dynamic>>?> _cursors =
      <String, DocumentSnapshot<Map<String, dynamic>>?>{};
  final Map<String, bool> _hasMore = <String, bool>{};
  final Set<String> _loadingReplies = <String>{};
  final Set<String> _expandedReplies = <String>{};

  StreamSubscription<List<Comment>>? _liveSubscription;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _isSending = false;
  bool _isRecording = false;
  bool _isUploading = false;
  double _uploadProgress = 0;
  int _recordingSeconds = 0;
  Timer? _recordingTimer;
  String? _error;
  String? _replyToCommentId;
  String? _replyToUserId;
  String? _replyToUsername;
  String? _editingCommentId;

  CommentProvider({
    required this.postId,
    CommentService? service,
    AudioCommentService? audioService,
  }) : _service = service ?? CommentService(),
       audioService = audioService ?? AudioCommentService() {
    _loadInitialPage();
    _listenToFirstPage();
  }

  List<Comment> get comments => List.unmodifiable(_comments);
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get isSending => _isSending;
  bool get isRecording => _isRecording;
  bool get isUploading => _isUploading;
  double get uploadProgress => _uploadProgress;
  int get recordingSeconds => _recordingSeconds;
  String? get error => _error;
  String? get replyToCommentId => _replyToCommentId;
  String? get replyToUsername => _replyToUsername;
  String? get editingCommentId => _editingCommentId;
  bool get hasMore => _hasMore[''] ?? false;

  List<Comment> repliesFor(String commentId) =>
      List.unmodifiable(_replies[commentId] ?? const <Comment>[]);

  bool isRepliesExpanded(String commentId) =>
      _expandedReplies.contains(commentId);

  bool hasMoreReplies(String commentId) => _hasMore[commentId] ?? false;

  void _listenToFirstPage() {
    _liveSubscription = _service
        .commentsStream(postId)
        .listen(
          (items) {
            final byId = <String, Comment>{
              for (final item in _comments) item.id: item,
            };
            for (final item in items) byId[item.id] = item;
            _comments
              ..clear()
              ..addAll(byId.values);
            _comments.sort((a, b) => b.timestamp.compareTo(a.timestamp));
            _hydrateLikeState(items);
            _isLoading = false;
            _error = null;
            notifyListeners();
          },
          onError: (Object error) {
            _isLoading = false;
            _error = error.toString();
            notifyListeners();
          },
        );
  }

  Future<void> _hydrateLikeState(Iterable<Comment> items) async {
    for (final item in items) {
      try {
        final liked = await _service.isLiked(
          postId: postId,
          commentId: item.id,
        );
        final index = _comments.indexWhere((comment) => comment.id == item.id);
        if (index >= 0 && _comments[index].isLikedByCurrentUser != liked) {
          _comments[index] = _comments[index].copyWith(
            isLikedByCurrentUser: liked,
          );
        }
      } catch (error) {
        _error = error.toString();
      }
    }
    notifyListeners();
  }

  Future<void> _loadInitialPage() async {
    try {
      final page = await _service.fetchPage(postId);
      _comments
        ..clear()
        ..addAll(page.comments);
      _cursors[''] = page.cursor;
      _hasMore[''] = page.hasMore;
      _isLoading = false;
      notifyListeners();
    } catch (error) {
      _isLoading = false;
      _error = error.toString();
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (_isLoadingMore || !hasMore) return;
    _isLoadingMore = true;
    _error = null;
    notifyListeners();
    try {
      final page = await _service.fetchPage(postId, cursor: _cursors['']);
      final ids = _comments.map((comment) => comment.id).toSet();
      _comments.addAll(page.comments.where((comment) => ids.add(comment.id)));
      _comments.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      _cursors[''] = page.cursor;
      _hasMore[''] = page.hasMore;
    } catch (error) {
      _error = error.toString();
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  Future<void> loadReplies(String commentId) async {
    _expandedReplies.add(commentId);
    if (_loadingReplies.contains(commentId)) return;
    if (_replies.containsKey(commentId) && !hasMoreReplies(commentId)) {
      notifyListeners();
      return;
    }
    _loadingReplies.add(commentId);
    _error = null;
    notifyListeners();
    try {
      final page = await _service.fetchPage(
        postId,
        parentCommentId: commentId,
        cursor: _cursors[commentId],
      );
      final current = _replies.putIfAbsent(commentId, () => <Comment>[]);
      final ids = current.map((comment) => comment.id).toSet();
      current.addAll(page.comments.where((comment) => ids.add(comment.id)));
      current.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      _cursors[commentId] = page.cursor;
      _hasMore[commentId] = page.hasMore;
      await _hydrateLikeState(page.comments);
    } catch (error) {
      _error = error.toString();
    } finally {
      _loadingReplies.remove(commentId);
      notifyListeners();
    }
  }

  Future<void> loadMoreReplies(String commentId) => loadReplies(commentId);

  void collapseReplies(String commentId) {
    _expandedReplies.remove(commentId);
    notifyListeners();
  }

  void startReply(Comment comment) {
    _replyToCommentId = comment.id;
    _replyToUserId = comment.userId;
    _replyToUsername = comment.username;
    notifyListeners();
  }

  void cancelReply() {
    _replyToCommentId = null;
    _replyToUserId = null;
    _replyToUsername = null;
    notifyListeners();
  }

  void startEditing(Comment comment) {
    _editingCommentId = comment.id;
    notifyListeners();
  }

  void cancelEditing() {
    _editingCommentId = null;
    notifyListeners();
  }

  Future<void> sendText({
    required String text,
    required String userId,
    required String username,
    String? userPhotoUrl,
  }) async {
    final normalizedText = text.trim();
    if (_isSending || normalizedText.isEmpty) return;
    _isSending = true;
    _error = null;
    notifyListeners();
    try {
      if (_editingCommentId != null) {
        final editingId = _editingCommentId!;
        await _service.updateComment(
          postId: postId,
          commentId: editingId,
          text: normalizedText,
        );
        _replaceComment(
          editingId,
          (comment) => comment.copyWith(text: normalizedText, isEdited: true),
        );
        _editingCommentId = null;
      } else {
        await _service.addComment(
          postId: postId,
          userId: userId,
          username: username,
          userPhotoUrl: userPhotoUrl,
          text: normalizedText,
          replyToCommentId: _replyToCommentId,
          replyToUserId: _replyToUserId,
          replyToUsername: _replyToUsername,
          clientRequestId: '${postId}_${DateTime.now().microsecondsSinceEpoch}',
        );
        cancelReply();
      }
    } catch (error) {
      _error = error.toString();
      rethrow;
    } finally {
      _isSending = false;
      notifyListeners();
    }
  }

  Future<void> sendAudio({
    required String userId,
    required String username,
    String? userPhotoUrl,
  }) async {
    if (_isSending || !_isRecording) return;
    _recordingTimer?.cancel();
    _isRecording = false;
    notifyListeners();
    final audioPath = await audioService.stopRecording();
    if (audioPath == null || audioPath.isEmpty) {
      throw Exception('فشل تسجيل الصوت');
    }
    _isSending = true;
    _isUploading = true;
    _uploadProgress = 0;
    notifyListeners();
    try {
      final result = await audioService.uploadAudioFile(
        audioPath,
        onProgress: (progress) {
          _uploadProgress = progress.percentComplete;
          notifyListeners();
        },
      );
      final url = result?['url'] as String?;
      if (url == null || url.trim().isEmpty) throw Exception('فشل رفع الصوت');
      await _service.addComment(
        postId: postId,
        userId: userId,
        username: username,
        userPhotoUrl: userPhotoUrl,
        text: '[AUDIO]',
        audioUrl: url,
        type: 'audio',
        duration: audioService.durationSeconds,
        replyToCommentId: _replyToCommentId,
        replyToUserId: _replyToUserId,
        replyToUsername: _replyToUsername,
        clientRequestId: '${postId}_${DateTime.now().microsecondsSinceEpoch}',
      );
      cancelReply();
    } catch (error) {
      _error = error.toString();
      rethrow;
    } finally {
      _isUploading = false;
      _uploadProgress = 0;
      _isSending = false;
      notifyListeners();
    }
  }

  Future<void> startRecording() async {
    if (_isRecording || _isSending) return;
    if (!await audioService.checkPermission()) {
      throw Exception('صلاحية الميكروفون مطلوبة');
    }
    final path = await audioService.startRecording();
    if (path == null || path.isEmpty) throw Exception('تعذر بدء التسجيل');
    _isRecording = true;
    _recordingSeconds = 0;
    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _recordingSeconds++;
      notifyListeners();
    });
    notifyListeners();
  }

  Future<void> cancelRecording() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    if (_isRecording) await audioService.stopRecording();
    _isRecording = false;
    _recordingSeconds = 0;
    notifyListeners();
  }

  Future<void> delete(Comment comment) async {
    await _service.deleteComment(postId: postId, commentId: comment.id);
    final index = _comments.indexWhere((item) => item.id == comment.id);
    if (index >= 0) {
      if (comment.repliesCount > 0) {
        _comments[index] = comment.copyWith(isDeleted: true, text: '');
      } else {
        _comments.removeAt(index);
      }
    } else {
      for (final entry in _replies.entries) {
        final replyIndex = entry.value.indexWhere(
          (item) => item.id == comment.id,
        );
        if (replyIndex >= 0) {
          entry.value.removeAt(replyIndex);
          break;
        }
      }
    }
    notifyListeners();
  }

  void _replaceComment(String commentId, Comment Function(Comment) update) {
    final rootIndex = _comments.indexWhere((item) => item.id == commentId);
    if (rootIndex >= 0) {
      _comments[rootIndex] = update(_comments[rootIndex]);
      return;
    }
    for (final items in _replies.values) {
      final index = items.indexWhere((item) => item.id == commentId);
      if (index >= 0) {
        items[index] = update(items[index]);
        return;
      }
    }
  }

  Future<void> toggleLike(Comment comment) async {
    await _service.toggleLike(postId: postId, commentId: comment.id);
    final index = _comments.indexWhere((item) => item.id == comment.id);
    final target = index >= 0
        ? _comments
        : (_replies.values.firstWhere(
            (items) => items.any((item) => item.id == comment.id),
            orElse: () => <Comment>[],
          ));
    final targetIndex = target.indexWhere((item) => item.id == comment.id);
    if (targetIndex >= 0) {
      target[targetIndex] = target[targetIndex].copyWith(
        likesCount: comment.isLikedByCurrentUser
            ? (comment.likesCount > 0 ? comment.likesCount - 1 : 0)
            : comment.likesCount + 1,
        isLikedByCurrentUser: !comment.isLikedByCurrentUser,
      );
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _liveSubscription?.cancel();
    audioService.dispose();
    super.dispose();
  }
}
