import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 1. دالة تسجيل الدخول
  Future<void> login({
    required String email,
    required String password,
  }) async {
    UserCredential userCredential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    // منع الدخول فورا إذا كان البريد غير مفعل
    if (userCredential.user != null && !userCredential.user!.emailVerified) {
      await _auth.signOut();
      throw FirebaseAuthException(
        code: 'email-not-verified',
        message: 'يرجى مراجعة بريدك الإلكتروني والضغط على رابط التفعيل لتتمكن من الدخول.',
      );
    }
  }

  // 2. دالة تسجيل حساب جديد متكاملة
  Future<void> register({
    required String username,
    required String email,
    required String password,
  }) async {
    // أ. إنشاء الحساب
    UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    User? user = userCredential.user;

    if (user != null) {
      // ب. تحديث اسم المستخدم
      await user.updateDisplayName(username);

      // ج. إنشاء مستند المستخدم في Firestore مباشرة هنا
      await _firestore.collection('users').doc(user.uid).set({
        'username': username,
        'email': email,
        'bio': 'مرحباً! أنا في ZAMEL ✨',
        'photoURL': 'default-avatar.png',
        'location': '',
        'work': '',
        'hobby': '',
        'points': 0,
        'rank': 'عضو جديد',
        'createdAt': FieldValue.serverTimestamp(),
        'followers': [],
        'following': [],
      });

      // د. إرسال رسالة التفعيل للمستخدم
      await user.sendEmailVerification();

      // هـ. تسجيل الخروج فوراً لمنع تضارب الشاشات والدخول العشوائي
      await _auth.signOut();
    }
  }

  // 3. دالة استعادة كلمة المرور
  Future<void> resetPassword({required String email}) async {
    await _auth.sendPasswordResetEmail(email: email);
  }
}