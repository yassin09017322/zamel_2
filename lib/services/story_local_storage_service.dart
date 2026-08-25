import 'dart:async'; // 🔥 تم إصلاح حرف الـ I الكبير
import 'dart:io' as io; // 🔥 تمت الإضافة عشان نقدر نستخدم rename و delete و flush

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:isar/isar.dart';

import '../models/story.dart';
import '../models/story_local_cache.dart';
import 'isar_service.dart';
import '../src/platform_directory.dart';
import '../src/platform_file.dart';

class StoryLocalStorageService {
  static const Duration _downloadTimeout = Duration(minutes: 10);
  static final Map<String, Future<String?>> _activeDownloads = {};

  Future<List<Story>> getActiveCachedStories() async {
    if (kIsWeb) return const <Story>[];
    final Isar? isar;
    try {
      isar = await IsarService.init();
    } catch (_) {
      return const <Story>[];
    }
    if (isar == null) return const <Story>[];
    final now = DateTime.now().toUtc();
    final caches = await isar.storyLocalCaches.where().findAll();
    final stories = <Story>[];
    for (final cache in caches) {
      if (!now.isBefore(cache.expiresAt.toUtc())) continue;
      final file = io.File(cache.localFilePath); // 🔥 استخدام io.File
      if (!await file.exists() || await file.length() <= 0) continue;
      stories.add(
        Story(
          id: cache.storyId,
          userId: cache.ownerId,
          username: cache.username,
          imageUrl: cache.remoteUrl,
          text: cache.text,
          mediaType: cache.mediaType,
          timestamp: cache.publishedAt.toUtc(),
          expiresAt: cache.expiresAt.toUtc(),
          expireHours: cache.durationHours,
          originalStoryId: cache.originalStoryId,
          originalTimestamp: cache.originalTimestamp.toUtc(),
        ),
      );
    }
    return stories;
  }

  Future<String?> getLocalPath(Story story) async {
    if (kIsWeb || !story.isActiveAt(DateTime.now().toUtc())) return null;
    final isar = await IsarService.init();
    if (isar == null) return null;
    final cache = await isar.storyLocalCaches
        .filter()
        .storyIdEqualTo(story.id)
        .build() // 🔥 إضافة build() عشان دالة findFirst تشتغل بدون أخطاء
        .findFirst();
    if (cache == null || cache.expiresAt.toUtc() != story.expiresAt.toUtc()) {
      return null;
    }
    final file = io.File(cache.localFilePath); // 🔥 استخدام io.File
    if (!await file.exists() || await file.length() <= 0) return null;
    return cache.localFilePath;
  }

  Future<String?> ensureLocalPath(Story story) async {
    final localPath = await getLocalPath(story);
    if (localPath != null) return localPath;
    if (kIsWeb || story.imageUrl.trim().isEmpty) return null;

    final activeDownload = _activeDownloads[story.id];
    if (activeDownload != null) return activeDownload;
    final download = _downloadAndCache(story);
    _activeDownloads[story.id] = download;
    try {
      return await download;
    } finally {
      _activeDownloads.remove(story.id);
    }
  }

  Future<String?> _downloadAndCache(Story story) async {
    final response = await http
        .get(Uri.parse(story.imageUrl.trim()))
        .timeout(_downloadTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    final bytes = response.bodyBytes;
    if (bytes.isEmpty || !story.isActiveAt(DateTime.now().toUtc())) return null;

    final directory = await getApplicationSupportDirectory();
    final mediaDirectory = io.Directory('${directory.path}/story_media'); // 🔥 استخدام io.Directory
    await mediaDirectory.create(recursive: true);
    final extension = _extension(story.imageUrl, story.mediaType);
    final path =
        '${mediaDirectory.path}/story_${_safePart(story.id)}$extension';
    final file = io.File(path); // 🔥 استخدام io.File ليدعم الحذف
    final temporaryFile = io.File('$path.download'); // 🔥 استخدام io.File ليدعم تغيير الاسم والحفظ العميق
    await temporaryFile.writeAsBytes(bytes, flush: true);
    if (!await temporaryFile.exists() ||
        await temporaryFile.length() != bytes.length) {
      if (await temporaryFile.exists()) await temporaryFile.delete();
      return null;
    }
    if (await file.exists()) await file.delete();
    await temporaryFile.rename(path);
    if (!await file.exists() || await file.length() <= 0) return null;

    final isar = await IsarService.init();
    if (isar == null) return path;
    final cache = StoryLocalCache()
      ..storyId = story.id
      ..ownerId = story.userId
      ..username = story.username
      ..mediaType = story.mediaType
      ..localFilePath = path
      ..remoteUrl = story.imageUrl
      ..publishedAt = story.timestamp.toUtc()
      ..expiresAt = story.expiresAt.toUtc()
      ..durationHours = story.expireHours
      ..originalStoryId = story.originalStoryId
      ..originalTimestamp = story.originalTimestamp.toUtc()
      ..text = story.text;
    await isar.writeTxn(() async {
      await isar.storyLocalCaches.put(cache);
    });
    return path;
  }

  String _extension(String url, String mediaType) {
    final path = Uri.tryParse(url)?.path ?? '';
    final dot = path.lastIndexOf('.');
    if (dot >= 0 && dot < path.length - 1) {
      final extension = path.substring(dot).toLowerCase();
      if (extension.length <= 8) return extension;
    }
    if (mediaType == 'video') return '.mp4';
    return '.jpg';
  }

  String _safePart(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
}
