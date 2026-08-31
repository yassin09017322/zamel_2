import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/post.dart';
import '../models/app_user.dart'; // تم إضافة استدعاء موديل المستخدم
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
  bool hasCompletedInitialLoad = false;
  String? errorMessage;
  String? _activeCategoryId;
  String? _activeResolvedCategoryId;
  Set<String> _excludedPostIds = <String>{};
  Set<String> _reducedCategoryIds = <String>{};
  int _loadGeneration = 0;

  Future<void> loadFirstPage({
    String? categoryId,
    AppUser? currentUser,
    bool preserveExistingPosts = false,
  }) async {
    debugPrint('🟠 PROVIDER: loadFirstPage() START - categoryId=$categoryId, userId=${currentUser?.id}');
    final generation = ++_loadGeneration;
    isLoading = true;
    isLoadingMore = false;
    hasCompletedInitialLoad = false;
    errorMessage = null;
    _activeCategoryId = normalizeCategoryFilter(categoryId);
    _activeResolvedCategoryId = null;
    _lastDocument = null;
    hasMore = true;
    if (!preserveExistingPosts) {
      posts = <Post>[];
    }
    debugPrint('🟠 PROVIDER: Set isLoading=true, posts.clear(), notifying...');
    notifyListeners();

    try {
      debugPrint('🟠 PROVIDER: Calling _loadUserFilters()');
      await _loadUserFilters(currentUser, generation: generation);
      if (generation != _loadGeneration) return;
      debugPrint('🟠 PROVIDER: _loadUserFilters() complete');
      
      debugPrint('🟠 PROVIDER: Calling _resolveCategoryId()');
      final resolvedCategoryId = await _resolveCategoryId(_activeCategoryId);
      if (generation != _loadGeneration) return;
      _activeResolvedCategoryId = resolvedCategoryId;
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
        generation: generation,
      );
      debugPrint('🟠 PROVIDER: _loadPage() complete, posts.length=${posts.length}');
    } catch (error) {
      debugPrint('🟠 PROVIDER: CAUGHT ERROR: $error');
      if (generation == _loadGeneration) {
        errorMessage = error.toString();
      }
    } finally {
      if (generation == _loadGeneration) {
        isLoading = false;
        hasCompletedInitialLoad = true;
        debugPrint('🟠 PROVIDER: loadFirstPage() FINALLY - setting isLoading=false, posts.length=${posts.length}');
        notifyListeners();
      }
      debugPrint('🟠 PROVIDER: loadFirstPage() END');
    }
  }

  Future<void> loadNextPage({AppUser? currentUser}) async {
    if (isLoading || isLoadingMore || !hasMore || _lastDocument == null) {
      return;
    }

    isLoadingMore = true;
    final generation = _loadGeneration;
    errorMessage = null;
    notifyListeners();

    try {
      await _loadPage(
        currentUser: currentUser,
        categoryId: _activeResolvedCategoryId,
        append: true,
        generation: generation,
      );
    } catch (error) {
      if (generation == _loadGeneration) {
        errorMessage = error.toString();
      }
    } finally {
      if (generation == _loadGeneration) {
        isLoadingMore = false;
        notifyListeners();
      }
    }
  }

  Future<void> refresh({String? categoryId, AppUser? currentUser}) async {
    await loadFirstPage(
      categoryId: categoryId,
      currentUser: currentUser,
      preserveExistingPosts: true,
    );
  }

  Future<void> _loadPage({
    required AppUser? currentUser,
    required String? categoryId,
    required bool append,
    required int generation,
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
    if (generation != _loadGeneration) return;
    debugPrint('🟡 LOADPAGE: Firestore returned ${snapshot.docs.length} documents');
    
    if (snapshot.docs.length < pageSize) hasMore = false;
    if (snapshot.docs.isEmpty) {
      debugPrint('🟡 LOADPAGE: No documents, setting hasMore=false');
      hasMore = false;
      notifyListeners();
      return;
    }

    _lastDocument = snapshot.docs.last;
    final existingIds = append
      ? posts.map((post) => post.id).toSet()
      : <String>{};
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

  Future<void> _loadUserFilters(
    AppUser? currentUser, {
    required int generation,
  }) async {
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
        if (generation != _loadGeneration) return;
      final userData = userSnapshot.data();
      if (userData == null) return;
      _excludedPostIds.addAll(_stringList(userData['hiddenPostIds']));
      _reducedCategoryIds.addAll(
        _stringList(userData['reducedPostCategoryIds']),
      );
    } catch (error) {
      debugPrint('Feed user filters unavailable: $error');
      if (generation == _loadGeneration) {
        _excludedPostIds = <String>{};
        _reducedCategoryIds = <String>{};
      }
    }
  }

  Future<String?> _resolveCategoryId(String? categoryId) async {
    if (categoryId == null || categoryId == 'all') return null;
    final categories = await CategoryService.fetchCategories().timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException('Category query timeout'),
    );
    return SettingsProvider.resolveCategoryIdForFeedMode(
      categoryId,
      categories.map((category) => category.id),
    );
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
