import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/post.dart';
import '../models/app_user.dart'; // تم إضافة استدعاء موديل المستخدم
import '../services/category_service.dart';
import 'settings_provider.dart';

class FeedProvider extends ChangeNotifier {
  final FirebaseFirestore firestore;

  FeedProvider({FirebaseFirestore? firestoreInstance})
    : firestore = firestoreInstance ?? FirebaseFirestore.instance;

  // 1. خوارزمية زامل الذكية (دي الدالة اللي كانت ناقصة وجابت الخطأ)
  Stream<List<Post>> getAlgorithmicFeed(AppUser? currentUser) {
    final query = firestore
        .collection('posts')
        .orderBy('timestamp', descending: true)
        .limit(100);

    return query.snapshots().map((snapshot) {
      List<Post> posts = snapshot.docs
          .map((doc) => Post.fromFirestore(doc))
          .toList();

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

  static String normalizeCategoryFilter(String? categoryId) {
    return SettingsProvider.normalizeFeedMode(categoryId);
  }

  // 2. الدالة القديمة (خليناها كاحتياط)
  Stream<List<Post>> postsStream({
    String? categoryId,
    AppUser? currentUser,
  }) async* {
    final normalizedMode = normalizeCategoryFilter(categoryId);
    final excludedPostIds = <String>{};
    final reducedCategoryIds = <String>{};
    final normalizedUserId = currentUser?.id.trim();
    if (normalizedUserId != null && normalizedUserId.isNotEmpty) {
      try {
        final userSnapshot = await firestore
            .collection('users')
            .doc(normalizedUserId)
            .get();
        final userData = userSnapshot.data();
        if (userData != null) {
          excludedPostIds.addAll(_stringList(userData['hiddenPostIds']));
          reducedCategoryIds.addAll(
            _stringList(userData['reducedPostCategoryIds']),
          );
        }
      } catch (_) {}
    }
    if (normalizedMode == 'all') {
      yield* _postsQuery().snapshots().map(
        (snapshot) => _postsFromSnapshot(
          snapshot,
          currentUser,
          excludedPostIds,
          reducedCategoryIds,
        ),
      );
      return;
    }

    final List<String> availableCategoryIds;
    try {
      final categories = await CategoryService.fetchCategories();
      availableCategoryIds = categories.map((category) => category.id).toList();
    } catch (_) {
      yield const <Post>[];
      return;
    }

    final resolvedCategoryId = SettingsProvider.resolveCategoryIdForFeedMode(
      normalizedMode,
      availableCategoryIds,
    );
    if (resolvedCategoryId == null || resolvedCategoryId.trim().isEmpty) {
      yield const <Post>[];
      return;
    }

    yield* _postsQuery(categoryId: resolvedCategoryId).snapshots().map(
      (snapshot) => _postsFromSnapshot(
        snapshot,
        currentUser,
        excludedPostIds,
        reducedCategoryIds,
      ),
    );
  }

  Query<Map<String, dynamic>> _postsQuery({String? categoryId}) {
    Query<Map<String, dynamic>> query = firestore.collection('posts');
    final normalizedCategoryId = categoryId?.trim();
    if (normalizedCategoryId != null && normalizedCategoryId.isNotEmpty) {
      query = query.where('categoryId', isEqualTo: normalizedCategoryId);
    }
    return query.orderBy('timestamp', descending: true);
  }

  List<Post> _postsFromSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
    AppUser? currentUser,
    Set<String> excludedPostIds,
    Set<String> reducedCategoryIds,
  ) {
    return snapshot.docs
        .map(Post.fromFirestore)
        .where((post) => _isVisibleToUser(post, currentUser))
        .where((post) => !excludedPostIds.contains(post.id))
        .where(
          (post) =>
              post.categoryId == null ||
              !reducedCategoryIds.contains(post.categoryId),
        )
        .toList();
  }

  bool _isVisibleToUser(Post post, AppUser? currentUser) {
    if (post.privacy == 'public') return true;
    if (currentUser == null) return false;
    if (post.userId == currentUser.id) return true;
    if (post.privacy != 'friends') return false;
    return currentUser.following.contains(post.userId) ||
        currentUser.followers.contains(post.userId);
  }

  List<String> _stringList(Object? value) {
    if (value is! List) return const <String>[];
    return value
        .whereType<String>()
        .where((item) => item.trim().isNotEmpty)
        .toList();
  }

  Future<String> getSavedFeedMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_mode') ?? 'all';
  }

  // 3. دالة حساب النقاط (الذكاء الاصطناعي للخوارزمية)
  int _calculateZamelScore(Post post, AppUser currentUser) {
    int score = 0;

    // المتابعة والأصدقاء (+50 نقطة)
    if (currentUser.following.contains(post.userId) ||
        post.userId == currentUser.id) {
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
    int totalEngagement =
        post.likes.length + post.commentsCount + post.reactions.length;
    score += (totalEngagement * 2);

    // الزمن (خصم نقطة لكل ساعة تمر على المنشور)
    final hoursDifference = DateTime.now().difference(post.timestamp).inHours;
    if (hoursDifference > 0) {
      score -= hoursDifference;
    }

    return score;
  }
}
