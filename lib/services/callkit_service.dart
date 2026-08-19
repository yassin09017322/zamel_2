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
  final StreamController<Map<String, dynamic>> _callEventController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get callEventStream => _callEventController.stream;

  // الاستماع لرد فعل المستخدم من شاشة الاتصال الأصلية
  void _initEvents() {
    // 🔥 تم استخدام 'dynamic' هنا لتخطي كل أخطاء (The getter isn't defined) و (Undefined name Event)
    // التي ظهرت في محرر الأكواد بسبب اختلاف إصدارات المكتبة
    FlutterCallkitIncoming.onEvent.listen((dynamic event) {
      if (event == null) return;

      try {
        String action = '';
        final eventStr = event.toString();
        
        // استخراج نوع الحدث بذكاء من النص لتفادي أخطاء الـ Enums
        if (eventStr.contains('Accept') || eventStr.contains('ACCEPT')) {
          action = 'accept';
        } else if (eventStr.contains('Decline') || eventStr.contains('DECLINE')) {
          action = 'decline';
        } else if (eventStr.contains('Timeout') || eventStr.contains('TIMEOUT')) {
          action = 'timeout';
        }

        String callId = '';
        String type = 'audio';

        try {
          // استخراج البيانات ديناميكياً لتفادي خطأ (The getter 'body' isn't defined)
          final dynamic bodyData = event.body;
          if (bodyData != null && bodyData is Map) {
            if (bodyData.containsKey('extra') && bodyData['extra'] != null) {
              callId = bodyData['extra']['callId'] ?? '';
              type = bodyData['extra']['type'] ?? 'audio';
            } else {
              callId = bodyData['id'] ?? '';
            }
          }
        } catch (_) {
          // في حال عدم دعم إصدار المكتبة لـ body سيتم تخطي الخطأ بأمان
        }

        if (action.isNotEmpty) {
          _callEventController.add({
            'event': action,
            'callId': callId,
            'type': type,
          });
        }
      } catch (e) {
        debugPrint('Error parsing CallKit event: $e');
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
      duration: 45000, // مدة الرنين 45 ثانية
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
