import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:zamel_appp/src/platform_file.dart'; // مسار ملفك الخاص

class MediaUploadResult {
  final bool success;
  final String? url;
  final String? fileName;
  final String? fileId;
  final int? size;
  final String? error;

  const MediaUploadResult({
    required this.success,
    this.url,
    this.fileName,
    this.fileId,
    this.size,
    this.error,
  });

  factory MediaUploadResult.fromJson(Map<String, dynamic> json) {
    return MediaUploadResult(
      success: json['success'] == true || (json.containsKey('url') && json['url'] != null),
      url: json['url']?.toString(),
      fileName: json['fileName']?.toString(),
      fileId: json['fileId']?.toString(),
      size: int.tryParse(json['size']?.toString() ?? ''),
      error: json['error']?.toString(),
    );
  }
}

class MediaService {
  // 🔥 تم التعديل: وضعنا رابط الـ Cloudflare Worker الخاص بك مباشرة كنقطة اتصال آمنة
  // المفاتيح السرية تم إبعادها تماماً عن كود فلاتر كما طلبت
  MediaService({String? baseUrl}) : baseUrl = baseUrl ?? 'https://zamel-2.yassin090173221.workers.dev/' {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(minutes: 5),
      receiveTimeout: const Duration(minutes: 5),
      sendTimeout: const Duration(minutes: 5),
    ));
  }

  final String baseUrl;
  late final Dio _dio;
  static const int _maxAttempts = 2;

  Future<String> uploadFile(
    File file, {
    bool isVideo = false,
    String? explicitFileName,
  }) async {
    final result = await uploadFileWithResult(file, isVideo: isVideo, explicitFileName: explicitFileName);
    if (!result.success || (result.url ?? '').trim().isEmpty) {
      throw Exception(result.error ?? 'Upload failed');
    }
    return result.url!;
  }

  Future<MediaUploadResult> uploadFileWithResult(
    File file, {
    bool isVideo = false,
    String? explicitFileName,
  }) async {
    if (kIsWeb) {
      throw Exception('uploadFile is not supported on web; use uploadBytes instead');
    }

    final dynamic ioFile = file;
    final safeFileName = _sanitizeFileName(explicitFileName ?? ioFile.path.split(RegExp(r'[\\/]+')).last);
    final mimeType = _detectMimeType(safeFileName, isVideo: isVideo);

    return _uploadWithRetry(() async {
      if (!await ioFile.exists()) return const MediaUploadResult(success: false, error: 'الملف غير موجود');
      final length = await ioFile.length();
      if (length == 0) return const MediaUploadResult(success: false, error: 'الملف المختار فارغ');

      final response = await _dio.post(
        baseUrl,
        data: ioFile.openRead(), // التدفق المباشر لحل مشكلة استنزاف الذاكرة
        options: Options(
          headers: {
            'File-Name': safeFileName,
            'X-File-Name': safeFileName,
            'Content-Type': mimeType,
            'Content-Length': length,
            'Accept': 'application/json',
            'X-Requested-With': 'flutter',
            // 🔥 الضربة القاضية لمشكلة البصمة هنا 👇
            'X-Bz-Content-Sha1': 'do_not_verify_sha1',
          },
        ),
      );
      return _parseDioResponse(response.data);
    });
  }

  Future<MediaUploadResult> uploadXFileWithResult(
    XFile file, {
    bool isVideo = false,
  }) async {
    final safeFileName = _sanitizeFileName(file.name);
    final mimeType = _detectMimeType(safeFileName, isVideo: isVideo);

    if (kIsWeb) {
      final bytes = await file.readAsBytes();
      return _uploadBytesWithRetry(bytes, safeFileName, mimeType);
    } else {
      return uploadFileWithResult(File(file.path), isVideo: isVideo, explicitFileName: file.name);
    }
  }

  Future<String> uploadBytes(
    Uint8List bytes,
    String filename, {
    bool isVideo = false,
  }) async {
    final result = await uploadBytesWithResult(bytes, filename, isVideo: isVideo);
    if (!result.success || (result.url ?? '').trim().isEmpty) {
      throw Exception(result.error ?? 'Upload failed');
    }
    return result.url!;
  }

  Future<MediaUploadResult> uploadBytesWithResult(
    Uint8List bytes,
    String filename, {
    bool isVideo = false,
  }) async {
    final safeFileName = _sanitizeFileName(filename);
    final mimeType = _detectMimeType(safeFileName, isVideo: isVideo);

    return _uploadBytesWithRetry(bytes, safeFileName, mimeType);
  }

  Future<String?> uploadSticker(File imageFile) async {
    try {
      final dynamic ioFile = imageFile;
      final result = await uploadFileWithResult(
        imageFile,
        isVideo: false,
        explicitFileName: ioFile.path.split(RegExp(r'[\\/]+')).last,
      );
      return result.success ? result.url : null;
    } catch (error) {
      return null;
    }
  }

  Future<MediaUploadResult> _uploadBytesWithRetry(
    Uint8List bytes,
    String safeFileName,
    String mimeType,
  ) async {
    if (bytes.isEmpty) {
      return const MediaUploadResult(success: false, error: 'The selected file is empty');
    }

    return _uploadWithRetry(() async {
      final response = await _dio.post(
        baseUrl,
        data: Stream.fromIterable([bytes]),
        options: Options(
          headers: {
            'File-Name': safeFileName,
            'X-File-Name': safeFileName,
            'Content-Type': mimeType,
            'Content-Length': bytes.length,
            'Accept': 'application/json',
            'X-Requested-With': 'flutter',
            // 🔥 الضربة القاضية لمشكلة البصمة هنا 👇
            'X-Bz-Content-Sha1': 'do_not_verify_sha1',
          },
        ),
      );
      return _parseDioResponse(response.data);
    });
  }

  // نظام إعادة المحاولة مع تحسين التقاط الأخطاء لقراءة رد كلاودفلير الحقيقي
  Future<MediaUploadResult> _uploadWithRetry(Future<MediaUploadResult> Function() uploadTask) async {
    Object? lastError;
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        final response = await uploadTask();
        if (response.success) {
          return response;
        }
        lastError = response.error;
      } catch (error) {
        if (error is DioException) {
          // 🔥 هنا لو كلاودفلير أو باك بلز رفضوا الرفع، التطبيق حيطبع ليك السبب الحقيقي بالضبط!
          lastError = 'خطأ اتصال: ${error.message}\nالتفاصيل من السيرفر: ${error.response?.data ?? "لا يوجد تفاصيل"}';
        } else {
          lastError = error;
        }
      }

      if (attempt < _maxAttempts) {
        await Future.delayed(Duration(milliseconds: 500 * attempt));
      }
    }
    return MediaUploadResult(success: false, error: lastError?.toString() ?? 'فشل الرفع بعد عدة محاولات');
  }

  MediaUploadResult _parseDioResponse(dynamic data) {
    try {
      final payload = data is String ? jsonDecode(data) : data;
      final parsed = MediaUploadResult.fromJson(payload);
      if (parsed.success) return parsed;
      return MediaUploadResult(success: false, error: parsed.error ?? 'السيرفر رفض عملية الرفع');
    } catch (e) {
      return MediaUploadResult(success: false, error: 'الاستجابة من السيرفر غير صالحة');
    }
  }

  String _sanitizeFileName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'upload_${DateTime.now().microsecondsSinceEpoch}';
    final normalized = trimmed.replaceAll(RegExp(r'\s+'), '_');
    return normalized;
  }

  String _detectMimeType(String fileName, {required bool isVideo}) {
    final lowered = fileName.toLowerCase();
    if (isVideo) {
      if (lowered.endsWith('.mp4')) return 'video/mp4';
      if (lowered.endsWith('.mov')) return 'video/quicktime';
      if (lowered.endsWith('.m4v')) return 'video/x-m4v';
      if (lowered.endsWith('.webm')) return 'video/webm';
      return 'video/mp4';
    }

    if (lowered.endsWith('.jpg') || lowered.endsWith('.jpeg')) return 'image/jpeg';
    if (lowered.endsWith('.png')) return 'image/png';
    return 'application/octet-stream';
  }
}
