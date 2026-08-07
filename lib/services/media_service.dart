import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

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
      // تم حل الفخ هنا: نعتبر العملية ناجحة إذا رجع السيرفر رابط الفيديو
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
  MediaService({String? baseUrl}) : baseUrl = baseUrl ?? 'https://zamel-2.yassin090173221.workers.dev/';

  final String baseUrl;
  static const int _maxAttempts = 2; // قللنا المحاولات لتسريع الاستجابة
  static const Duration _timeout = Duration(seconds: 120); // زِدنا الوقت لرفع الفيديوهات براحتها

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

    final safeFileName = _sanitizeFileName(explicitFileName ?? file.path.split(Platform.pathSeparator).last);
    final mimeType = _detectMimeType(safeFileName, isVideo: isVideo);
    final bytes = await file.readAsBytes();

    return _uploadBytesWithRetry(bytes, safeFileName, mimeType);
  }

  Future<MediaUploadResult> uploadXFileWithResult(
    XFile file, {
    bool isVideo = false,
  }) async {
    final safeFileName = _sanitizeFileName(file.name);
    final mimeType = _detectMimeType(safeFileName, isVideo: isVideo);
    final bytes = await file.readAsBytes();

    return _uploadBytesWithRetry(bytes, safeFileName, mimeType);
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

  Future<MediaUploadResult> _uploadBytesWithRetry(
    Uint8List bytes,
    String safeFileName,
    String mimeType,
  ) async {
    if (bytes.isEmpty) {
      return const MediaUploadResult(success: false, error: 'The selected file is empty');
    }

    Object? lastError;
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        // الحل الجذري: إنشاء الطلب من جديد في كل محاولة بدلاً من إعادة استخدام طلب تالف
        final request = http.Request('POST', Uri.parse(baseUrl))
          ..headers['File-Name'] = safeFileName
          ..headers['Content-Type'] = mimeType
          ..headers['Content-Length'] = bytes.length.toString()
          ..headers['Accept'] = 'application/json'
          ..headers['X-Requested-With'] = 'flutter'
          ..bodyBytes = bytes;

        final response = await _sendOnce(request, bytes.length, fileName: safeFileName);
        if (response.success) {
          return response;
        }
        lastError = response.error;
      } catch (error) {
        lastError = error;
      }

      if (attempt < _maxAttempts) {
        await Future.delayed(Duration(milliseconds: 500 * attempt));
      }
    }

    return MediaUploadResult(success: false, error: lastError?.toString() ?? 'Upload failed after retries');
  }

  Future<String?> uploadSticker(File imageFile) async {
    try {
      final result = await uploadFileWithResult(imageFile, isVideo: false, explicitFileName: imageFile.path.split(Platform.pathSeparator).last);
      return result.success ? result.url : null;
    } catch (error) {
      return null;
    }
  }

  Future<MediaUploadResult> _sendOnce(
    dynamic request,
    int size, {
    required String fileName,
  }) async {
    late final http.BaseRequest baseRequest;
    if (request is http.Request) {
      baseRequest = request;
    } else if (request is http.MultipartRequest) {
      baseRequest = request;
    } else {
      throw Exception('Unsupported request type');
    }

    baseRequest.headers['X-File-Name'] = fileName;
    baseRequest.headers['X-Requested-With'] = 'flutter';
    baseRequest.headers['Accept'] = 'application/json';

    final streamedResponse = await baseRequest.send().timeout(_timeout);
    final responseBody = await streamedResponse.stream.bytesToString();

    Map<String, dynamic>? payload;
    if (responseBody.isNotEmpty) {
      try {
        payload = jsonDecode(responseBody) as Map<String, dynamic>;
      } catch (_) {
        payload = null;
      }
    }

    // تعديل ذكي: إذا كانت حالة الطلب صحيحة وتم استرجاع الرابط، نعتبره نجاح فوراً
    if (streamedResponse.statusCode >= 200 && streamedResponse.statusCode < 300) {
      final parsed = payload != null 
          ? MediaUploadResult.fromJson(payload) 
          : MediaUploadResult(success: false, error: 'Invalid worker response');
          
      if (parsed.success) {
        return parsed;
      }
      return MediaUploadResult(success: false, error: parsed.error ?? 'Worker rejected the upload');
    }

    final workerMessage = payload != null ? payload['error']?.toString() ?? payload.toString() : responseBody;
    throw Exception('Worker returned ${streamedResponse.statusCode}: $workerMessage');
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
