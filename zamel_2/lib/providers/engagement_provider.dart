import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EngagementProvider extends ChangeNotifier {
  int _streak = 0;
  int _points = 0;
  int _completedChallenges = 0;
  bool _todayChallengeCompleted = false;
  String _lastActiveDate = '';
  final List<String> _achievements = <String>[];

  int get streak => _streak;
  int get points => _points;
  int get completedChallenges => _completedChallenges;
  bool get todayChallengeCompleted => _todayChallengeCompleted;
  List<String> get achievements => List.unmodifiable(_achievements);

  EngagementProvider() {
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = _dateKey(DateTime.now());
      _streak = prefs.getInt('engagement_streak') ?? 0;
      _points = prefs.getInt('engagement_points') ?? 0;
      _completedChallenges = prefs.getInt('engagement_completedChallenges') ?? 0;
      _lastActiveDate = prefs.getString('engagement_lastActiveDate') ?? '';
      _todayChallengeCompleted = prefs.getBool('engagement_todayChallengeCompleted') ?? false;
      _achievements.addAll(prefs.getStringList('engagement_achievements') ?? const <String>[]);

      if (_lastActiveDate != today) {
        _todayChallengeCompleted = false;
      }
    } catch (_) {
      _streak = 0;
      _points = 0;
      _completedChallenges = 0;
      _todayChallengeCompleted = false;
      _lastActiveDate = '';
      _achievements.clear();
    }
    notifyListeners();
  }

  Future<void> completeDailyChallenge() async {
    final today = _dateKey(DateTime.now());
    if (_todayChallengeCompleted && _lastActiveDate == today) {
      return;
    }

    final yesterday = _dateKey(DateTime.now().subtract(const Duration(days: 1)));
    if (_lastActiveDate == yesterday) {
      _streak += 1;
    } else if (_lastActiveDate != today) {
      _streak = 1;
    }

    _points += 50;
    _completedChallenges += 1;
    _todayChallengeCompleted = true;
    _lastActiveDate = today;

    if (_points >= 200 && !_achievements.contains('محترف التفاعل')) {
      _achievements.add('محترف التفاعل');
    }
    if (_streak >= 7 && !_achievements.contains('سلسلة أسبوعية')) {
      _achievements.add('سلسلة أسبوعية');
    }

    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('engagement_streak', _streak);
      await prefs.setInt('engagement_points', _points);
      await prefs.setInt('engagement_completedChallenges', _completedChallenges);
      await prefs.setString('engagement_lastActiveDate', _lastActiveDate);
      await prefs.setBool('engagement_todayChallengeCompleted', _todayChallengeCompleted);
      await prefs.setStringList('engagement_achievements', _achievements);
    } catch (_) {}
  }

  String get challengeText {
    if (_todayChallengeCompleted) {
      return 'تم إكمال تحدي اليوم بنجاح';
    }
    return 'تحدي اليوم: شارك منشورًا أو ردًا جديدًا';
  }

  String get progressText {
    final percent = (_points / 200).clamp(0.0, 1.0);
    return '${(percent * 100).round()}% للوصول إلى المكافأة التالية';
  }

  String _dateKey(DateTime value) {
    return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  }
}
