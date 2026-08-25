import 'package:isar/isar.dart';

part 'story_local_cache.g.dart';

@Collection()
class StoryLocalCache {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  String storyId = '';

  String ownerId = '';
  String username = '';
  String mediaType = '';
  String localFilePath = '';
  String remoteUrl = '';
  DateTime publishedAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime expiresAt = DateTime.fromMillisecondsSinceEpoch(0);
  int durationHours = 24;
  String? originalStoryId;
  DateTime originalTimestamp = DateTime.fromMillisecondsSinceEpoch(0);
  String text = '';
}
