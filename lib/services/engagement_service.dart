import 'package:shared_preferences/shared_preferences.dart';

class EngagementService {
  static const _streakKey = 'engagement_streak';
  static const _lastActiveKey = 'engagement_last_active';
  static const _activityCountKey = 'engagement_activity_count';

  static Future<Map<String, dynamic>> recordActivity() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final lastActive = prefs.getString(_lastActiveKey);
    var streak = prefs.getInt(_streakKey) ?? 0;
    var activityCount = prefs.getInt(_activityCountKey) ?? 0;

    if (lastActive != null) {
      final lastDate = DateTime.parse(lastActive);
      final difference = now.difference(lastDate).inDays;
      if (difference == 1) {
        streak += 1;
      } else if (difference > 1) {
        streak = 1;
      }
    } else {
      streak = 1;
    }

    activityCount += 1;
    await prefs.setInt(_streakKey, streak);
    await prefs.setString(_lastActiveKey, now.toIso8601String());
    await prefs.setInt(_activityCountKey, activityCount);

    return getSummary();
  }

  static Future<Map<String, dynamic>> getSummary() async {
    final prefs = await SharedPreferences.getInstance();
    final streak = prefs.getInt(_streakKey) ?? 0;
    final activityCount = prefs.getInt(_activityCountKey) ?? 0;
    final achievementLabel = streak >= 7
        ? '🔥 سلسلة قوية'
        : streak >= 3
            ? '⭐ نشط بانتظام'
            : '🌱 يبدأ الآن';

    return {
      'streak': streak,
      'activityCount': activityCount,
      'achievementLabel': achievementLabel,
    };
  }

  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_streakKey);
    await prefs.remove(_lastActiveKey);
    await prefs.remove(_activityCountKey);
  }
}
