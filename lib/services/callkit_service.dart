import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

class CallKitService {
  CallKitService._() {
    _initEvents();
  }
  static final CallKitService instance = CallKitService._();

  // قناة اتصال (Stream) لنقل قرار المستخدم (رد / رفض) إلى شاشة المحادثة
  final StreamController<Map<String, dynamic>> _callEventController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get callEventStream =>
      _callEventController.stream;

  // الاستماع لرد فعل المستخدم من شاشة الاتصال الأصلية
  void _initEvents() {
    // 🔥 تم استخدام 'dynamic' هنا لتخطي كل أخطاء (The getter isn't defined) و (Undefined name Event)
    // التي ظهرت في محرر الأكواد بسبب اختلاف إصدارات المكتبة
    FlutterCallkitIncoming.onEvent.listen((event) {
      if (event == null) return;

      try {
        String? action;
        String? callId;
        String type = 'audio';

        if (event is CallEventActionCallAccept) {
          action = 'accept';
          callId = event.callKitParams.id;
          type = (event.callKitParams.extra?['type'] as String?) ?? 'audio';
        } else if (event is CallEventActionCallDecline) {
          action = 'decline';
          callId = event.callKitParams.id;
          type = (event.callKitParams.extra?['type'] as String?) ?? 'audio';
        } else if (event is CallEventActionCallTimeout) {
          action = 'timeout';
          callId = event.id;
        } else if (event is CallEventActionCallEnded) {
          action = 'ended';
          callId = event.callKitParams.id;
        }

        if (action != null && callId != null && callId.isNotEmpty) {
          _callEventController.add({
            'event': action,
            'callId': callId,
            'type': type,
          });
        }
      } catch (error) {
        debugPrint('Error parsing CallKit event: $error');
      }
    });
  }

  // دالة إظهار شاشة الاتصال الأصلية
  Future<void> showIncomingCall({
    required String callId,
    required String callerName,
    required String type, // 'video' أو 'audio'
  }) async {
    final params = CallKitParams(
      id: callId,
      nameCaller: callerName,
      appName: 'ZAMEL',
      handle: type == 'video' ? 'مكالمة فيديو 🎥' : 'مكالمة صوتية 📞',
      type: type == 'video' ? 1 : 0,
      duration: 120000, // مدة الرنين دقيقتان
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: false, // تعطيل معاودة الاتصال مؤقتاً لتقليل الأخطاء
        subtitle: 'مكالمة فائتة',
      ),
      extra: <String, dynamic>{'callId': callId, 'type': type},
      headers: <String, dynamic>{'apiKey': 'zamel_secure_key'},
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0955fa',
        backgroundUrl: 'https://i.pravatar.cc/500', // صورة خلفية احترافية
        actionColor: '#4CAF50',
        textColor: '#ffffff',
        textAccept: 'رد',
        textDecline: 'رفض',
      ),
      ios: const IOSParams(
        iconName: 'AppIcon',
        handleType: 'generic',
        supportsVideo: true,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'videoChat', // تم التعديل لدعم الـ WebRTC
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        supportsDTMF: true,
        supportsHolding: true,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: 'system_ringtone_default',
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  // دالة إنهاء الرنين فوراً
  Future<void> endCall(String callId) async {
    await FlutterCallkitIncoming.endCall(callId);
  }

  // دالة إظهار إشعار مكالمة فائتة
  Future<void> showMissedCall({
    required String callId,
    required String callerName,
  }) async {
    await FlutterCallkitIncoming.showMissCallNotification(
      CallKitParams(
        id: callId,
        nameCaller: callerName,
        appName: 'ZAMEL',
        handle: 'مكالمة فائتة',
        type: 0,
        extra: <String, dynamic>{'callId': callId},
      ),
    );
  }
}
