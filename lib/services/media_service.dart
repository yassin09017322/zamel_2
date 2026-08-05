import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

class MediaService {
  final String baseUrl = 'https://zamel-2.yassin090173221.workers.dev/';

  Future<String> uploadFile(
    dynamic file, {
    bool isVideo = false,
  }) async {
    if (kIsWeb) throw Exception('uploadFile is not supported on web; use uploadBytes instead');

    final uri = Uri.parse(baseUrl);
    final fileName = file.path.split('/').last;
    
    final request = http.Request('POST', uri)
      ..headers['File-Name'] = fileName
      ..bodyBytes = await file.readAsBytes();

    final response = await http.Response.fromStream(await request.send());
    if (response.statusCode != 200) {
      throw Exception('Upload failed: ${response.statusCode}');
    }
    
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['url'] as String;
  }

  Future<String?> uploadSticker(File imageFile) async {
    try {
      final uri = Uri.parse(baseUrl);
      final fileName = imageFile.path.split('/').last;
      
      final request = http.Request('POST', uri)
        ..headers['File-Name'] = fileName
        ..bodyBytes = await imageFile.readAsBytes();

      final response = await http.Response.fromStream(await request.send());
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return body['url'] as String;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<String> uploadBytes(
    Uint8List bytes,
    String filename, {
    bool isVideo = false,
  }) async {
    final uri = Uri.parse(baseUrl);
    
    final request = http.Request('POST', uri)
      ..headers['File-Name'] = filename
      ..bodyBytes = bytes;

    final response = await http.Response.fromStream(await request.send());
    if (response.statusCode != 200) {
      throw Exception('Upload failed: ${response.statusCode}');
    }
    
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['url'] as String;
  }
}