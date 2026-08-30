import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/post.dart';
import '../models/app_user.dart'; // تم إضافة استدعاء موديل المستخدم
import '../models/category_model.dart';
import '../services/category_service.dart';
import 'settings_provider.dart';

class FeedProvider extends ChangeNotifier {
  final FirebaseFirestore firestore;
  static const int pageSize = 12;

  FeedProvider({FirebaseFirestore? firestoreInstance})
    : firestore = firestoreInstance ?? FirebaseFirestore.instance;

  List<Post> posts = <Post>[];
  DocumentSnapshot<Map<String, dynamic>>? _lastDocument;
  bool isLoading = false;
  bool isLoadingMore = false;
  bool hasMore = true;
  String? errorMessage;
  String? _activeCategoryId;
  String? _activeResolvedCategoryId;
  Set<String> _excludedPostIds = <String>{};
  Set<String> _reducedCategoryIds = <String>{};

  Future<void> loadFirstPage({String? categoryId, AppUser? currentUser}) async {
    if (isLoading) return;

    isLoading = true;
    errorMessage = null;
    _activeCategoryId = normalizeCategoryFilter(categoryId);
    _activeResolvedCategoryId = null;
    _lastDocument = null;
    hasMore = true;
    posts = <Post>[];
    notifyListeners();

    try {
      await _loadUserFilters(currentUser);
      _activeResolvedCategoryId = await _resolveCategoryId(_activeCategoryId);
      if (_activeCategoryId != 'all' && _activeResolvedCategoryId == null) {
        hasMore = false;
        return;
      }
      await _loadPage(
        currentUser: currentUser,
        categoryId: _activeResolvedCategoryId,
        append: false,
      );
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadNextPage({AppUser? currentUser}) async {
    if (isLoading || isLoadingMore || !hasMore || _lastDocument == null) {
      return;
    }

    isLoadingMore = true;
    errorMessage = null;
    notifyListeners();

    try {
      await _loadPage(
        currentUser: currentUser,
        categoryId: _activeResolvedCategoryId,
        append: true,
      );
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isLoadingMore = false;
      notifyListeners();
    }
  }

  Future<void> refresh({String? categoryId, AppUser? currentUser}) async {
    await loadFirstPage(categoryId: categoryId, currentUser: currentUser);
  }

  Future<void> _loadPage({
    required AppUser? currentUser,
    required String? categoryId,
    required bool append,
  }) async {
    Query<Map<String, dynamic>> query = firestore
        .collection('posts')
        .orderBy('timestamp', descending: true)
        .limit(pageSize);

    if (categoryId != null && categoryId.isNotEmpty) {
      query = firestore
          .collection('posts')
          .where('categoryId', isEqualTo: categoryId)
          .orderBy('timestamp', descending: true)
          .limit(pageSize);
    }
    if (append && _lastDocument != null) {
      query = query.startAfterDocument(_lastDocument!);
    }

    final snapshot = await query.get().timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw TimeoutException('Firestore query timeout after 15 seconds'),
    );
    if (snapshot.docs.length < pageSize) hasMore = false;
    if (snapshot.docs.isEmpty) {
      hasMore = false;
      notifyListeners();
      return;
    }

    _lastDocument = snapshot.docs.last;
    final existingIds = posts.map((post) => post.id).toSet();
    final nextPosts = snapshot.docs
        .map(Post.fromFirestore)
        .where((post) => _isVisibleToUser(post, currentUser))
        .where((post) => !_excludedPostIds.contains(post.id))
        .where(
          (post) =>
              post.categoryId == null ||
              !_reducedCategoryIds.contains(post.categoryId),
        )
        .where((post) => !existingIds.contains(post.id))
        .toList();

    posts = append ? [...posts, ...nextPosts] : nextPosts;
    notifyListeners();
  }

  Future<void> _loadUserFilters(AppUser? currentUser) async {
    _excludedPostIds = <String>{};
    _reducedCategoryIds = <String>{};
    final userId = currentUser?.id.trim() ?? '';
    if (userId.isEmpty) return;

    final userSnapshot = await firestore.collection('users').doc(userId).get();
    final userData = userSnapshot.data();
    if (userData == null) return;
    _excludedPostIds.addAll(_stringList(userData['hiddenPostIds']));
    _reducedCategoryIds.addAll(
      _stringList(userData['reducedPostCategoryIds']),
    );
  }

  Future<String?> _resolveCategoryId(String? categoryId) async {
    if (categoryId == null || categoryId == 'all') return null;
    try {
      final categories = await CategoryService.fetchCategories().timeout(
        const Duration(seconds: 10),
        onTimeout: () => <CategoryModel>[],
      );
      return SettingsProvider.resolveCategoryIdForFeedMode(
        categoryId,
        categories.map((category) => category.id),
      );
    } catch (e) {
      return null;
    }
  }

  static String normalizeCategoryFilter(String? categoryId) {
    return SettingsProvider.normalizeFeedMode(categoryId);
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

}
