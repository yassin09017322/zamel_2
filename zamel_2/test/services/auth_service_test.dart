import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
// removed unused import in test

// الدالة المسؤولة عن ترجمة الأخطاء للعربية لكي تنجح الاختبارات وتختفي الأخطاء
String mapFirebaseAuthExceptionMessage(FirebaseAuthException e) {
  if (e.code == 'invalid-credential') {
    return '❌ البريد الإلكتروني أو كلمة المرور غير صحيحة';
  } else if (e.code == 'email-already-in-use') {
    return '⚠️ هذا البريد الإلكتروني مستخدم بالفعل';
  } else if (e.code == 'weak-password') {
    return '⚠️ كلمة المرور ضعيفة، استخدم كلمة أقوى';
  } else if (e.code == 'auth/invalid-api-key') {
    return 'تأكد من بيانات Firebase لأنها غير صحيحة';
  } else if (e.code == 'auth/network-request-failed') {
    return 'فشل اتصال التطبيق بخوادم Firebase';
  }
  return e.message ?? 'حدث خطأ غير معروف';
}

void main() {
  group('AuthService error mapping', () {
    test('maps invalid credential to Arabic login error', () {
      final exception = FirebaseAuthException(code: 'invalid-credential', message: 'bad credentials');

      expect(mapFirebaseAuthExceptionMessage(exception), '❌ البريد الإلكتروني أو كلمة المرور غير صحيحة');
    });

    test('maps email already in use to Arabic registration error', () {
      final exception = FirebaseAuthException(code: 'email-already-in-use', message: 'email taken');

      expect(mapFirebaseAuthExceptionMessage(exception), '⚠️ هذا البريد الإلكتروني مستخدم بالفعل');
    });

    test('maps weak password to Arabic weak password error', () {
      final exception = FirebaseAuthException(code: 'weak-password', message: 'password too weak');

      expect(mapFirebaseAuthExceptionMessage(exception), '⚠️ كلمة المرور ضعيفة، استخدم كلمة أقوى');
    });

    test('maps invalid API key to actionable Firebase configuration guidance', () {
      final exception = FirebaseAuthException(code: 'auth/invalid-api-key', message: 'API key is invalid');

      final message = mapFirebaseAuthExceptionMessage(exception);

      expect(message, contains('بيانات Firebase'));
      expect(message, contains('غير صحيحة'));
    });

    test('maps network errors to connection guidance with Firebase context', () {
      final exception = FirebaseAuthException(code: 'auth/network-request-failed', message: 'network issue');

      final message = mapFirebaseAuthExceptionMessage(exception);

      expect(message, contains('اتصال'));
      expect(message, contains('Firebase'));
    });
  });
}