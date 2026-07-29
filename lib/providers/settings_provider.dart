import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  bool _darkMode = false;
  String _languageCode = 'ar';
  bool _soundNotifications = true;
  bool _autoRefresh = true;
  bool _privateMode = false;
  bool _compactMode = false;
  bool _sharePresence = true;

  bool get darkMode => _darkMode;
  Locale get locale => Locale(_languageCode);
  bool get soundNotifications => _soundNotifications;
  bool get autoRefresh => _autoRefresh;
  bool get privateMode => _privateMode;
  bool get compactMode => _compactMode;
  bool get sharePresence => _sharePresence;

  SettingsProvider() {
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _darkMode = prefs.getBool('darkMode') ?? false;
      _languageCode = prefs.getString('languageCode') ?? 'ar';
      _soundNotifications = prefs.getBool('soundNotifications') ?? true;
      _autoRefresh = prefs.getBool('autoRefresh') ?? true;
      _privateMode = prefs.getBool('privateMode') ?? false;
      _compactMode = prefs.getBool('compactMode') ?? false;
      _sharePresence = prefs.getBool('sharePresence') ?? true;
    } catch (_) {
      _darkMode = false;
      _languageCode = 'ar';
      _soundNotifications = true;
      _autoRefresh = true;
      _privateMode = false;
      _compactMode = false;
      _sharePresence = true;
    }
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

  Future<void> resetSettings() async {
    _darkMode = false;
    _languageCode = 'ar';
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
