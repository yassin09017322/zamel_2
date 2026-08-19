import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import '../models/app_user.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final FirebaseAuth auth = FirebaseAuth.instance;
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();

  AppUser? currentUser;
  bool isLoading = true;
  String? errorMessage;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSubscription;

  AuthProvider() {
    _initialize();
  }

  Future<void> _initialize() async {
    auth.authStateChanges().listen((firebaseUser) async {
      isLoading = true;
      errorMessage = null;
      notifyListeners();

      await _userSubscription?.cancel();
      _userSubscription = null;

      // منع الدخول نهائياً إذا لم يكن المستخدم موجوداً أو بريده غير مفعل
      if (firebaseUser == null || !firebaseUser.emailVerified) {
        currentUser = null;
        isLoading = false;
        notifyListeners();
        return;
      }

      // جلب بيانات المستخدم من فايرستور
      final userRef = firestore.collection('users').doc(firebaseUser.uid);
      _userSubscription = userRef.snapshots().listen(
        (snapshot) async {
          if (snapshot.exists && snapshot.data() != null) {
            currentUser = AppUser.fromFirestore(snapshot.data()!, firebaseUser.uid);
            if (currentUser != null && currentUser!.isOnline != true) {
              await updateUserPresence(online: true);
            }
          } else {
            currentUser = null;
          }
          isLoading = false;
          notifyListeners();
        },
        onError: (error) {
          errorMessage = error.toString();
          isLoading = false;
          notifyListeners();
        },
      );
    });
  }

  Future<void> signIn(String email, String password) async {
    await signInWithEmail(email, password);
  }

  Future<String?> signInWithEmail(String email, String password) async {
    _clearError();
    isLoading = true;
    notifyListeners();

    try {
      await _authService.login(email: email, password: password);
      return null;
    } on FirebaseAuthException catch (error) {
      final message = error.message ?? error.code;
      errorMessage = message;
      return message;
    } catch (error) {
      final message = error.toString();
      errorMessage = message;
      return message;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> register({
    required String email,
    required String username,
    required String password,
  }) async {
    await registerWithEmail(email, password, username: username);
  }

  Future<String?> registerWithEmail(String email, String password, {required String username}) async {
    _clearError();
    isLoading = true;
    notifyListeners();

    try {
      await _authService.register(
        username: username,
        email: email,
        password: password,
      );
      return null;
    } on FirebaseAuthException catch (error) {
      final message = error.message ?? error.code;
      errorMessage = message;
      return message;
    } catch (error) {
      final message = error.toString();
      errorMessage = message;
      return message;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> sendPasswordReset(String email) async {
    await resetPassword(email);
  }

  Future<String?> resetPassword(String email) async {
    _clearError();
    isLoading = true;
    notifyListeners();

    try {
      await _authService.resetPassword(email: email);
      return null;
    } on FirebaseAuthException catch (error) {
      final message = error.message ?? error.code;
      errorMessage = message;
      return message;
    } catch (error) {
      final message = error.toString();
      errorMessage = message;
      return message;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    _clearError();
    isLoading = true;
    notifyListeners();
    try {
      // Update presence to offline
      await updateUserPresence(online: false);
      
      // Cancel user data subscription
      await _userSubscription?.cancel();
      _userSubscription = null;
      
      // Clear user data
      currentUser = null;
      
      // Sign out from Firebase
      await auth.signOut();
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateUserPresence({required bool online}) async {
    if (currentUser == null) return;

    try {
      final presenceRef = FirebaseDatabase.instance.ref().child('presence/${currentUser!.id}');

      await presenceRef.onDisconnect().set({
        'online': false,
        'lastSeen': ServerValue.timestamp,
      });

      await presenceRef.set({
        'online': online,
        'lastSeen': ServerValue.timestamp,
      });

      currentUser = currentUser!.copyWith(
        isOnline: online,
        lastSeen: online ? currentUser!.lastSeen : DateTime.now(),
      );
      notifyListeners();
    } catch (_) {
      // ignore errors silently
    }
  }

  Future<void> updateSharePresenceSetting(bool sharePresence) async {
    if (currentUser == null) return;

    try {
      final data = <String, Object?>{
        'sharePresence': sharePresence,
      };
      if (!sharePresence) {
        data['isOnline'] = false;
        data['lastSeen'] = FieldValue.serverTimestamp();
      }
      await firestore.collection('users').doc(currentUser!.id).update(data);
      currentUser = currentUser!.copyWith(
        sharePresence: sharePresence,
        isOnline: sharePresence ? currentUser!.isOnline : false,
        lastSeen: !sharePresence ? DateTime.now() : currentUser!.lastSeen,
      );
      notifyListeners();
    } catch (_) {
      // ignore errors silently
    }
  }

  Future<void> updateProfile({
    String? username,
    String? bio,
    String? location,
    String? work,
    String? hobby,
    String? photoURL,
  }) async {
    if (currentUser == null) return;
    _clearError();
    isLoading = true;
    notifyListeners();

    final updateData = <String, dynamic>{};
    if (username != null) updateData['username'] = username;
    if (bio != null) updateData['bio'] = bio;
    if (location != null) updateData['location'] = location;
    if (work != null) updateData['work'] = work;
    if (hobby != null) updateData['hobby'] = hobby;
    if (photoURL != null) updateData['photoURL'] = photoURL;

    try {
      await firestore.collection('users').doc(currentUser!.id).update(updateData);
    } catch (error) {
      errorMessage = error.toString();
    }

    isLoading = false;
    notifyListeners();
  }

  void _clearError() {
    errorMessage = null;
  }

  @override
  void dispose() {
    _userSubscription?.cancel();
    super.dispose();
  }
}