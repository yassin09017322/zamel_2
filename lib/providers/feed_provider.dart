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
    debugPrint('🟠 PROVIDER: loadFirstPage() START - categoryId=$categoryId, userId=${currentUser?.id}');
    if (isLoading) {
      debugPrint('🟠 PROVIDER: Already loading, returning early');
      return;
    }

    isLoading = true;
    errorMessage = null;
    _activeCategoryId = normalizeCategoryFilter(categoryId);
    _activeResolvedCategoryId = null;
    _lastDocument = null;
    hasMore = true;
    posts = <Post>[];
    debugPrint('🟠 PROVIDER: Set isLoading=true, posts.clear(), notifying...');
    notifyListeners();

    try {
      debugPrint('🟠 PROVIDER: Calling _loadUserFilters()');
      await _loadUserFilters(currentUser);
      debugPrint('🟠 PROVIDER: _loadUserFilters() complete');
      
      debugPrint('🟠 PROVIDER: Calling _resolveCategoryId()');
      _activeResolvedCategoryId = await _resolveCategoryId(_activeCategoryId);
      debugPrint('🟠 PROVIDER: _resolveCategoryId() complete, resolved=$_activeResolvedCategoryId');
      
      if (_activeCategoryId != 'all' && _activeResolvedCategoryId == null) {
        debugPrint('🟠 PROVIDER: Category not found, setting hasMore=false');
        hasMore = false;
        return;
      }
      
      debugPrint('🟠 PROVIDER: Calling _loadPage()');
      await _loadPage(
        currentUser: currentUser,
        categoryId: _activeResolvedCategoryId,
        append: false,
      );
      debugPrint('🟠 PROVIDER: _loadPage() complete, posts.length=${posts.length}');
    } catch (error) {
      debugPrint('🟠 PROVIDER: CAUGHT ERROR: $error');
      errorMessage = error.toString();
    } finally {
      isLoading = false;
      debugPrint('🟠 PROVIDER: loadFirstPage() FINALLY - setting isLoading=false, posts.length=${posts.length}');
      notifyListeners();
      debugPrint('🟠 PROVIDER: loadFirstPage() END');
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
    debugPrint('🟡 LOADPAGE: START - categoryId=$categoryId, append=$append, _lastDocument=${_lastDocument != null}');
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

    debugPrint('🟡 LOADPAGE: Firestore query built, executing...');
    final snapshot = await query.get().timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw TimeoutException('Firestore query timeout after 15 seconds'),
    );
    debugPrint('🟡 LOADPAGE: Firestore returned ${snapshot.docs.length} documents');
    
    if (snapshot.docs.length < pageSize) hasMore = false;
    if (snapshot.docs.isEmpty) {
      debugPrint('🟡 LOADPAGE: No documents, setting hasMore=false');
      hasMore = false;
      notifyListeners();
      return;
    }

    _lastDocument = snapshot.docs.last;
    final existingIds = posts.map((post) => post.id).toSet();
    debugPrint('🟡 LOADPAGE: Parsing ${snapshot.docs.length} documents...');
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

    debugPrint('🟡 LOADPAGE: Parsed and filtered to ${nextPosts.length} posts');
    posts = append ? [...posts, ...nextPosts] : nextPosts;
    debugPrint('🟡 LOADPAGE: Total posts now: ${posts.length}, notifying...');
    notifyListeners();
    debugPrint('🟡 LOADPAGE: END');
  }

  Future<void> _loadUserFilters(AppUser? currentUser) async {
    _excludedPostIds = <String>{};
    _reducedCategoryIds = <String>{};
    final userId = currentUser?.id.trim() ?? '';
    if (userId.isEmpty) return;

    try {
      final userSnapshot = await firestore
          .collection('users')
          .doc(userId)
          .get()
          .timeout(const Duration(seconds: 10));
      final userData = userSnapshot.data();
      if (userData == null) return;
      _excludedPostIds.addAll(_stringList(userData['hiddenPostIds']));
      _reducedCategoryIds.addAll(
        _stringList(userData['reducedPostCategoryIds']),
      );
    } catch (error) {
      debugPrint('Feed user filters unavailable: $error');
      _excludedPostIds = <String>{};
      _reducedCategoryIds = <String>{};
    }
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
