import 'dart:typed_data';
import 'package:zamel_appp/src/platform_file.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/media_service.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _usernameController = TextEditingController();
  final _bioController = TextEditingController();
  final _locationController = TextEditingController();
  final _workController = TextEditingController();
  final _hobbyController = TextEditingController();
  
  // تم تعريف أداة اختيار الصور هنا
  final ImagePicker _picker = ImagePicker(); 
  
  bool _isSaving = false;
  dynamic _photoFile;
  
  // تم تصحيح الخطأ المطبعي هنا
  Uint8List? _photoBytes; 

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().currentUser;
    if (user != null) {
      _usernameController.text = user.username;
      _bioController.text = user.bio;
      _locationController.text = user.location;
      _workController.text = user.work;
      _hobbyController.text = user.hobby;
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _bioController.dispose();
    _locationController.dispose();
    _workController.dispose();
    _hobbyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('الرجاء تسجيل الدخول')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('تعديل الملف الشخصي')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_photoBytes != null)
              CircleAvatar(radius: 50, backgroundImage: MemoryImage(_photoBytes!))
            else if (_photoFile != null && !kIsWeb)
              CircleAvatar(radius: 50, backgroundImage: FileImage(_photoFile as dynamic))
            else if (user.photoURL?.isNotEmpty == true)
              CircleAvatar(radius: 50, backgroundImage: NetworkImage(user.photoURL!))
            else
              CircleAvatar(radius: 50, child: Text(user.username.isNotEmpty ? user.username[0] : 'م', style: const TextStyle(fontSize: 32))),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('تغيير الصورة'),
              onPressed: _pickPhoto,
            ),
            const SizedBox(height: 24),
            _buildTextField(controller: _usernameController, label: 'اسم المستخدم'),
            const SizedBox(height: 12),
            _buildTextField(controller: _bioController, label: 'نبذة', maxLines: 3),
            const SizedBox(height: 12),
            _buildTextField(controller: _locationController, label: 'مكان السكن'),
            const SizedBox(height: 12),
            _buildTextField(controller: _workController, label: 'مكان العمل'),
            const SizedBox(height: 12),
            _buildTextField(controller: _hobbyController, label: 'الهواية'),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isSaving ? null : _saveProfile,
              child: _isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text('حفظ التغييرات'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
      ),
    );
  }

  Future<void> _pickPhoto() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    if (kIsWeb) {
      _photoBytes = await picked.readAsBytes();
      _photoFile = null;
    } else {
      _photoFile = File(picked.path);
      _photoBytes = null;
    }

    if (mounted) setState(() {});
  }

  Future<void> _saveProfile() async {
    final authProvider = context.read<AuthProvider>();
    setState(() => _isSaving = true);

    String? photoUrl;
    if (_photoBytes != null) {
      try {
        final mediaService = MediaService();
        photoUrl = await mediaService.uploadBytes(_photoBytes!, 'profile_photo.png', isVideo: false);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فشل رفع صورة الملف الشخصي')));
        }
      }
    } else if (_photoFile != null) {
      try {
        final mediaService = MediaService();
        photoUrl = await mediaService.uploadFile(_photoFile!, isVideo: false);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فشل رفع صورة الملف الشخصي')));
        }
      }
    }

    try {
      await authProvider.updateProfile(
        username: _usernameController.text.trim(),
        bio: _bioController.text.trim(),
        location: _locationController.text.trim(),
        work: _workController.text.trim(),
        hobby: _hobbyController.text.trim(),
        photoURL: photoUrl,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ التغييرات')));
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فشل حفظ التغييرات')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
