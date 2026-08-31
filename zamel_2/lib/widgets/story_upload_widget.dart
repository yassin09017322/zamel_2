import 'dart:typed_data';
import '../src/file_io_stub.dart' if (dart.library.io) 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'media_picker_widget.dart';

class StoryUploadWidget extends StatefulWidget {
  final Future<void> Function({
    File? file,
    Uint8List? bytes,
    String? fileName,
    String? cloudUrl,
    required String mediaType,
  }) onUpload;

  const StoryUploadWidget({super.key, required this.onUpload});

  @override
  State<StoryUploadWidget> createState() => _StoryUploadWidgetState();
}

class _StoryUploadWidgetState extends State<StoryUploadWidget> {
  final TextEditingController _cloudUrlController = TextEditingController();
  String _cloudMediaType = 'image';
  File? _selectedFile;
  Uint8List? _selectedBytes;
  String? _selectedFileName;
  String _selectedFileType = 'image';
  bool _isUploading = false;

  @override
  void dispose() {
    _cloudUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('أضف قصة جديدة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            // تم إضافة required String لحل الخطأ الأحمر
            MediaPickerWidget(onPicked: ({file, bytes, fileName, required String mediaType}) async {
              setState(() {
                _selectedFile = file;
                _selectedBytes = bytes;
                _selectedFileName = fileName;
                _selectedFileType = mediaType;
                _cloudUrlController.clear();
              });
              return Future<void>.value();
            }),
            if (_selectedFile != null || _selectedBytes != null) ...[
              const SizedBox(height: 10),
              Text(
                'ملف محدد: ${_selectedFile != null ? _selectedFile!.path.split(RegExp(r'[\\/]+')).last : _selectedFileName ?? 'ملف'}',
                style: const TextStyle(fontSize: 13, color: Colors.blueAccent),
              ),
            ],
            const SizedBox(height: 10),
            const Text('أو استخدم رابط وسحابي', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _cloudUrlController,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                hintText: 'أدخل رابط الوسائط السحابية',
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
              ),
              onChanged: (_) {
                if (_cloudUrlController.text.isNotEmpty) {
                  setState(() {
                    _selectedFile = null;
                    _selectedBytes = null;
                    _selectedFileName = null;
                  });
                }
              },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _cloudMediaType, // تم استبدال value بـ initialValue لحل التحذير
              items: const [
                DropdownMenuItem(value: 'image', child: Text('صورة')),
                DropdownMenuItem(value: 'video', child: Text('فيديو')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _cloudMediaType = value);
              },
              decoration: const InputDecoration(
                labelText: 'نوع الوسائط للرابط السحابي',
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _isUploading ? null : _upload,
              child: _isUploading ? const CircularProgressIndicator(color: Colors.white) : const Text('رفع القصة'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _upload() async {
    final cloudUrl = _cloudUrlController.text.trim();
    if (_selectedFile == null && cloudUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الرجاء اختيار ملف أو إدخال رابط')));
      return;
    }

    setState(() => _isUploading = true);
    try {
      await widget.onUpload(
        file: _selectedFile,
        bytes: _selectedBytes,
        fileName: _selectedFileName,
        cloudUrl: _selectedFile == null ? cloudUrl : null,
        mediaType: _selectedFile != null ? _selectedFileType : _cloudMediaType,
      );
      
      // تم إضافة حماية الـ context لحل التحذيرات الزرقاء
      if (!mounted) return; 

      _cloudUrlController.clear();
      _selectedFile = null;
      _selectedBytes = null;
      _selectedFileName = null;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ تم إضافة القصة')));
    } catch (_) {
      if (!mounted) return; 
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ فشل رفع القصة')));
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }

    return Future<void>.value();
  }
}
