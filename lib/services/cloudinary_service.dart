import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

class CloudinaryService {
  final String cloudName;
  final String uploadPreset;

  CloudinaryService({required this.cloudName, required this.uploadPreset});

  /// Upload a local File directly to Cloudinary using unsigned preset.
  Future<String> uploadFile(
    dynamic file, {
    bool isVideo = false,
    String? folder,
    String? publicId,
    String? resourceType,
  }) async {
    if (kIsWeb) throw Exception('uploadFile is not supported on web; use uploadBytes instead');

    final resolvedResourceType = resourceType ?? (isVideo ? 'video' : 'image');
    final uri = Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/$resolvedResourceType/upload');
    final request = http.MultipartRequest('POST', uri);
    request.fields['upload_preset'] = uploadPreset;
    request.fields['resource_type'] = resolvedResourceType;
    if (folder != null && folder.isNotEmpty) {
      request.fields['folder'] = folder;
    }
    if (publicId != null && publicId.isNotEmpty) {
      request.fields['public_id'] = publicId;
    }
    request.files.add(await http.MultipartFile.fromPath('file', file.path));

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Cloudinary upload failed: ${response.statusCode} ${response.body}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['secure_url'] as String;
  }

  Future<String?> uploadSticker(File imageFile) async {
    try {
      var uri = Uri.parse('https://api.cloudinary.com/v1_1/ggvpugii/image/upload');
      var request = http.MultipartRequest('POST', uri);
      
      request.fields['upload_preset'] = 'yassin_upload';
      request.files.add(await http.MultipartFile.fromPath('file', imageFile.path));

      var response = await request.send();
      
      if (response.statusCode == 200) {
        var responseData = await response.stream.bytesToString();
        var jsonResponse = json.decode(responseData);
        return jsonResponse['secure_url']; 
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Upload raw bytes (useful on web where files are provided as bytes).
  Future<String> uploadBytes(
    Uint8List bytes,
    String filename, {
    bool isVideo = false,
    String? folder,
    String? publicId,
    String? resourceType,
  }) async {
    final resolvedResourceType = resourceType ?? (isVideo ? 'video' : 'image');
    final uri = Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/$resolvedResourceType/upload');
    final request = http.MultipartRequest('POST', uri);
    request.fields['upload_preset'] = uploadPreset;
    request.fields['resource_type'] = resolvedResourceType;
    if (folder != null && folder.isNotEmpty) {
      request.fields['folder'] = folder;
    }
    if (publicId != null && publicId.isNotEmpty) {
      request.fields['public_id'] = publicId;
    }
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Cloudinary upload failed: ${response.statusCode} ${response.body}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['secure_url'] as String;
  }
}

