import 'package:flutter_test/flutter_test.dart';
import 'package:zamel_appp/providers/feed_provider.dart';
import 'package:zamel_appp/providers/settings_provider.dart';
import 'package:zamel_appp/services/post_service.dart';

void main() {
  group('PostService media payload normalization', () {
    test('keeps legacy fallback while preserving multiple media files', () {
      final payload = PostService.buildMediaPayload(
        mediaType: 'image',
        mediaData: 'https://example.com/legacy.jpg',
        mediaFiles: [
          {'mediaType': 'image', 'url': 'https://example.com/1.jpg'},
          {'mediaType': 'video', 'url': 'https://example.com/clip.mp4'},
        ],
      );

      expect(payload['mediaType'], 'image');
      expect(payload['mediaData'], 'https://example.com/legacy.jpg');
      expect(payload['mediaFiles'], isA<List>());
      expect((payload['mediaFiles'] as List).length, 2);
      expect((payload['mediaFiles'] as List).first['mediaType'], 'image');
      expect((payload['mediaFiles'] as List).last['mediaType'], 'video');
    });

    test('normalizes app mode aliases to the same feed/category values', () {
      expect(SettingsProvider.normalizeFeedMode('general'), 'all');
      expect(SettingsProvider.normalizeFeedMode('sport'), 'sports');
      expect(SettingsProvider.normalizeFeedMode('study'), 'study');
      expect(SettingsProvider.normalizeFeedMode('culture'), 'culture');
      expect(SettingsProvider.normalizeFeedMode('entertainment'), 'entertainment');
      expect(SettingsProvider.normalizeFeedMode('work'), 'work');

      expect(FeedProvider.normalizeCategoryFilter('general'), 'all');
      expect(FeedProvider.normalizeCategoryFilter('sport'), 'sports');
      expect(FeedProvider.normalizeCategoryFilter('study'), 'study');
      expect(FeedProvider.normalizeCategoryFilter('culture'), 'culture');
      expect(FeedProvider.normalizeCategoryFilter('entertainment'), 'entertainment');
      expect(FeedProvider.normalizeCategoryFilter('work'), 'work');
    });
  });
}
