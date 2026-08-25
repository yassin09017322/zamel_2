import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:isar/isar.dart'; // هذا السطر الوحيد المطلوب ليتعرف المحرك على دوال findFirst

import '../models/chat_message.dart';
import 'isar_service.dart';
import '../src/platform_directory.dart';
import '../src/platform_file.dart';

class ChatMediaStorageService {
  static const String _directoryName = 'chat_media';
  static const Duration _downloadTimeout = Duration(minutes: 10);
  static final Map<String, Future<String?>> _activeDownloads = {};

  Future<String?> getExistingPath(ChatMessage message) async {
    if (kIsWeb) return null;
    final storedPath = message.localFilePath?.trim();
    if (storedPath != null && storedPath.isNotEmpty) {
      final storedFile = File(storedPath);
      if (await storedFile.exists() && await _hasContent(storedFile)) {
        return storedPath;
      }
    }

    final isar = await IsarService.init();
    if (isar == null) return null;
    final localMessage = await isar.chatMessages
        .filter()
        .firestoreIdEqualTo(message.firestoreId)
        .roomIdEqualTo(message.roomId)
        .findFirst(); // الكود الخاص بك سليم 100% بدون أي إضافات
    final localPath = localMessage?.localFilePath?.trim();
    if (localPath == null || localPath.isEmpty) return null;
    final localFile = File(localPath);
    if (!await localFile.exists() || !await _hasContent(localFile)) return null;
    return localPath;
  }

  Future<String?> saveXFile({
    required XFile source,
    required ChatMessage message,
  }) async {
    if (kIsWeb) return null;
    final bytes = await source.readAsBytes();
    return saveBytes(bytes: bytes, message: message, fileName: source.name);
  }

  Future<String?> download({required ChatMessage message}) async {
    if (kIsWeb || message.mediaUrl.trim().isEmpty) return null;
    final existingPath = await getExistingPath(message);
    if (existingPath != null) return existingPath;

    final key = '${message.roomId}/${message.firestoreId}';
    final activeDownload = _activeDownloads[key];
    if (activeDownload != null) return activeDownload;
    final downloadFuture = _downloadAndSave(message);
    _activeDownloads[key] = downloadFuture;
    try {
      return await downloadFuture;
    } finally {
      _activeDownloads.remove(key);
    }
  }

  Future<String?> _downloadAndSave(ChatMessage message) async {
    final response = await http
        .get(Uri.parse(message.mediaUrl.trim()))
        .timeout(_downloadTimeout);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        response.bodyBytes.isEmpty) {
      throw Exception('فشل تنزيل الوسائط (${response.statusCode})');
    }
    return saveBytes(
      bytes: response.bodyBytes,
      message: message,
      fileName: message.fileName.isNotEmpty
          ? message.fileName
          : _nameFromUrl(message.mediaUrl),
    );
  }

  Future<String?> saveBytes({
    required Uint8List bytes,
    required ChatMessage message,
    required String fileName,
  }) async {
    if (kIsWeb || bytes.isEmpty) return null;
    final directory = await getApplicationSupportDirectory();
    final mediaDirectory = Directory(
      '${directory.path}/$_directoryName/${_safePart(message.roomId)}',
    );
    await mediaDirectory.create(recursive: true);
    final extension = _extension(fileName, message.mediaType);
    final path =
        '${mediaDirectory.path}/${_safePart(message.firestoreId)}$extension';
    final file = File(path);
    if (!await file.exists() || !await _hasContent(file)) {
      await file.writeAsBytes(bytes);
    }
    if (!await file.exists() || !await _hasContent(file)) {
      throw Exception('تعذر حفظ الوسائط محليًا');
    }
    await _savePathToIsar(message, path);
    return path;
  }

  Future<void> _savePathToIsar(ChatMessage message, String path) async {
    final isar = await IsarService.init();
    if (isar == null) return;
    final localMessage = await isar.chatMessages
        .filter()
        .firestoreIdEqualTo(message.firestoreId)
        .roomIdEqualTo(message.roomId)
        .findFirst(); // الكود الخاص بك سليم 100%
    final messageToSave = localMessage ?? message;
    messageToSave.localFilePath = path;
    await isar.writeTxn(() async {
      await isar.chatMessages.put(messageToSave);
    });
  }

  Future<bool> _hasContent(File file) async {
    return (await file.length()) > 0;
  }

  String _extension(String fileName, String mediaType) {
    final name = fileName.trim();
    final dot = name.lastIndexOf('.');
    if (dot >= 0 && dot < name.length - 1) {
      return name.substring(dot).toLowerCase();
    }
    if (mediaType == ChatMessageType.image) return '.jpg';
    if (mediaType == ChatMessageType.video) return '.mp4';
    if (mediaType == ChatMessageType.audio) return '.m4a';
    return '.bin';
  }

  String _nameFromUrl(String url) {
    final path = Uri.tryParse(url)?.path ?? '';
    final name = path.split('/').last;
    return name.isEmpty ? 'media' : name;
  }

  String _safePart(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty
        ? 'unknown'
        : trimmed.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  }
}
