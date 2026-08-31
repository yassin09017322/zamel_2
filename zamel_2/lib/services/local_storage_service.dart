import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LocalStorageService {
  static final LocalStorageService _instance = LocalStorageService._();
  LocalStorageService._();
  factory LocalStorageService() => _instance;

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<void> setValue(String key, Object? value) async {
    await init();
    if (value == null) {
      await _prefs?.remove(key);
      return;
    }
    if (value is String) {
      await _prefs?.setString(key, value);
      return;
    }
    final encoded = jsonEncode(value);
    await _prefs?.setString(key, encoded);
  }

  Future<T?> getValue<T>(String key) async {
    await init();
    final raw = _prefs?.getString(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded as T;
    } catch (_) {
      if (T == String) return raw as T;
      return raw as T?;
    }
  }

  Future<void> deleteValue(String key) async {
    await init();
    await _prefs?.remove(key);
  }
}
