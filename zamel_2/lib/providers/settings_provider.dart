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
      _feedMode = prefs.getString('user_mode') ?? 'all';
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
    _feedMode = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_mode', value);
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
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (_) {}
  }
}
