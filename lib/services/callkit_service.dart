import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

class CallKitService {
  CallKitService._();
  static final CallKitService instance = CallKitService._();

  // دالة إظهار شاشة الاتصال الأصلية (توقظ الهاتف ويرن بصوت عالٍ)
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
        isShowCallback: true,
        subtitle: 'مكالمة فائتة',
        callbackText: 'معاودة الاتصال',
      ),
      extra: <String, dynamic>{'callId': callId, 'type': type},
      headers: <String, dynamic>{'apiKey': 'zamel_secure_key'},
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#000000',
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
        audioSessionMode: 'default',
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

  // دالة إنهاء الرنين فوراً (إذا قفل الطرف الآخر الخط قبل أن ترد)
  Future<void> endCall(String callId) async {
    await FlutterCallkitIncoming.endCall(callId);
  }

  // دالة إظهار إشعار مكالمة فائتة يدوياً (تستخدم فقط في حالات خاصة)
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
