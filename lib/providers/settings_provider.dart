import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  bool _darkMode = false;
  String _languageCode = 'ar';

  bool _isInitialized = false;
  bool _soundNotifications = true;
  bool _autoRefresh = true;
  bool _privateMode = false;
  bool _compactMode = false;
  bool _sharePresence = true;
  String _feedMode = 'all';

  static const List<String> _supportedFeedModes = [
    'all',
    'general',
    'study',
    'culture',
    'sports',
    'entertainment',
    'work',
  ];

  static String normalizeFeedMode(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    if (normalized.isEmpty || normalized == 'general') return 'all';
    if (normalized == 'sport') return 'sports';
    if (normalized == 'study' || normalized == 'studies') return 'study';
    if (normalized == 'culture' || normalized == 'cultural') return 'culture';
    if (normalized == 'sports' || normalized == 'sport') return 'sports';
    if (normalized == 'fun' || normalized == 'entertainment' || normalized == 'entertain') return 'entertainment';
    if (normalized == 'work' || normalized == 'jobs' || normalized == 'career') return 'work';
    return normalized;
  }

  static String? resolveCategoryIdForFeedMode(String? feedMode, Iterable<String> availableCategoryIds) {
    final available = availableCategoryIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();

    if (available.isEmpty) return null;

    final normalizedMode = normalizeFeedMode(feedMode);
    final modeAliases = <String>{
      normalizedMode,
      if (normalizedMode == 'all') ...{'all', 'general'},
      if (normalizedMode == 'sports') ...{'sports', 'sport'},
      if (normalizedMode == 'study') ...{'study', 'studies'},
      if (normalizedMode == 'culture') ...{'culture', 'cultural'},
      if (normalizedMode == 'entertainment') ...{'entertainment', 'entertain', 'fun'},
      if (normalizedMode == 'work') ...{'work', 'jobs', 'career'},
    };

    for (final alias in modeAliases) {
      if (available.contains(alias)) return alias;
    }

    for (final category in available) {
      final categoryAlias = normalizeFeedMode(category);
      if (modeAliases.contains(categoryAlias)) {
        return category;
      }
    }

    if (normalizedMode == 'all' || normalizedMode == 'general') {
      final fallback = available.firstWhere(
        (category) => category.toLowerCase() == 'general' || category.toLowerCase() == 'all',
        orElse: () => available.first,
      );
      return fallback;
    }

    return available.first;
  }

  bool get darkMode => _darkMode;
  Locale get locale => Locale(_languageCode);
  bool get isInitialized => _isInitialized;
  bool get soundNotifications => _soundNotifications;
  bool get autoRefresh => _autoRefresh;
  bool get privateMode => _privateMode;
  bool get compactMode => _compactMode;
  bool get sharePresence => _sharePresence;
  String get feedMode => _feedMode;

  SettingsProvider() {
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _darkMode = prefs.getBool('darkMode') ?? false;
      final storedLanguageCode = prefs.getString('languageCode');
      if (storedLanguageCode != null && (storedLanguageCode == 'ar' || storedLanguageCode == 'en' || storedLanguageCode == 'fr' || storedLanguageCode == 'es')) {
        _languageCode = storedLanguageCode;
      } else {
        final deviceLocale = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
        _languageCode = switch (deviceLocale) {
          'en' => 'en',
          'fr' => 'fr',
          'es' => 'es',
          _ => 'ar',
        };
      }
      _soundNotifications = prefs.getBool('soundNotifications') ?? true;
      _autoRefresh = prefs.getBool('autoRefresh') ?? true;
      _privateMode = prefs.getBool('privateMode') ?? false;
      _compactMode = prefs.getBool('compactMode') ?? false;
      _sharePresence = prefs.getBool('sharePresence') ?? true;
      _feedMode = normalizeFeedMode(prefs.getString('user_mode'));
    } catch (_) {
      _darkMode = false;
      _languageCode = 'ar';
      _soundNotifications = true;
      _autoRefresh = true;
      _privateMode = false;
      _compactMode = false;
      _sharePresence = true;
      _feedMode = 'all';
    }
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> toggleDarkMode(bool value) async {
    _darkMode = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('darkMode', value);
    } catch (_) {}
  }

  Future<void> setLanguage(String languageCode) async {
    if (languageCode != 'ar' && languageCode != 'en' && languageCode != 'fr' && languageCode != 'es') {
      return;
    }
    _languageCode = languageCode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('languageCode', languageCode);
    } catch (_) {}
  }

  Future<void> toggleSoundNotifications(bool value) async {
    _soundNotifications = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('soundNotifications', value);
    } catch (_) {}
  }

  Future<void> toggleAutoRefresh(bool value) async {
    _autoRefresh = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('autoRefresh', value);
    } catch (_) {}
  }

  Future<void> togglePrivateMode(bool value) async {
    _privateMode = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('privateMode', value);
    } catch (_) {}
  }

  Future<void> toggleSharePresence(bool value) async {
    _sharePresence = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('sharePresence', value);
    } catch (_) {}
  }

  Future<void> toggleCompactMode(bool value) async {
    _compactMode = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('compactMode', value);
    } catch (_) {}
  }

  Future<void> setFeedMode(String value) async {
    final normalized = normalizeFeedMode(value);
    _feedMode = normalized;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_mode', normalized);
    } catch (_) {}
  }

  Future<void> clearRememberedPostCategory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_selected_post_category');
    } catch (_) {}
  }

  Future<void> resetSettings() async {
    _darkMode = false;
    _languageCode = 'ar';
    _isInitialized = true;
    _soundNotifications = true;
    _autoRefresh = true;
    _privateMode = false;
    _compactMode = false;
    _sharePresence = true;
    _feedMode = 'all';
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      await prefs.setString('user_mode', 'all');
      await prefs.remove('last_selected_post_category');
    } catch (_) {}
  }
}
