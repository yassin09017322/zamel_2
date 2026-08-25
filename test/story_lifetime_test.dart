import 'package:flutter_test/flutter_test.dart';
import 'package:zamel_appp/models/story.dart';
import 'package:zamel_appp/services/story_service.dart';

Story _story({
  required String id,
  required DateTime timestamp,
  required DateTime expiresAt,
  String? originalStoryId,
  DateTime? originalTimestamp,
  int expireHours = 24,
}) {
  return Story(
    id: id,
    userId: 'user-1',
    username: 'User',
    imageUrl: 'https://example.com/story.jpg',
    mediaType: 'image',
    timestamp: timestamp,
    expiresAt: expiresAt,
    expireHours: expireHours,
    originalStoryId: originalStoryId,
    originalTimestamp: originalTimestamp,
  );
}

void main() {
  group('Story lifetime', () {
    test('calculates expiry from the exact published instant', () {
      final publishedAt = DateTime.utc(2026, 8, 24, 10, 30);

      expect(
        StoryService.calculateExpiresAt(publishedAt, 24),
        DateTime.utc(2026, 8, 25, 10, 30),
      );
      expect(
        StoryService.calculateExpiresAt(publishedAt, 48),
        DateTime.utc(2026, 8, 26, 10, 30),
      );
      expect(
        StoryService.calculateExpiresAt(publishedAt, 72),
        DateTime.utc(2026, 8, 27, 10, 30),
      );
    });

    test('is inactive at the exact expiry instant', () {
      final publishedAt = DateTime.utc(2026, 8, 24, 10, 30);
      final expiresAt = StoryService.calculateExpiresAt(publishedAt, 24);
      final story = _story(
        id: 'story-1',
        timestamp: publishedAt,
        expiresAt: expiresAt,
      );

      expect(
        story.isActiveAt(expiresAt.subtract(const Duration(microseconds: 1))),
        isTrue,
      );
      expect(story.isActiveAt(expiresAt), isFalse);
      expect(
        story.isActiveAt(expiresAt.add(const Duration(microseconds: 1))),
        isFalse,
      );
    });
  });

  group('Annual memories', () {
    test('matches month and day and deduplicates reposts', () {
      final originalDate = DateTime.utc(2026, 8, 24, 10, 30);
      final targetDate = DateTime.utc(2027, 8, 24, 12);
      final original = _story(
        id: 'story-1',
        timestamp: originalDate,
        expiresAt: DateTime.utc(2026, 8, 25, 10, 30),
      );
      final repost = _story(
        id: 'story-2',
        timestamp: DateTime.utc(2027, 8, 24, 9),
        expiresAt: DateTime.utc(2027, 8, 24, 10),
        originalStoryId: 'story-1',
        originalTimestamp: originalDate,
      );

      final memories = StoryService.filterAnnualMemories([
        original,
        repost,
      ], date: targetDate);

      expect(memories, hasLength(1));
      expect(memories.single.memoryKey, 'story-1');
    });

    test('handles February 29 memories in non-leap years', () {
      final originalDate = DateTime.utc(2024, 2, 29, 8);
      final story = _story(
        id: 'leap-story',
        timestamp: originalDate,
        expiresAt: DateTime.utc(2024, 3, 1, 8),
      );

      expect(story.isMemoryFor(DateTime.utc(2025, 2, 28)), isTrue);
      expect(story.isMemoryFor(DateTime.utc(2025, 3, 1)), isFalse);
    });
  });
}
