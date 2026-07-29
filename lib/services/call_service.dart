import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import 'chat_service.dart';

class CallSession {
  final String callId;
  final String chatId;
  final String callerId;
  final String callerName;
  final String receiverId;
  final String receiverName;
  final String type;
  final bool isCaller;
  final RTCPeerConnection peerConnection;
  final MediaStream localStream;
  MediaStream? remoteStream;
  bool _isDisposed = false;
  DateTime? startedAt;
  DateTime? endedAt;
  final StreamController<MediaStream?> _remoteStreamController = StreamController.broadcast();
  final StreamController<String> _statusController = StreamController.broadcast();
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _callSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _candidateSubscription;
  // removed unused helper
  Timer? _autoEndTimer;
  String currentFacingMode = 'user';

  CallSession({
    required this.callId,
    required this.chatId,
    required this.callerId,
    required this.callerName,
    required this.receiverId,
    required this.receiverName,
    required this.type,
    required this.isCaller,
    required this.peerConnection,
    required this.localStream,
  });

  Stream<MediaStream?> get remoteStreamStream => _remoteStreamController.stream;
  Stream<String> get statusStream => _statusController.stream;

  void _updateRemoteStream(MediaStream? stream) {
    remoteStream = stream;
    _remoteStreamController.add(stream);
  }

  void _updateStatus(String status) {
    if (status == 'accepted' && startedAt == null) {
      startedAt = DateTime.now();
    }
    if (status == 'ended' || status == 'rejected' || status == 'canceled') {
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
    _autoEndTimer = Timer(const Duration(minutes: 2), () async {
      final docRef = FirebaseFirestore.instance.doc(callDocumentPath);
      final snapshot = await docRef.get();
      final data = snapshot.data();
      final status = data == null ? null : data['status'] as String?;
      if (status == 'calling' || status == 'ringing') {
        await docRef.update({'status': 'ended'});
      }
    });
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

  Future<void> switchCamera() async {
    final videoTracks = localStream.getVideoTracks();
    if (videoTracks.isEmpty) return;
    currentFacingMode = currentFacingMode == 'user' ? 'environment' : 'user';

    final oldTrack = videoTracks.first;
    final newStream = await navigator.mediaDevices.getUserMedia({
      'audio': false,
      'video': {'facingMode': currentFacingMode},
    });
    final newTrack = newStream.getVideoTracks().first;

    localStream.removeTrack(oldTrack);
    localStream.addTrack(newTrack);

    final senders = await peerConnection.getSenders();
    RTCRtpSender? sender;
    for (final item in senders) {
      if (item.track?.kind == 'video') {
        sender = item;
        break;
      }
    }

    if (sender != null) {
      await sender.replaceTrack(newTrack);
    }
    oldTrack.stop();
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
    ]
  };

  final StreamController<IncomingCall> _incomingCallController = StreamController<IncomingCall>.broadcast();
  Stream<IncomingCall> get incomingCallStream => _incomingCallController.stream;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _incomingCallSubscription;
  CallSession? activeSession;
  bool _isDisposed = false;

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
      peerConnection: peerConnection,
      localStream: localStream,
    );

    session.attachStreamListener();

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
    final callDocRef = _firestore.collection('calls').doc();
    final localStream = await _getUserMedia(video: type == 'video');
    final peerConnection = await _createPeerConnection();
    await _prepareSession(
      callId: callDocRef.id,
      chatId: chatId,
      callerId: callerId,
      callerName: callerName,
      receiverId: receiverId,
      receiverName: receiverName,
      type: type,
      isCaller: true,
      localStream: localStream,
      peerConnection: peerConnection,
    );

    localStream.getTracks().forEach((track) {
      peerConnection.addTrack(track, localStream);
    });

    peerConnection.onIceCandidate = (RTCIceCandidate? candidate) {
      if (candidate == null) return;
      _firestore
          .collection('calls')
          .doc(callDocRef.id)
          .collection('callerCandidates')
          .add(_candidateToMap(candidate));
    };

    final offer = await peerConnection.createOffer();
    await peerConnection.setLocalDescription(offer);

    await callDocRef.set({
      'callerId': callerId,
      'callerName': callerName,
      'receiverId': receiverId,
      'receiverName': receiverName,
      'chatId': chatId,
      'type': type,
      'status': 'calling',
      'offer': {'type': offer.type, 'sdp': offer.sdp},
      'timestamp': FieldValue.serverTimestamp(),
    });

    await ChatService().sendMessage(
      roomId: chatId,
      senderId: callerId,
      senderName: callerName,
      receiverId: receiverId,
      text: type == 'video' ? 'بدء مكالمة فيديو' : 'بدء مكالمة صوتية',
      mediaType: 'call',
      mediaUrl: '',
    );

    _listenToCallUpdates(callDocRef.id);
    await _listenToRemoteCandidates(callDocRef.id, 'calleeCandidates');
    activeSession?.scheduleAutoEnd(callDocRef.path);

    return activeSession!;
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
    final callDocRef = _firestore.collection('calls').doc(callId);
    final callSnapshot = await callDocRef.get();
    final callData = callSnapshot.data();
    if (callData == null) {
      throw StateError('Call data not found');
    }

    final localStream = await _getUserMedia(video: type == 'video');
    final peerConnection = await _createPeerConnection();
    await _prepareSession(
      callId: callId,
      chatId: chatId,
      callerId: callerId,
      callerName: callerName,
      receiverId: receiverId,
      receiverName: receiverName,
      type: type,
      isCaller: false,
      localStream: localStream,
      peerConnection: peerConnection,
    );

    localStream.getTracks().forEach((track) {
      peerConnection.addTrack(track, localStream);
    });

    peerConnection.onIceCandidate = (RTCIceCandidate? candidate) {
      if (candidate == null) return;
      _firestore
          .collection('calls')
          .doc(callId)
          .collection('calleeCandidates')
          .add(_candidateToMap(candidate));
    };

    final offer = callData['offer'] as Map<String, dynamic>?;
    if (offer == null) {
      throw StateError('Offer data missing');
    }

    await peerConnection.setRemoteDescription(
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
    activeSession?.scheduleAutoEnd(callDocRef.path);

    return activeSession!;
  }

  Future<void> rejectCall(String callId) async {
    await updateCallStatus(callId: callId, status: 'rejected');
  }

  Future<void> endCall(String callId) async {
    try {
      if (activeSession?.callId == callId) {
        activeSession = null;
      }
      await updateCallStatus(callId: callId, status: 'ended');
    } catch (_) {}
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
    activeSession?._callSubscription = docRef.snapshots().listen((snapshot) async {
      final data = snapshot.data();
      if (data == null) return;
      final status = data['status'] as String?;
      final answer = data['answer'] as Map<String, dynamic>?;
      _updateStatus(status ?? 'unknown');

      if (status == 'accepted' && activeSession?.isCaller == true && answer != null) {
        final remoteDescription = RTCSessionDescription(answer['sdp'] as String, answer['type'] as String);
        await activeSession?.peerConnection.setRemoteDescription(remoteDescription);
      }

      if (status == 'rejected' || status == 'ended' || status == 'canceled') {
        final session = activeSession;
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

  Future<void> _listenToRemoteCandidates(String callId, String collectionPath) async {
    final collectionRef = _firestore.collection('calls').doc(callId).collection(collectionPath);
    activeSession?._candidateSubscription?.cancel();
    activeSession?._candidateSubscription = collectionRef.snapshots().listen((snapshot) async {
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
            await activeSession?.peerConnection.addCandidate(candidate);
          } catch (_) {}
        }
      }
    });
  }

  void _updateStatus(String status) {
    final session = activeSession;
    if (session != null) {
      session._updateStatus(status);
    }
  }

  void startIncomingCallListener({
    required String currentUserId,
  }) {
    _incomingCallSubscription?.cancel();
    _incomingCallSubscription = _firestore
        .collection('calls')
        .where('receiverId', isEqualTo: currentUserId)
        .where('status', isEqualTo: 'calling')
        .snapshots()
        .listen((snapshot) {
      if (activeSession != null) {
        return;
      }
      for (final change in snapshot.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final data = change.doc.data();
        if (data == null) continue;

        final callId = change.doc.id;
        final callerName = data['callerName'] as String? ?? 'مستخدم';
        final callerId = data['callerId'] as String? ?? '';
        final chatId = data['chatId'] as String? ?? '';
        final callType = data['type'] as String? ?? 'audio';
        final receiverName = data['receiverName'] as String? ?? '';

        _incomingCallController.add(IncomingCall(
          callId: callId,
          callerId: callerId,
          callerName: callerName,
          receiverId: currentUserId,
          receiverName: receiverName,
          chatId: chatId,
          type: callType,
        ));
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
  CallNotSupportedException([this.message = 'Call is not supported on this platform.']);

  @override
  String toString() => message;
}
