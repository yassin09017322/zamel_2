import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/chat_message.dart';
import 'chat_service.dart';
import 'callkit_service.dart'; // 🔥 تم الإضافة: لربط المحرك بشاشة الاتصال الأصلية
import 'notification_service.dart';

class CallSession {
  final String callId;
  final String chatId;
  final String callerId;
  final String callerName;
  final String receiverId;
  final String receiverName;
  final String type;
  String currentMediaType;
  final bool isCaller;
  bool isReceiverOnline;
  final RTCPeerConnection peerConnection;
  final MediaStream localStream;
  MediaStream? remoteStream;
  String? callMessageId;
  bool callMessageCreated = false;
  bool isConnected = false;
  bool isEnding = false;
  bool _isDisposed = false;
  bool _hasRemoteDescription = false;
  final List<RTCIceCandidate> _pendingRemoteCandidates = <RTCIceCandidate>[];
  DateTime? startedAt;
  DateTime? endedAt;
  final StreamController<MediaStream?> _remoteStreamController =
      StreamController.broadcast();
  final StreamController<String> _statusController =
      StreamController.broadcast();
  final StreamController<String> _mediaTypeController =
      StreamController.broadcast();
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _callSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _candidateSubscription;
  Timer? _autoEndTimer;
  String currentFacingMode = 'user';
  bool _mediaSwitchInProgress = false;
  String? _lastRenegotiationId;
  String? _lastHandledRenegotiationId;
  MediaStreamTrack? _videoTrack;

  CallSession({
    required this.callId,
    required this.chatId,
    required this.callerId,
    required this.callerName,
    required this.receiverId,
    required this.receiverName,
    required this.type,
    required this.isCaller,
    this.isReceiverOnline = false,
    required this.peerConnection,
    required this.localStream,
  }) : currentMediaType = type;

  Stream<MediaStream?> get remoteStreamStream => _remoteStreamController.stream;
  Stream<String> get statusStream => _statusController.stream;
  Stream<String> get mediaTypeStream => _mediaTypeController.stream;

  void _updateMediaType(String mediaType) {
    if (currentMediaType == mediaType) return;
    currentMediaType = mediaType;
    if (!_mediaTypeController.isClosed) {
      _mediaTypeController.add(mediaType);
    }
  }

  void _updateRemoteStream(MediaStream? stream) {
    remoteStream = stream;
    _remoteStreamController.add(stream);
  }

  void _updateStatus(String status) {
    if (status == 'connected' && startedAt == null) {
      startedAt = DateTime.now();
    }
    if (status == 'ended' ||
        status == 'rejected' ||
        status == 'canceled' ||
        status == 'missed' ||
        status == 'failed') {
      endedAt ??= DateTime.now();
    }
    _statusController.add(status);
  }

  int getDurationSeconds() {
    if (startedAt == null) return 0;
    final end = endedAt ?? DateTime.now();
    return end.difference(startedAt!).inSeconds;
  }

  Future<void> scheduleAutoEnd(String callDocumentPath) async {
    _autoEndTimer?.cancel();
    _autoEndTimer = Timer(const Duration(seconds: 120), () async {
      final docRef = FirebaseFirestore.instance.doc(callDocumentPath);
      final snapshot = await docRef.get();
      final data = snapshot.data();
      final status = data == null ? null : data['status'] as String?;
      if (status == 'calling' || status == 'ringing' || status == 'accepted') {
        await docRef.update({'status': 'missed'});
      }
    });
  }

  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    await peerConnection.setRemoteDescription(description);
    _hasRemoteDescription = true;
    for (final candidate in List<RTCIceCandidate>.from(
      _pendingRemoteCandidates,
    )) {
      await peerConnection.addCandidate(candidate);
    }
    _pendingRemoteCandidates.clear();
  }

  Future<void> addRemoteCandidate(RTCIceCandidate candidate) async {
    if (_hasRemoteDescription) {
      await peerConnection.addCandidate(candidate);
    } else {
      _pendingRemoteCandidates.add(candidate);
    }
  }

  void attachStreamListener() {
    try {
      peerConnection.onTrack = (RTCTrackEvent event) {
        final remote = event.streams.isNotEmpty ? event.streams.first : null;
        if (remote != null) {
          _updateRemoteStream(remote);
        }
      };
    } catch (_) {
      try {
        peerConnection.onAddStream = (MediaStream stream) {
          _updateRemoteStream(stream);
        };
      } catch (_) {}
    }
  }

  Future<void> toggleMute() async {
    final audioTracks = localStream.getAudioTracks();
    if (audioTracks.isEmpty) return;
    final track = audioTracks.first;
    track.enabled = !track.enabled;
  }

  Future<void> toggleCamera() async {
    final videoTracks = localStream.getVideoTracks();
    if (videoTracks.isEmpty) return;
    final track = videoTracks.first;
    track.enabled = !track.enabled;
  }

  Future<void> switchMediaType({required bool enableVideo}) async {
    if (_isDisposed || _mediaSwitchInProgress) return;
    _mediaSwitchInProgress = true;
    try {
      final senders = await peerConnection.getSenders();
      RTCRtpSender? videoSender;
      for (final sender in senders) {
        if (sender.track?.kind == 'video') {
          videoSender = sender;
          break;
        }
      }

      if (enableVideo) {
        await _ensureCameraPermission();
        final cameraStream = await navigator.mediaDevices.getUserMedia({
          'audio': false,
          'video': {'facingMode': currentFacingMode},
        });
        final newTrack = cameraStream.getVideoTracks().first;
        localStream.addTrack(newTrack);
        if (videoSender == null) {
          videoSender = await peerConnection.addTrack(newTrack, localStream);
        } else {
          await videoSender.replaceTrack(newTrack);
        }
        _videoTrack = newTrack;
      } else {
        final track = _videoTrack ?? localStream.getVideoTracks().firstOrNull;
        if (track != null) {
          if (videoSender != null) {
            await videoSender.replaceTrack(null);
          }
          localStream.removeTrack(track);
          track.stop();
          _videoTrack = null;
        }
      }

      final mediaType = enableVideo ? 'video' : 'audio';
      await _renegotiateMedia(mediaType);
      _updateMediaType(mediaType);
    } finally {
      _mediaSwitchInProgress = false;
    }
  }

  Future<void> _ensureCameraPermission() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      throw StateError('Camera permission is required for video calls.');
    }
  }

  Future<void> _renegotiateMedia(String mediaType) async {
    final renegotiationId =
        '${callId}_${DateTime.now().microsecondsSinceEpoch}';
    _lastRenegotiationId = renegotiationId;
    final offer = await peerConnection.createOffer();
    await peerConnection.setLocalDescription(offer);
    await FirebaseFirestore.instance.collection('calls').doc(callId).update({
      'type': mediaType,
      'renegotiationId': renegotiationId,
      'renegotiationBy': isCaller ? callerId : receiverId,
      'renegotiationOffer': {'type': offer.type, 'sdp': offer.sdp},
      'renegotiationAnswer': FieldValue.delete(),
    });
  }

  Future<void> switchCamera() async {
    if (_isDisposed || _mediaSwitchInProgress) return;
    _mediaSwitchInProgress = true;

    final videoTracks = localStream.getVideoTracks();
    try {
      if (videoTracks.isEmpty) return;

      final track = videoTracks.first;
      await Helper.switchCamera(track);
      currentFacingMode = currentFacingMode == 'user' ? 'environment' : 'user';
      _videoTrack = track;
    } finally {
      _mediaSwitchInProgress = false;
    }
  }

  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    _autoEndTimer?.cancel();
    _callSubscription?.cancel();
    _candidateSubscription?.cancel();
    if (!_remoteStreamController.isClosed) {
      _remoteStreamController.close();
    }
    if (!_statusController.isClosed) {
      _statusController.close();
    }
    if (!_mediaTypeController.isClosed) {
      _mediaTypeController.close();
    }
    remoteStream?.getTracks().forEach((track) => track.stop());
    endedAt ??= DateTime.now();
    await peerConnection.close();
    localStream.getTracks().forEach((track) => track.stop());
    if (CallService.instance.activeSession == this) {
      CallService.instance.activeSession = null;
    }
  }
}

class CallService {
  CallService._();
  static final CallService instance = CallService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Map<String, dynamic> _rtcConfiguration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
  };

  final StreamController<IncomingCall> _incomingCallController =
      StreamController<IncomingCall>.broadcast();
  Stream<IncomingCall> get incomingCallStream => _incomingCallController.stream;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _incomingCallSubscription;
  CallSession? activeSession;
  bool _isDisposed = false;

  Future<User> _requireCurrentUser(String suppliedUserId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('User must be authenticated.');
    final requestedId = suppliedUserId.trim();
    if (requestedId.isNotEmpty && requestedId != user.uid) {
      throw StateError('Authenticated user does not match call participant.');
    }
    return user;
  }

  Future<void> _writeCandidate(
    String callId,
    String collectionPath,
    RTCIceCandidate candidate,
  ) async {
    try {
      await _firestore
          .collection('calls')
          .doc(callId)
          .collection(collectionPath)
          .add(_candidateToMap(candidate));
    } catch (error) {
      debugPrint('Failed to write ICE candidate: $error');
    }
  }

  Future<void> _endSessionAfterFailure(CallSession session) async {
    if (session.isEnding) return;
    session.isEnding = true;
    try {
      await updateCallStatus(callId: session.callId, status: 'failed');
    } catch (error) {
      debugPrint('Failed to mark call as failed: $error');
    } finally {
      if (activeSession == session) activeSession = null;
      await session.dispose();
    }
  }

  Future<void> _ensurePermissions({required bool video}) async {
    final microphoneStatus = await Permission.microphone.request();
    if (!microphoneStatus.isGranted) {
      throw StateError('Microphone permission is required.');
    }
    if (video) {
      final cameraStatus = await Permission.camera.request();
      if (!cameraStatus.isGranted) {
        throw StateError('Camera permission is required for video calls.');
      }
    }
  }

  Future<MediaStream> _getUserMedia({required bool video}) async {
    await _ensurePermissions(video: video);
    final constraints = {
      'audio': true,
      'video': video ? {'facingMode': 'user'} : false,
    };
    return await navigator.mediaDevices.getUserMedia(constraints);
  }

  Future<RTCPeerConnection> _createPeerConnection() async {
    return await createPeerConnection(_rtcConfiguration, {
      'mandatory': {},
      'optional': [
        {'DtlsSrtpKeyAgreement': true},
      ],
    });
  }

  Map<String, dynamic> _candidateToMap(RTCIceCandidate candidate) {
    return {
      'candidate': candidate.candidate,
      'sdpMid': candidate.sdpMid,
      'sdpMLineIndex': candidate.sdpMLineIndex,
    };
  }

  Future<CallSession> _prepareSession({
    required String callId,
    required String chatId,
    required String callerId,
    required String callerName,
    required String receiverId,
    required String receiverName,
    required String type,
    required bool isCaller,
    required bool isReceiverOnline,
    required MediaStream localStream,
    required RTCPeerConnection peerConnection,
  }) async {
    final session = CallSession(
      callId: callId,
      chatId: chatId,
      callerId: callerId,
      callerName: callerName,
      receiverId: receiverId,
      receiverName: receiverName,
      type: type,
      isCaller: isCaller,
      isReceiverOnline: isReceiverOnline,
      peerConnection: peerConnection,
      localStream: localStream,
    );

    session.attachStreamListener();
    peerConnection.onIceConnectionState = (RTCIceConnectionState state) async {
      if (session.isConnected || session.isEnding) return;
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        session.isConnected = true;
        await updateCallStatus(callId: session.callId, status: 'connected');
        if (session.isCaller) {
          await _upsertCallRecord(session: session, status: 'connected');
        }
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          state == RTCIceConnectionState.RTCIceConnectionStateClosed) {
        await _endSessionAfterFailure(session);
      }
    };

    activeSession = session;
    return session;
  }

  Future<CallSession> initiateCall({
    required String chatId,
    required String callerId,
    required String callerName,
    required String receiverId,
    required String receiverName,
    required String type,
  }) async {
    final currentUser = await _requireCurrentUser(callerId);
    final safeChatId = chatId.trim();
    final safeReceiverId = receiverId.trim();
    final safeType = type.trim().toLowerCase();
    if (safeChatId.isEmpty || safeReceiverId.isEmpty) {
      throw ArgumentError('Call participants are invalid.');
    }
    if (safeType != 'audio' && safeType != 'video') {
      throw ArgumentError('Call type is invalid.');
    }
    if (activeSession != null) {
      throw StateError('Another call is already active.');
    }

    final callDocRef = _firestore.collection('calls').doc();
    MediaStream? localStream;
    RTCPeerConnection? peerConnection;
    try {
      localStream = await _getUserMedia(video: safeType == 'video');
      peerConnection = await _createPeerConnection();

      final session = await _prepareSession(
        callId: callDocRef.id,
        chatId: safeChatId,
        callerId: currentUser.uid,
        callerName: callerName,
        receiverId: safeReceiverId,
        receiverName: receiverName,
        type: safeType,
        isCaller: true,
        isReceiverOnline: false,
        localStream: localStream,
        peerConnection: peerConnection,
      );

      for (final track in localStream.getTracks()) {
        await peerConnection.addTrack(track, localStream);
      }

      peerConnection.onIceCandidate = (RTCIceCandidate? candidate) {
        if (candidate == null) return;
        unawaited(
          _writeCandidate(callDocRef.id, 'callerCandidates', candidate),
        );
      };

      final offer = await peerConnection.createOffer();
      await peerConnection.setLocalDescription(offer);

      await callDocRef.set({
        'callerId': currentUser.uid,
        'callerName': callerName,
        'receiverId': safeReceiverId,
        'receiverName': receiverName,
        'chatId': safeChatId,
        'type': safeType,
        'status': 'calling',
        'offer': {'type': offer.type, 'sdp': offer.sdp},
        'timestamp': FieldValue.serverTimestamp(),
      });

      _listenToCallUpdates(callDocRef.id);
      await _listenToRemoteCandidates(callDocRef.id, 'calleeCandidates');
      await session.scheduleAutoEnd(callDocRef.path);

      return session;
    } catch (_) {
      if (activeSession?.callId == callDocRef.id) {
        final session = activeSession;
        activeSession = null;
        await session?.dispose();
      } else {
        await peerConnection?.close();
        localStream?.getTracks().forEach((track) => track.stop());
      }
      rethrow;
    }
  }

  Future<CallSession> answerCall({
    required String callId,
    required String type,
    required String callerId,
    required String callerName,
    required String receiverId,
    required String receiverName,
    required String chatId,
  }) async {
    final currentUser = await _requireCurrentUser(receiverId);
    if (currentUser.uid == callerId.trim()) {
      throw StateError('Caller and receiver must be different users.');
    }
    if (callId.trim().isEmpty) throw ArgumentError('Call ID is invalid.');
    final safeType = type.trim().toLowerCase();
    if (safeType != 'audio' && safeType != 'video') {
      throw ArgumentError('Call type is invalid.');
    }
    if (activeSession != null) {
      throw StateError('Another call is already active.');
    }

    final callDocRef = _firestore.collection('calls').doc(callId);
    final callSnapshot = await callDocRef.get();
    final callData = callSnapshot.data();
    if (callData == null) {
      throw StateError('Call data not found');
    }

    MediaStream? localStream;
    RTCPeerConnection? peerConnection;
    try {
      localStream = await _getUserMedia(video: safeType == 'video');
      peerConnection = await _createPeerConnection();
      final session = await _prepareSession(
        callId: callId,
        chatId: chatId,
        callerId: callerId,
        callerName: callerName,
        receiverId: currentUser.uid,
        receiverName: receiverName,
        type: safeType,
        isCaller: false,
        isReceiverOnline: true,
        localStream: localStream,
        peerConnection: peerConnection,
      );

      for (final track in localStream.getTracks()) {
        await peerConnection.addTrack(track, localStream);
      }

      peerConnection.onIceCandidate = (RTCIceCandidate? candidate) {
        if (candidate == null) return;
        unawaited(_writeCandidate(callId, 'calleeCandidates', candidate));
      };

      final offer = callData['offer'] as Map<String, dynamic>?;
      if (offer == null) {
        throw StateError('Offer data missing');
      }

      await activeSession!.setRemoteDescription(
        RTCSessionDescription(offer['sdp'] as String, offer['type'] as String),
      );

      final answer = await peerConnection.createAnswer();
      await peerConnection.setLocalDescription(answer);

      await callDocRef.update({
        'status': 'accepted',
        'answer': {'type': answer.type, 'sdp': answer.sdp},
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _listenToCallUpdates(callId);
      await _listenToRemoteCandidates(callId, 'callerCandidates');
      await session.scheduleAutoEnd(callDocRef.path);

      // 🔥 إنهاء شاشة CallKit بمجرد الرد بنجاح
      await CallKitService.instance.endCall(callId);

      return session;
    } catch (_) {
      if (activeSession?.callId == callId) {
        final session = activeSession;
        activeSession = null;
        await session?.dispose();
      } else {
        await peerConnection?.close();
        localStream?.getTracks().forEach((track) => track.stop());
      }
      rethrow;
    }
  }

  Future<void> rejectCall(String callId) async {
    await updateCallStatus(callId: callId, status: 'rejected');
    await _finalizeCallWithoutSession(callId, 'rejected');
    await CallKitService.instance.endCall(callId); // تأكيد إنهاء CallKit
  }

  Future<void> endCall(String callId) async {
    final session = activeSession?.callId == callId ? activeSession : null;
    final terminalStatus = session?.isConnected == true ? 'ended' : 'canceled';
    try {
      session?.isEnding = true;
      await updateCallStatus(callId: callId, status: terminalStatus);
      if (session != null) {
        await _finalizeCallRecord(session: session, status: terminalStatus);
      } else {
        await _finalizeCallWithoutSession(callId, terminalStatus);
      }
      await CallKitService.instance.endCall(callId);
    } catch (error) {
      // Cleanup must still happen if signaling or CallKit fails.
      debugPrint('Failed to end call signaling: $error');
    } finally {
      if (session != null) {
        if (activeSession == session) activeSession = null;
        await session.dispose();
      }
    }
  }

  Future<void> updateCallStatus({
    required String callId,
    required String status,
    int? durationSeconds,
  }) async {
    if (_isDisposed) return;

    final payload = <String, dynamic>{
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (durationSeconds != null) {
      payload['durationSeconds'] = durationSeconds;
    }

    await _firestore.collection('calls').doc(callId).update(payload);
  }

  void _listenToCallUpdates(String callId) {
    final docRef = _firestore.collection('calls').doc(callId);
    activeSession?._callSubscription?.cancel();
    activeSession?._callSubscription = docRef.snapshots().listen((
      snapshot,
    ) async {
      final data = snapshot.data();
      if (data == null) return;
      final status = data['status'] as String?;
      final answer = data['answer'] as Map<String, dynamic>?;
      _updateStatus(status ?? 'unknown');

      if (status == 'accepted' &&
          activeSession?.isCaller == true &&
          answer != null) {
        final remoteDescription = RTCSessionDescription(
          answer['sdp'] as String,
          answer['type'] as String,
        );
        await activeSession?.setRemoteDescription(remoteDescription);
      }

      final session = activeSession;
      final remoteMediaType = data['type'] as String?;
      if (session != null &&
          remoteMediaType != null &&
          remoteMediaType != session.currentMediaType &&
          (remoteMediaType == 'audio' || remoteMediaType == 'video')) {
        session._updateMediaType(remoteMediaType);
      }
      final renegotiationId = data['renegotiationId'] as String?;
      final renegotiationBy = data['renegotiationBy'] as String?;
      final renegotiationOffer =
          data['renegotiationOffer'] as Map<String, dynamic>?;
      final renegotiationAnswer =
          data['renegotiationAnswer'] as Map<String, dynamic>?;
      if (session != null &&
          renegotiationId != null &&
          renegotiationBy != null &&
          renegotiationOffer != null &&
          renegotiationBy !=
              (session.isCaller ? session.callerId : session.receiverId) &&
          renegotiationId != session._lastHandledRenegotiationId) {
        session._lastHandledRenegotiationId = renegotiationId;
        await session.setRemoteDescription(
          RTCSessionDescription(
            renegotiationOffer['sdp'] as String,
            renegotiationOffer['type'] as String,
          ),
        );
        final renegotiationAnswerDescription = await session.peerConnection
            .createAnswer();
        await session.peerConnection.setLocalDescription(
          renegotiationAnswerDescription,
        );
        await docRef.update({
          'renegotiationAnswer': {
            'type': renegotiationAnswerDescription.type,
            'sdp': renegotiationAnswerDescription.sdp,
          },
        });
      } else if (session != null &&
          renegotiationId != null &&
          renegotiationId == session._lastRenegotiationId &&
          renegotiationAnswer != null) {
        await session.setRemoteDescription(
          RTCSessionDescription(
            renegotiationAnswer['sdp'] as String,
            renegotiationAnswer['type'] as String,
          ),
        );
      }

      // 🔥 تم التعديل الجذري هنا لضمان إغلاق CallKit وتنبيهات المكالمات الفائتة
      if (status == 'rejected' ||
          status == 'ended' ||
          status == 'canceled' ||
          status == 'missed' ||
          status == 'failed') {
        // إيقاف شاشة CallKit فوراً
        await CallKitService.instance.endCall(callId);

        final session = activeSession;

        if (session != null) {
          try {
            await _finalizeCallRecord(
              session: session,
              status: status ?? 'ended',
            );
          } catch (error) {
            debugPrint('Failed to finalize call record: $error');
          }
        }

        // إظهار إشعار مكالمة فائتة للمستلم إذا انقضى الوقت أو المتصل قفل
        if (status == 'missed' && session?.isCaller == false) {
          await CallKitService.instance.showMissedCall(
            callId: callId,
            callerName: session?.callerName ?? 'مكالمة فائتة',
          );
        }

        activeSession = null;
        if (session != null) {
          final normalizedStatus = status ?? 'ended';
          await updateCallStatus(
            callId: callId,
            status: normalizedStatus,
            durationSeconds: session.getDurationSeconds(),
          );
        }
        await session?.dispose();
      }
    });
  }

  Future<void> _listenToRemoteCandidates(
    String callId,
    String collectionPath,
  ) async {
    final collectionRef = _firestore
        .collection('calls')
        .doc(callId)
        .collection(collectionPath);
    activeSession?._candidateSubscription?.cancel();
    activeSession?._candidateSubscription = collectionRef.snapshots().listen((
      snapshot,
    ) async {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data == null) continue;

          final candidate = RTCIceCandidate(
            (data['candidate'] as String?) ?? '',
            (data['sdpMid'] as String?) ?? '',
            (data['sdpMLineIndex'] as int?) ?? 0,
          );

          try {
            await activeSession?.addRemoteCandidate(candidate);
          } catch (_) {}
        }
      }
    });
  }

  Future<void> _upsertCallRecord({
    required CallSession session,
    required String status,
  }) async {
    final messageId = 'call_${session.callId}';
    final text = _callRecordText(session.type, status);
    await ChatService().sendMessage(
      roomId: session.chatId,
      senderId: session.callerId,
      senderName: session.callerName,
      receiverId: session.receiverId,
      messageId: messageId,
      text: text,
      mediaType: ChatMessageType.call,
      mediaUrl: '',
      status: MessageStatus.sent,
    );

    session.callMessageId = messageId;
    session.callMessageCreated = true;
    await _firestore.collection('calls').doc(session.callId).update({
      'messageId': messageId,
    });
  }

  String _callRecordText(String type, String status) {
    final label = type == 'video' ? 'مكالمة فيديو' : 'مكالمة صوتية';
    switch (status) {
      case 'missed':
        return '$label فائتة';
      case 'rejected':
        return '$label مرفوضة';
      case 'canceled':
        return '$label ملغاة';
      case 'failed':
        return '$label فاشلة';
      case 'ended':
        return '$label منتهية';
      default:
        return '$label صادرة';
    }
  }

  Future<void> _finalizeCallRecord({
    required CallSession session,
    required String status,
  }) async {
    await _upsertCallRecord(session: session, status: status);
    if (status == 'missed') {
      await NotificationService().createNotification(
        senderId: session.callerId,
        receiverId: session.receiverId,
        type: 'missed_call',
        referenceId: session.callId,
        roomId: session.chatId,
        notificationKey: 'missed_call:${session.callId}:${session.receiverId}',
      );
    }
  }

  Future<void> _finalizeCallWithoutSession(String callId, String status) async {
    final snapshot = await _firestore.collection('calls').doc(callId).get();
    final data = snapshot.data();
    if (data == null) return;

    final chatId = (data['chatId'] as String? ?? '').trim();
    final callerId = (data['callerId'] as String? ?? '').trim();
    final callerName = (data['callerName'] as String? ?? 'مستخدم').trim();
    final receiverId = (data['receiverId'] as String? ?? '').trim();
    final type = (data['type'] as String? ?? 'audio').trim();
    if (chatId.isEmpty || callerId.isEmpty || receiverId.isEmpty) return;

    await ChatService().sendMessage(
      roomId: chatId,
      senderId: callerId,
      senderName: callerName,
      receiverId: receiverId,
      messageId: 'call_$callId',
      text: _callRecordText(type, status),
      mediaType: ChatMessageType.call,
      mediaUrl: '',
      status: MessageStatus.sent,
    );
    await _firestore.collection('calls').doc(callId).update({
      'messageId': 'call_$callId',
    });
    if (status == 'missed') {
      await NotificationService().createNotification(
        senderId: callerId,
        receiverId: receiverId,
        type: 'missed_call',
        referenceId: callId,
        roomId: chatId,
        notificationKey: 'missed_call:$callId:$receiverId',
      );
    }
  }

  Future<void> finalizeCallWithoutSession({
    required String callId,
    required String status,
  }) async {
    await _finalizeCallWithoutSession(callId, status);
  }

  void _updateStatus(String status) {
    final session = activeSession;
    if (session != null) {
      session._updateStatus(status);
    }
  }

  void startIncomingCallListener({required String currentUserId}) {
    _incomingCallSubscription?.cancel();
    _incomingCallSubscription = _firestore
        .collection('calls')
        .where('receiverId', isEqualTo: currentUserId)
        .where('status', isEqualTo: 'calling')
        .snapshots()
        .listen((snapshot) {
          for (final change in snapshot.docChanges) {
            final callId = change.doc.id;

            // 🔥 التعديل الجذري: إذا تم حذف أو تعديل المكالمة (المتصل قفل أو انتهى الوقت) نغلق CallKit
            if (change.type == DocumentChangeType.removed) {
              CallKitService.instance.endCall(callId);
              continue;
            }

            if (change.type == DocumentChangeType.added) {
              if (activeSession != null) return;

              final data = change.doc.data();
              if (data == null) continue;

              final callerName = data['callerName'] as String? ?? 'مستخدم';
              final callerId = data['callerId'] as String? ?? '';
              final chatId = data['chatId'] as String? ?? '';
              final callType = data['type'] as String? ?? 'audio';
              final receiverName = data['receiverName'] as String? ?? '';

              _incomingCallController.add(
                IncomingCall(
                  callId: callId,
                  callerId: callerId,
                  callerName: callerName,
                  receiverId: currentUserId,
                  receiverName: receiverName,
                  chatId: chatId,
                  type: callType,
                ),
              );
            }
          }
        });
  }

  void stopIncomingCallListener() {
    _incomingCallSubscription?.cancel();
    _incomingCallSubscription = null;
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;

    _incomingCallSubscription?.cancel();
    activeSession?.dispose();
    if (!_incomingCallController.isClosed) {
      _incomingCallController.close();
    }
  }
}

class IncomingCall {
  final String callId;
  final String callerId;
  final String callerName;
  final String receiverId;
  final String receiverName;
  final String chatId;
  final String type;

  IncomingCall({
    required this.callId,
    required this.callerId,
    required this.callerName,
    required this.receiverId,
    required this.receiverName,
    required this.chatId,
    required this.type,
  });
}

class CallState {
  final String callId;
  final String chatId;
  final String callerId;
  final String receiverId;
  final bool isCaller;
  final String type;
  final String status;

  CallState({
    required this.callId,
    required this.chatId,
    required this.callerId,
    required this.receiverId,
    required this.isCaller,
    required this.type,
    required this.status,
  });
}

class CallNotSupportedException implements Exception {
  final String message;
  CallNotSupportedException([
    this.message = 'Call is not supported on this platform.',
  ]);

  @override
  String toString() => message;
}
