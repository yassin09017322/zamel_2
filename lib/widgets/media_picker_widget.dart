import '../src/file_io_stub.dart' if (dart.library.io) 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class MediaPickerWidget extends StatefulWidget {
  final Future<void> Function(File file, String mediaType) onPicked;

  const MediaPickerWidget({super.key, required this.onPicked});

  @override
  State<MediaPickerWidget> createState() => _MediaPickerWidgetState();
}

class _MediaPickerWidgetState extends State<MediaPickerWidget> {
  final ImagePicker _picker = ImagePicker();
  String _mediaType = 'image';
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _mediaType,
                items: const [
                  DropdownMenuItem(value: 'image', child: Text('صورة من الجهاز')),
                  DropdownMenuItem(value: 'video', child: Text('فيديو من الجهاز')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _mediaType = value);
                },
                decoration: const InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
                ),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              icon: const Icon(Icons.file_upload),
              label: const Text('اختر'),
              onPressed: _isLoading ? null : _pickMedia,
            ),
          ],
        ),
        if (_isLoading) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
      ],
    );
  }

  Future<void> _pickMedia() async {
    setState(() => _isLoading = true);
    try {
      final XFile? picked;
      if (_mediaType == 'video') {
        picked = await _picker.pickVideo(source: ImageSource.gallery);
      } else {
        picked = await _picker.pickImage(source: ImageSource.gallery);
      }
      if (picked == null) return;
      await widget.onPicked(File(picked.path), _mediaType);
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فشل اختيار الوسائط')));
    } finally {
      setState(() => _isLoading = false);
    }
  }
}
