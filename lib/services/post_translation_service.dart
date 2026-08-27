import 'dart:convert';

import 'package:http/http.dart' as http;

class PostTranslationService {
  static const _supportedLanguages = {'ar', 'en', 'es', 'fr', 'tr'};
  static final Map<String, String?> _cache = <String, String?>{};
  static final Map<String, Future<String?>> _inFlight =
      <String, Future<String?>>{};

  Future<String?> translateIfNeeded({
    required String postId,
    required String text,
    required String targetLanguage,
  }) {
    final normalizedText = text.trim();
    final normalizedTarget = targetLanguage.trim().toLowerCase();
    if (normalizedText.isEmpty ||
        !_supportedLanguages.contains(normalizedTarget)) {
      return Future<String?>.value(null);
    }

    final requestKey = '$postId|$normalizedTarget|$normalizedText';
    if (_cache.containsKey(requestKey)) {
      return Future<String?>.value(_cache[requestKey]);
    }
    final existingRequest = _inFlight[requestKey];
    if (existingRequest != null) return existingRequest;

    final request = _translate(normalizedText, normalizedTarget).then((result) {
      _cache[requestKey] = result;
      return result;
    });
    _inFlight[requestKey] = request;
    request.whenComplete(() => _inFlight.remove(requestKey));
    return request;
  }

  Future<String?> _translate(String text, String targetLanguage) async {
    final uri = Uri.https('translate.googleapis.com', '/translate_a/single', {
      'client': 'gtx',
      'sl': 'auto',
      'tl': targetLanguage,
      'dt': 't',
      'q': text,
    });

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;

      final payload = jsonDecode(response.body);
      if (payload is! List || payload.length < 3) return null;
      final sourceLanguage = payload[2]?.toString().toLowerCase();
      if (sourceLanguage == targetLanguage) return null;

      final translatedParts = <String>[];
      final segments = payload[0];
      if (segments is! List) return null;
      for (final segment in segments) {
        if (segment is List && segment.isNotEmpty && segment[0] is String) {
          translatedParts.add(segment[0] as String);
        }
      }
      final translation = translatedParts.join().trim();
      return translation.isEmpty || translation == text ? null : translation;
    } catch (_) {
      return null;
    }
  }
}
