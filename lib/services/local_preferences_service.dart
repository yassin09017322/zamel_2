import 'package:shared_preferences/shared_preferences.dart';

class LocalPreferencesService {
  static const _draftKey = 'draft_post';
  static const _savedPostsKey = 'saved_posts';

  static String _storyMemoriesKey(String userId, int year) =>
      'ignored_story_memories_${userId}_$year';

  static Future<Set<String>> getIgnoredStoryMemoryKeys(
    String userId,
    int year,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_storyMemoriesKey(userId, year)) ?? <String>[])
        .toSet();
  }

  static Future<void> ignoreStoryMemory(
    String userId,
    int year,
    String memoryKey,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _storyMemoriesKey(userId, year);
    final ignored = prefs.getStringList(key) ?? <String>[];
    if (!ignored.contains(memoryKey)) {
      await prefs.setStringList(key, [...ignored, memoryKey]);
    }
  }

  static Future<void> saveDraft({
    required String text,
    required String location,
    required String cloudUrl,
    required String mediaType,
    required bool isTemporary,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _draftKey,
      {
        'text': text,
        'location': location,
        'cloudUrl': cloudUrl,
        'mediaType': mediaType,
        'isTemporary': isTemporary.toString(),
      }.entries.map((entry) => '${entry.key}=${entry.value}').join('|'),
    );
  }

  static Future<Map<String, dynamic>?> loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_draftKey);
    if (raw == null || raw.isEmpty) return null;

    final values = <String, dynamic>{};
    for (final part in raw.split('|')) {
      final index = part.indexOf('=');
      if (index <= 0) continue;
      final key = part.substring(0, index);
      final value = part.substring(index + 1);
      values[key] = value;
    }

    return {
      'text': values['text'] ?? '',
      'location': values['location'] ?? '',
      'cloudUrl': values['cloudUrl'] ?? '',
      'mediaType': values['mediaType'] ?? 'image',
      'isTemporary': values['isTemporary'] == 'true',
    };
  }

  static Future<void> clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftKey);
  }

  static Future<void> toggleSavedPost(String postId) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_savedPostsKey) ?? <String>[];
    if (current.contains(postId)) {
      await prefs.setStringList(
        _savedPostsKey,
        current.where((id) => id != postId).toList(),
      );
    } else {
      await prefs.setStringList(_savedPostsKey, [...current, postId]);
    }
  }

  static Future<bool> isPostSaved(String postId) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_savedPostsKey) ?? <String>[];
    return current.contains(postId);
  }

  static Future<List<String>> getSavedPosts() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_savedPostsKey) ?? <String>[];
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
