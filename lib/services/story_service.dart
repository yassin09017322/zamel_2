import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/story.dart';

class StoryService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<Story>> storiesStream() {
    final query = _firestore.collection('stories').orderBy('timestamp', descending: true);
    return query.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => Story.fromFirestore(doc)).toList();
    });
  }

  static List<List<Story>> groupStoriesByUser(List<Story> stories) {
    final grouped = <String, List<Story>>{};
    for (final story in stories) {
      grouped.putIfAbsent(story.userId, () => <Story>[]).add(story);
    }

    final orderedGroups = grouped.values.toList();
    orderedGroups.sort((a, b) => b.first.timestamp.compareTo(a.first.timestamp));
    return orderedGroups;
  }

  Future<void> addStory({
    required String userId,
    required String username,
    required String imageUrl,
    String mediaType = 'image',
    int expireHours = 24,
  }) async {
    final expiresAt = DateTime.now().add(Duration(hours: expireHours));

    await _firestore.collection('stories').add({
      'username': username,
      'imageUrl': imageUrl,
      'image': imageUrl,
      'mediaType': mediaType,
      'timestamp': FieldValue.serverTimestamp(),
      'userId': userId,
      'viewers': [],
      'reactions': [],
      'replies': [],
      'isVerified': false,
      'expireHours': expireHours,
      'expiresAt': Timestamp.fromDate(expiresAt),
    });
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
    final viewers = (snapshot.data()?['viewers'] as List<dynamic>?) ?? <dynamic>[];
    final alreadySeen = viewers.any((item) => item is Map && item['userId'] == userId);
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
