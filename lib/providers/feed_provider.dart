import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/post.dart';
import '../models/app_user.dart'; // تم إضافة استدعاء موديل المستخدم

class FeedProvider extends ChangeNotifier {
  final FirebaseFirestore firestore;

  FeedProvider({FirebaseFirestore? firestoreInstance}) : firestore = firestoreInstance ?? FirebaseFirestore.instance;

  // 1. خوارزمية زامل الذكية (دي الدالة اللي كانت ناقصة وجابت الخطأ)
  Stream<List<Post>> getAlgorithmicFeed(AppUser? currentUser) {
    final query = firestore.collection('posts').orderBy('timestamp', descending: true).limit(100);
    
    return query.snapshots().map((snapshot) {
      List<Post> posts = snapshot.docs.map((doc) => Post.fromFirestore(doc)).toList();

      // إذا لم يكن المستخدم مسجلاً، اعرض المنشورات بالترتيب العادي
      if (currentUser == null) return posts;

      // ترتيب المنشورات بناءً على نقاط الخوارزمية
      posts.sort((a, b) {
        int scoreA = _calculateZamelScore(a, currentUser);
        int scoreB = _calculateZamelScore(b, currentUser);
        // ترتيب تنازلي (الأعلى نقاطاً يظهر أولاً)
        return scoreB.compareTo(scoreA);
      });

      return posts;
    });
  }

  // 2. الدالة القديمة (خليناها كاحتياط)
  Stream<List<Post>> postsStream() {
    final query = firestore.collection('posts').orderBy('timestamp', descending: true);
    return query.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => Post.fromFirestore(doc)).toList();
    });
  }

  // 3. دالة حساب النقاط (الذكاء الاصطناعي للخوارزمية)
  int _calculateZamelScore(Post post, AppUser currentUser) {
    int score = 0;

    // المتابعة والأصدقاء (+50 نقطة)
    if (currentUser.following.contains(post.userId) || post.userId == currentUser.id) {
      score += 50;
    }

    // الموقع الجغرافي (+30 نقطة)
    if (post.location.isNotEmpty && post.location == currentUser.location) {
      score += 30;
    }

    // الهواية / الاهتمامات (+20 نقطة)
    if (currentUser.hobby.isNotEmpty && post.text.contains(currentUser.hobby)) {
      score += 20;
    }

    // التفاعل والتريند (+2 نقطة لكل تفاعل)
    int totalEngagement = post.likes.length + post.commentsCount + post.reactions.length;
    score += (totalEngagement * 2);

    // الزمن (خصم نقطة لكل ساعة تمر على المنشور)
    final hoursDifference = DateTime.now().difference(post.timestamp).inHours;
    if (hoursDifference > 0) {
      score -= hoursDifference;
    }

    return score;
  }
}