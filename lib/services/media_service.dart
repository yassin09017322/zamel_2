import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:zamel_appp/src/platform_file.dart'; // مسار ملفك الخاص

/// ✅ Represents upload progress for granular tracking
class UploadProgress {
  final int uploadedBytes;
  final int totalBytes;
  final double percentComplete;
  final DateTime startedAt;
  
  UploadProgress({
    required this.uploadedBytes,
    required this.totalBytes,
    required this.percentComplete,
    required this.startedAt,
  });
  
  Duration get elapsedTime => DateTime.now().difference(startedAt);
  
  Duration? get estimatedRemainingTime {
    if (percentComplete <= 0 || uploadedBytes <= 0) return null;
    final bytesPerSecond = uploadedBytes / elapsedTime.inSeconds;
    if (bytesPerSecond <= 0) return null;
    final remainingBytes = totalBytes - uploadedBytes;
    return Duration(seconds: (remainingBytes / bytesPerSecond).ceil());
  }
}

/// ✅ Complete upload result with all metadata
class MediaUploadResult {
  final bool success;
  final String? url;
  final String? fileName;
  final String? fileId;
  final int? size;
  final String? error;
  final String? mimeType;
  final String? detectedFileType;

  const MediaUploadResult({
    required this.success,
    this.url,
    this.fileName,
    this.fileId,
    this.size,
    this.error,
    this.mimeType,
    this.detectedFileType,
  });

  factory MediaUploadResult.fromJson(Map<String, dynamic> json) {
    return MediaUploadResult(
      success: json['success'] == true || (json.containsKey('url') && json['url'] != null),
      url: json['url']?.toString(),
      fileName: json['fileName']?.toString(),
      fileId: json['fileId']?.toString(),
      size: int.tryParse(json['size']?.toString() ?? ''),
      error: json['error']?.toString(),
      mimeType: json['mimeType']?.toString(),
      detectedFileType: json['detectedFileType']?.toString(),
    );
  }
}

class MediaService {
  MediaService({String? baseUrl}) : baseUrl = baseUrl ?? 'https://zamel-2.yassin090173221.workers.dev/' {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(minutes: 5),
      receiveTimeout: const Duration(minutes: 5),
      sendTimeout: const Duration(minutes: 5),
    ));
  }

  final String baseUrl;
  late final Dio _dio;
  static const int _maxAttempts = 3; 
  static const int _maxFileSizeBytes = 500 * 1024 * 1024; 

  Stream<UploadProgress>? _progressStream;

  Future<String> uploadFileWithProgress(
    File file, {
    bool isVideo = false,
    String? explicitFileName,
    Function(UploadProgress)? onProgress,
  }) async {
    final result = await uploadFileWithResultAndProgress(
      file,
      isVideo: isVideo,
      explicitFileName: explicitFileName,
      onProgress: onProgress,
    );
    if (!result.success || (result.url ?? '').trim().isEmpty) {
      throw Exception(result.error ?? 'Upload failed');
    }
    return result.url!;
  }

  Future<MediaUploadResult> uploadFileWithResultAndProgress(
    File file, {
    bool isVideo = false,
    String? explicitFileName,
    Function(UploadProgress)? onProgress,
  }) async {
    if (kIsWeb) {
      throw Exception('uploadFile is not supported on web; use uploadBytes instead');
    }

    final dynamic ioFile = file;
    final safeFileName = _sanitizeFileName(explicitFileName ?? ioFile.path.split(RegExp(r'[\\/]+')).last);
    
    final fileType = _detectFileType(safeFileName, isVideo: isVideo);
    final mimeType = _getMimeType(safeFileName, isVideo: isVideo);

    return _uploadWithRetry(
      () async {
        if (!await ioFile.exists()) {
          return const MediaUploadResult(
            success: false,
            error: 'الملف غير موجود',
          );
        }
        
        final length = await ioFile.length();
        if (length == 0) {
          return const MediaUploadResult(
            success: false,
            error: 'الملف المختار فارغ',
          );
        }

        if (length > _maxFileSizeBytes) {
          return MediaUploadResult(
            success: false,
            error: 'حجم الملف يتجاوز الحد الأقصى (${_maxFileSizeBytes ~/ (1024 * 1024)} MB)',
          );
        }

        final response = await _dio.post(
          baseUrl,
          data: ioFile.openRead(),
          options: Options(
            headers: {
              'File-Name': safeFileName,
              'X-File-Name': safeFileName,
              'Content-Type': mimeType,
              'Content-Length': length,
              'Accept': 'application/json',
              'X-Requested-With': 'flutter',
              'X-Bz-Content-Sha1': 'do_not_verify_sha1',
              'X-File-Type': fileType, 
            },
          ),
          onSendProgress: (int sent, int total) {
            if (onProgress != null) {
              onProgress(UploadProgress(
                uploadedBytes: sent,
                totalBytes: total,
                percentComplete: total > 0 ? (sent / total).clamp(0.0, 1.0) : 0.0,
                startedAt: DateTime.now(),
              ));
            }
          },
        );
        
        final result = _parseDioResponse(response.data);
        return result.copyWith(
          mimeType: mimeType,
          detectedFileType: fileType,
        );
      },
      onProgress: onProgress,
    );
  }

  Future<String> uploadFile(
    File file, {
    bool isVideo = false,
    String? explicitFileName,
  }) async {
    final result = await uploadFileWithResult(
      file,
      isVideo: isVideo,
      explicitFileName: explicitFileName,
    );
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
    return uploadFileWithResultAndProgress(
      file,
      isVideo: isVideo,
      explicitFileName: explicitFileName,
    );
  }

  // 🔥 هنا الضربة القاضية والتصحيح المعماري الأسطوري 🔥
  Future<MediaUploadResult> uploadXFileWithResult(
    XFile file, {
    bool isVideo = false,
    Function(UploadProgress)? onProgress, // تم إضافة دعم التقدم
  }) async {
    final safeFileName = _sanitizeFileName(file.name);
    final mimeType = _getMimeType(safeFileName, isVideo: isVideo);
    final fileType = _detectFileType(safeFileName, isVideo: isVideo);

    if (kIsWeb) {
      final bytes = await file.readAsBytes();
      return uploadBytesWithResultAndProgress(
        bytes, 
        safeFileName, 
        isVideo: isVideo,
        onProgress: onProgress,
      );
    } else {
      // 🚀 استخدام XFile مباشرة كـ Stream يتخطى كل مشاكل أندرويد ويمنع الكراش
      return _uploadWithRetry(() async {
        final length = await file.length();
        
        if (length == 0) {
          return const MediaUploadResult(success: false, error: 'الملف المختار فارغ');
        }

        if (length > _maxFileSizeBytes) {
          return MediaUploadResult(
            success: false,
            error: 'حجم الملف يتجاوز الحد الأقصى (${_maxFileSizeBytes ~/ (1024 * 1024)} MB)',
          );
        }

        final response = await _dio.post(
          baseUrl,
          data: file.openRead(), // 👈 السحر هنا: قراءة الملف بأمان تام من مسار content://
          options: Options(
            headers: {
              'File-Name': safeFileName,
              'X-File-Name': safeFileName,
              'Content-Type': mimeType,
              'Content-Length': length,
              'Accept': 'application/json',
              'X-Requested-With': 'flutter',
              'X-Bz-Content-Sha1': 'do_not_verify_sha1',
              'X-File-Type': fileType,
            },
          ),
          onSendProgress: (int sent, int total) {
            if (onProgress != null) {
              onProgress(UploadProgress(
                uploadedBytes: sent,
                totalBytes: total,
                percentComplete: total > 0 ? (sent / total).clamp(0.0, 1.0) : 0.0,
                startedAt: DateTime.now(),
              ));
            }
          },
        );
        
        final result = _parseDioResponse(response.data);
        return result.copyWith(
          mimeType: mimeType,
          detectedFileType: fileType,
        );
      });
    }
  }

  Future<String> uploadBytesWithProgress(
    Uint8List bytes,
    String filename, {
    bool isVideo = false,
    Function(UploadProgress)? onProgress,
  }) async {
    final result = await uploadBytesWithResultAndProgress(
      bytes,
      filename,
      isVideo: isVideo,
      onProgress: onProgress,
    );
    if (!result.success || (result.url ?? '').trim().isEmpty) {
      throw Exception(result.error ?? 'Upload failed');
    }
    return result.url!;
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

  Future<MediaUploadResult> uploadBytesWithResultAndProgress(
    Uint8List bytes,
    String filename, {
    bool isVideo = false,
    Function(UploadProgress)? onProgress,
  }) async {
    final safeFileName = _sanitizeFileName(filename);
    final mimeType = _getMimeType(safeFileName, isVideo: isVideo);
    final fileType = _detectFileType(safeFileName, isVideo: isVideo);

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
            'X-Bz-Content-Sha1': 'do_not_verify_sha1',
            'X-File-Type': fileType,
          },
        ),
        onSendProgress: (sent, total) {
          if (onProgress != null && total > 0) {
            onProgress(UploadProgress(
              uploadedBytes: sent,
              totalBytes: total,
              percentComplete: (sent / total).clamp(0.0, 1.0),
              startedAt: DateTime.now(),
            ));
          }
        },
      );

      final result = _parseDioResponse(response.data);
      return result.copyWith(
        mimeType: mimeType,
        detectedFileType: fileType,
      );
    });
  }

  Future<MediaUploadResult> uploadBytesWithResult(
    Uint8List bytes,
    String filename, {
    bool isVideo = false,
  }) async {
    final safeFileName = _sanitizeFileName(filename);
    final mimeType = _getMimeType(safeFileName, isVideo: isVideo);
    final fileType = _detectFileType(safeFileName, isVideo: isVideo);

    return _uploadBytesWithRetry(bytes, safeFileName, mimeType, fileType);
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
    String fileType,
  ) async {
    if (bytes.isEmpty) {
      return const MediaUploadResult(
        success: false,
        error: 'The selected file is empty',
      );
    }

    if (bytes.length > _maxFileSizeBytes) {
      return MediaUploadResult(
        success: false,
        error: 'حجم الملف يتجاوز الحد الأقصى (${_maxFileSizeBytes ~/ (1024 * 1024)} MB)',
      );
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
            'X-Bz-Content-Sha1': 'do_not_verify_sha1',
            'X-File-Type': fileType, 
          },
        ),
      );
      
      final result = _parseDioResponse(response.data);
      return result.copyWith(
        mimeType: mimeType,
        detectedFileType: fileType,
      );
    });
  }

  Future<MediaUploadResult> _uploadWithRetry(
    Future<MediaUploadResult> Function() uploadTask, {
    Function(UploadProgress)? onProgress,
  }) async {
    Object? lastError;
    final startedAt = DateTime.now();
    
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        final response = await uploadTask();
        if (response.success) {
          return response;
        }
        lastError = response.error;
      } catch (error) {
        if (error is DioException) {
          final statusCode = error.response?.statusCode ?? 0;
          final errorMessage = error.response?.data?.toString() ?? error.message ?? '';
          
          if (_isRetryableError(statusCode, errorMessage)) {
            lastError = 'خطأ في الاتصال (محاولة $attempt/$_maxAttempts): $errorMessage';
          } else {
            return MediaUploadResult(
              success: false,
              error: 'خطأ غير قابل للإعادة: $errorMessage (الرمز: $statusCode)',
            );
          }
        } else {
          lastError = error;
        }
      }

      if (attempt < _maxAttempts) {
        final delayMs = 500 * (1 << (attempt - 1));
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }
    
    return MediaUploadResult(
      success: false,
      error: lastError?.toString() ?? 'فشل الرفع بعد $_maxAttempts محاولات',
    );
  }

  bool _isRetryableError(int statusCode, String errorMessage) {
    if (statusCode == 408 || statusCode == 429 || statusCode == 500 || statusCode == 502 || statusCode == 503 || statusCode == 504) {
      return true;
    }
    
    if (errorMessage.contains('timeout') || 
        errorMessage.contains('connection') || 
        errorMessage.contains('reset') ||
        errorMessage.contains('refused')) {
      return true;
    }
    
    return false;
  }

  MediaUploadResult _parseDioResponse(dynamic data) {
    try {
      final payload = data is String ? jsonDecode(data) : data;
      final parsed = MediaUploadResult.fromJson(payload);
      if (parsed.success) return parsed;
      return MediaUploadResult(
        success: false,
        error: parsed.error ?? 'السيرفر رفض عملية الرفع',
      );
    } catch (e) {
      return const MediaUploadResult(
        success: false,
        error: 'الاستجابة من السيرفر غير صالحة',
      );
    }
  }

  String _sanitizeFileName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 'upload_${DateTime.now().microsecondsSinceEpoch}';
    }
    final normalized = trimmed.replaceAll(RegExp(r'\s+'), '_');
    return normalized;
  }

  String _detectFileType(String fileName, {required bool isVideo}) {
    final lowered = fileName.toLowerCase();
    
    if (lowered.endsWith('.mp4') || lowered.endsWith('.mov') || 
        lowered.endsWith('.m4v') || lowered.endsWith('.webm') ||
        lowered.endsWith('.avi') || lowered.endsWith('.mkv') ||
        lowered.endsWith('.flv') || lowered.endsWith('.wmv') ||
        lowered.endsWith('.3gp')) {
      return 'video';
    }
    
    if (lowered.endsWith('.jpg') || lowered.endsWith('.jpeg') || 
        lowered.endsWith('.png') || lowered.endsWith('.gif') ||
        lowered.endsWith('.webp') || lowered.endsWith('.svg') ||
        lowered.endsWith('.bmp') || lowered.endsWith('.ico')) {
      return 'image';
    }
    
    if (lowered.endsWith('.mp3') || lowered.endsWith('.wav') || 
        lowered.endsWith('.m4a') || lowered.endsWith('.aac') ||
        lowered.endsWith('.flac') || lowered.endsWith('.ogg') ||
        lowered.endsWith('.wma') || lowered.endsWith('.aiff')) {
      return 'audio';
    }
    
    if (lowered.endsWith('.pdf') || lowered.endsWith('.doc') || 
        lowered.endsWith('.docx') || lowered.endsWith('.txt') ||
        lowered.endsWith('.xls') || lowered.endsWith('.xlsx') ||
        lowered.endsWith('.ppt') || lowered.endsWith('.pptx') ||
        lowered.endsWith('.csv') || lowered.endsWith('.json') ||
        lowered.endsWith('.xml') || lowered.endsWith('.html')) {
      return 'document';
    }
    
    if (lowered.endsWith('.zip') || lowered.endsWith('.rar') || 
        lowered.endsWith('.7z') || lowered.endsWith('.tar') ||
        lowered.endsWith('.gz')) {
      return 'archive';
    }
    
    if (isVideo) {
      return 'video';
    }
    
    return 'file';
  }

  String _getMimeType(String fileName, {required bool isVideo}) {
    final lowered = fileName.toLowerCase();
    
    if (lowered.endsWith('.jpg') || lowered.endsWith('.jpeg')) return 'image/jpeg';
    if (lowered.endsWith('.png')) return 'image/png';
    if (lowered.endsWith('.gif')) return 'image/gif';
    if (lowered.endsWith('.webp')) return 'image/webp';
    if (lowered.endsWith('.svg')) return 'image/svg+xml';
    if (lowered.endsWith('.bmp')) return 'image/bmp';
    if (lowered.endsWith('.ico')) return 'image/x-icon';
    
    if (lowered.endsWith('.mp4')) return 'video/mp4';
    if (lowered.endsWith('.mov')) return 'video/quicktime';
    if (lowered.endsWith('.m4v')) return 'video/x-m4v';
    if (lowered.endsWith('.webm')) return 'video/webm';
    if (lowered.endsWith('.avi')) return 'video/x-msvideo';
    if (lowered.endsWith('.mkv')) return 'video/x-matroska';
    if (lowered.endsWith('.flv')) return 'video/x-flv';
    if (lowered.endsWith('.wmv')) return 'video/x-ms-wmv';
    if (lowered.endsWith('.3gp')) return 'video/3gpp';
    
    if (lowered.endsWith('.mp3')) return 'audio/mpeg';
    if (lowered.endsWith('.wav')) return 'audio/wav';
    if (lowered.endsWith('.m4a')) return 'audio/mp4';
    if (lowered.endsWith('.aac')) return 'audio/aac';
    if (lowered.endsWith('.flac')) return 'audio/flac';
    if (lowered.endsWith('.ogg')) return 'audio/ogg';
    if (lowered.endsWith('.wma')) return 'audio/x-ms-wma';
    if (lowered.endsWith('.aiff')) return 'audio/aiff';
    
    if (lowered.endsWith('.pdf')) return 'application/pdf';
    if (lowered.endsWith('.doc')) return 'application/msword';
    if (lowered.endsWith('.docx')) return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    if (lowered.endsWith('.txt')) return 'text/plain';
    if (lowered.endsWith('.xls')) return 'application/vnd.ms-excel';
    if (lowered.endsWith('.xlsx')) return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    if (lowered.endsWith('.ppt')) return 'application/vnd.ms-powerpoint';
    if (lowered.endsWith('.pptx')) return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    if (lowered.endsWith('.csv')) return 'text/csv';
    if (lowered.endsWith('.json')) return 'application/json';
    if (lowered.endsWith('.xml')) return 'application/xml';
    if (lowered.endsWith('.html')) return 'text/html';
    
    if (lowered.endsWith('.zip')) return 'application/zip';
    if (lowered.endsWith('.rar')) return 'application/vnd.rar';
    if (lowered.endsWith('.7z')) return 'application/x-7z-compressed';
    if (lowered.endsWith('.tar')) return 'application/x-tar';
    if (lowered.endsWith('.gz')) return 'application/gzip';
    
    return 'application/octet-stream';
  }
}

extension MediaUploadResultExt on MediaUploadResult {
  MediaUploadResult copyWith({
    bool? success,
    String? url,
    String? fileName,
    String? fileId,
    int? size,
    String? error,
    String? mimeType,
    String? detectedFileType,
  }) {
    return MediaUploadResult(
      success: success ?? this.success,
      url: url ?? this.url,
      fileName: fileName ?? this.fileName,
      fileId: fileId ?? this.fileId,
      size: size ?? this.size,
      error: error ?? this.error,
      mimeType: mimeType ?? this.mimeType,
      detectedFileType: detectedFileType ?? this.detectedFileType,
    );
  }
}
