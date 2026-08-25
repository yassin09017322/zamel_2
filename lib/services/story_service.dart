import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/story.dart';
import 'story_local_storage_service.dart';

class StoryService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final StoryLocalStorageService _localStorage =
      StoryLocalStorageService();
  static const List<int> supportedExpireHours = [24, 48, 72];

  static DateTime calculateExpiresAt(DateTime publishedAt, int expireHours) {
    if (!supportedExpireHours.contains(expireHours)) {
      throw ArgumentError.value(expireHours, 'expireHours');
    }
    return publishedAt.toUtc().add(Duration(hours: expireHours));
  }

  Stream<List<Story>> storiesStream() {
    final query = _firestore
        .collection('stories')
        .orderBy('timestamp', descending: true);
    late StreamController<List<Story>> controller;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? subscription;
    Timer? expiryTimer;
    List<Story> stories = const [];

    void emitActiveStories() {
      final now = DateTime.now().toUtc();
      final activeStories =
          stories.where((story) => story.isActiveAt(now)).toList()
            ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      controller.add(activeStories);

      expiryTimer?.cancel();
      DateTime? nextExpiry;
      for (final story in activeStories) {
        if (nextExpiry == null || story.expiresAt.isBefore(nextExpiry)) {
          nextExpiry = story.expiresAt;
        }
      }
      if (nextExpiry != null) {
        final delay = nextExpiry.difference(now);
        expiryTimer = Timer(
          delay.isNegative ? Duration.zero : delay,
          emitActiveStories,
        );
      }
    }

    controller = StreamController<List<Story>>(
      onListen: () {
        unawaited(_localStorage.getActiveCachedStories().then((cachedStories) {
          if (cachedStories.isNotEmpty) controller.add(cachedStories);
        }));
        subscription = query.snapshots().listen((snapshot) {
          stories = snapshot.docs.map(Story.fromFirestore).toList();
          emitActiveStories();
        }, onError: (Object error, StackTrace stackTrace) async {
          final cachedStories = await _localStorage.getActiveCachedStories();
          if (cachedStories.isNotEmpty) {
            controller.add(cachedStories);
          } else {
            controller.addError(error, stackTrace);
          }
        });
      },
      onCancel: () async {
        expiryTimer?.cancel();
        await subscription?.cancel();
      },
    );
    return controller.stream;
  }

  static List<Story> filterAnnualMemories(
    Iterable<Story> stories, {
    DateTime? date,
  }) {
    final targetDate = date ?? DateTime.now();
    final memories = <String, Story>{};
    for (final story in stories) {
      if (story.isActiveAt(targetDate) || !story.isMemoryFor(targetDate)) {
        continue;
      }
      memories.putIfAbsent(story.memoryKey, () => story);
    }
    return memories.values.toList()
      ..sort((a, b) => b.originalTimestamp.compareTo(a.originalTimestamp));
  }

  Stream<List<Story>> memoriesStream(String userId) {
    return _firestore
        .collection('stories')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map(
          (snapshot) =>
              filterAnnualMemories(snapshot.docs.map(Story.fromFirestore)),
        );
  }

  static List<List<Story>> groupStoriesByUser(List<Story> stories) {
    final grouped = <String, List<Story>>{};
    for (final story in stories) {
      grouped.putIfAbsent(story.userId, () => <Story>[]).add(story);
    }

    final orderedGroups = grouped.values.toList();
    orderedGroups.sort(
      (a, b) => b.first.timestamp.compareTo(a.first.timestamp),
    );
    return orderedGroups;
  }

  Future<void> addStory({
    required String userId,
    required String username,
    required String imageUrl,
    String mediaType = 'image',
    String? text,
    int expireHours = 24,
    String? originalStoryId,
    DateTime? originalTimestamp,
  }) async {
    if (!supportedExpireHours.contains(expireHours)) {
      throw ArgumentError.value(expireHours, 'expireHours');
    }
    final publishedAt = DateTime.now().toUtc();
    final expiresAt = calculateExpiresAt(publishedAt, expireHours);

    await _firestore.collection('stories').add({
      'username': username,
      'imageUrl': imageUrl,
      'image': imageUrl,
      'text': text ?? '',
      'mediaType': mediaType,
      'timestamp': Timestamp.fromDate(publishedAt),
      'userId': userId,
      'viewers': [],
      'reactions': [],
      'replies': [],
      'isVerified': false,
      'expireHours': expireHours,
      'expiresAt': Timestamp.fromDate(expiresAt),
      if (originalStoryId != null) 'originalStoryId': originalStoryId,
      'originalTimestamp': Timestamp.fromDate(
        (originalTimestamp ?? publishedAt).toUtc(),
      ),
    });
  }

  Future<void> repostStory({
    required Story story,
    required String userId,
    required String username,
    required int expireHours,
  }) {
    return addStory(
      userId: userId,
      username: username,
      imageUrl: story.imageUrl,
      mediaType: story.mediaType,
      text: story.text,
      expireHours: expireHours,
      originalStoryId: story.memoryKey,
      originalTimestamp: story.originalTimestamp,
    );
  }

  Future<void> updateStory(String storyId, Map<String, dynamic> data) async {
    await _firestore.collection('stories').doc(storyId).update(data);
  }

  Future<void> deleteStory(String storyId) async {
    await _firestore.collection('stories').doc(storyId).delete();
  }

  Future<void> addViewer({
    required String storyId,
    required String userId,
    required String username,
  }) async {
    final docRef = _firestore.collection('stories').doc(storyId);
    final snapshot = await docRef.get();
    final expiresAt = Story.readExpiresAt(snapshot.data());
    if (expiresAt == null || !DateTime.now().toUtc().isBefore(expiresAt)) {
      return;
    }
    final viewers =
        (snapshot.data()?['viewers'] as List<dynamic>?) ?? <dynamic>[];
    final alreadySeen = viewers.any(
      (item) => item is Map && item['userId'] == userId,
    );
    if (alreadySeen) return;

    await docRef.update({
      'viewers': FieldValue.arrayUnion([
        {
          'userId': userId,
          'username': username,
          'timestamp': DateTime.now().toIso8601String(),
        },
      ]),
    });
  }

  Future<void> addReaction({
    required String storyId,
    required String userId,
    required String username,
    required String emoji,
  }) async {
    final docRef = _firestore.collection('stories').doc(storyId);
    final snapshot = await docRef.get();
    final expiresAt = Story.readExpiresAt(snapshot.data());
    if (expiresAt == null || !DateTime.now().toUtc().isBefore(expiresAt)) {
      return;
    }
    await docRef.update({
      'reactions': FieldValue.arrayUnion([
        {
          'userId': userId,
          'username': username,
          'emoji': emoji,
          'timestamp': DateTime.now().toIso8601String(),
        },
      ]),
    });
  }

  Future<void> addReply({
    required String storyId,
    required String userId,
    required String username,
    required String text,
  }) async {
    final docRef = _firestore.collection('stories').doc(storyId);
    final snapshot = await docRef.get();
    final expiresAt = Story.readExpiresAt(snapshot.data());
    if (expiresAt == null || !DateTime.now().toUtc().isBefore(expiresAt)) {
      return;
    }
    await docRef.update({
      'replies': FieldValue.arrayUnion([
        {
          'userId': userId,
          'username': username,
          'text': text,
          'timestamp': DateTime.now().toIso8601String(),
        },
      ]),
    });
  }
}
