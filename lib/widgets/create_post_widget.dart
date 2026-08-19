import 'package:zamel_appp/src/platform_file.dart';
import 'dart:typed_data';
import 'dart:ui';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/category_model.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../services/category_service.dart';
import '../services/media_service.dart'; // تم إضافة محرك الرفع هنا

class _SelectedPostMedia {
  final String mediaType;
  final String fileName;
  final File? file;
  final Uint8List? bytes;

  const _SelectedPostMedia({
    required this.mediaType,
    required this.fileName,
    this.file,
    this.bytes,
  });
}

class CreatePostWidget extends StatefulWidget {
  final Future<void> Function(
    String text,
    bool isTemporary,
    String location,
    String mediaType,
    String mediaData,
    dynamic localFile,
    Uint8List? webBytes,
    String? mediaFileName,
    String privacy,
    String? categoryId,
    List<Map<String, dynamic>>? mediaFiles,
  ) onPublish;

  const CreatePostWidget({super.key, required this.onPublish});

  @override
  State<CreatePostWidget> createState() => _CreatePostWidgetState();
}

class _CreatePostWidgetState extends State<CreatePostWidget> {
  final TextEditingController _textController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  
  dynamic _selectedMediaFile;
  Uint8List? _selectedMediaBytes;
  String _selectedMediaName = '';
  String _mediaType = 'none';
  final List<_SelectedPostMedia> _selectedMediaList = [];
  bool _isPublishing = false;
  bool _isUploadingMedia = false;
  double _uploadProgress = 0.0;
  String? _uploadError;
  
  // متغيرات التفاعل المباشر
  String _selectedPrivacy = 'public';
  String _feeling = '';
  String _location = '';
  String? _selectedCategory;
  bool _hasUserSelectedCategory = false;
  bool _isLoadingCategories = true;
  bool _categoriesError = false;
  List<CategoryModel> _categories = [];
  final List<String> _taggedPeople = [];

  bool get _hasSelectedMedia =>
      _selectedMediaList.isNotEmpty || _selectedMediaFile != null || _selectedMediaBytes != null;

  final Map<String, Map<String, dynamic>> _privacyOptions = {
    'public': {'icon': Icons.public},
    'friends': {'icon': Icons.group},
    'private': {'icon': Icons.lock},
  };

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_categories.isNotEmpty && !_hasUserSelectedCategory) {
      _applyModeCategoryDefault();
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<String?> _loadLastSelectedCategoryId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('last_selected_post_category');
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveLastSelectedCategoryId(String categoryId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_selected_post_category', categoryId);
    } catch (_) {}
  }

  void _applyModeCategoryDefault() {
    if (!mounted || _categories.isEmpty || _hasUserSelectedCategory) return;

    final resolvedCategory = SettingsProvider.resolveCategoryIdForFeedMode(
      context.read<SettingsProvider>().feedMode,
      _categories.map((category) => category.id),
    );

    if (resolvedCategory != null && (_selectedCategory == null || _selectedCategory!.isEmpty || _selectedCategory != resolvedCategory)) {
      setState(() {
        _selectedCategory = resolvedCategory;
      });
    }
  }

  Future<void> _restoreLastSelectedCategoryIfAvailable() async {
    if (_categories.isEmpty) return;
    final lastCategory = await _loadLastSelectedCategoryId();
    if (!mounted || lastCategory == null || lastCategory.trim().isEmpty) {
      _applyModeCategoryDefault();
      return;
    }

    final availableCategoryIds = _categories.map((category) => category.id).toSet();
    final resolved = availableCategoryIds.contains(lastCategory)
        ? lastCategory
        : SettingsProvider.resolveCategoryIdForFeedMode(lastCategory, availableCategoryIds);

    if (resolved != null && mounted) {
      setState(() {
        _selectedCategory = resolved;
        _hasUserSelectedCategory = true;
      });
      return;
    }

    _applyModeCategoryDefault();
  }

  void _syncCurrentModeToSelectedCategory() {
    if (_categories.isEmpty || _hasUserSelectedCategory) return;

    final currentFeedMode = context.read<SettingsProvider>().feedMode;
    final resolvedCategory = SettingsProvider.resolveCategoryIdForFeedMode(
      currentFeedMode,
      _categories.map((category) => category.id),
    );

    if (resolvedCategory == null || _selectedCategory == resolvedCategory) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _hasUserSelectedCategory) return;
      if (_selectedCategory != resolvedCategory) {
        setState(() {
          _selectedCategory = resolvedCategory;
        });
      }
    });
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await CategoryService.fetchCategories();
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _isLoadingCategories = false;
        _categoriesError = false;
      });
      await _restoreLastSelectedCategoryIfAvailable();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingCategories = false;
        _categoriesError = true;
      });
    }
  }

  // 1. إغلاق الكيبورد (تحسين UX احترافي)
  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
  }

  // 2. دالة فتح المعرض
  Future<void> _pickMedia() async {
    _dismissKeyboard();
    try {
      final Future<List<XFile>> pickedFilesFuture = () async {
        try {
          final files = await _picker.pickMultipleMedia();
          return files ?? const <XFile>[];
        } catch (_) {
          final single = await _picker.pickMedia(imageQuality: 80);
          return single == null ? const <XFile>[] : [single];
        }
      }();

      final files = await pickedFilesFuture;
      if (files.isEmpty) return;

      final selectedMedia = <_SelectedPostMedia>[];
      for (final pickedFile in files) {
        final lowerName = pickedFile.name.toLowerCase();
        final isVideo = lowerName.endsWith('.mp4') || lowerName.endsWith('.mov') || lowerName.endsWith('.mkv') || lowerName.endsWith('.webm') || lowerName.endsWith('.avi');
        final bool shouldUseBytesUpload = kIsWeb || pickedFile.path.isEmpty;

        if (shouldUseBytesUpload) {
          selectedMedia.add(_SelectedPostMedia(
            mediaType: isVideo ? 'video' : 'image',
            fileName: pickedFile.name,
            bytes: await pickedFile.readAsBytes(),
          ));
        } else {
          selectedMedia.add(_SelectedPostMedia(
            mediaType: isVideo ? 'video' : 'image',
            fileName: pickedFile.name,
            file: File(pickedFile.path),
          ));
        }
      }

      if (selectedMedia.isEmpty) return;

      setState(() {
        _selectedMediaList
          ..clear()
          ..addAll(selectedMedia);

        final first = selectedMedia.first;
        _selectedMediaFile = first.file;
        _selectedMediaBytes = first.bytes;
        _selectedMediaName = first.fileName;
        _mediaType = first.mediaType;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فشل فتح المعرض')));
    }
  }

  // 3. نافذة اختيار الخصوصية
  void _showPrivacySelector() {
    _dismissKeyboard();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)))),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text('who_can_see'.tr(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 12),
                ..._privacyOptions.entries.map((entry) {
                  final isSelected = _selectedPrivacy == entry.key;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isSelected ? const Color(0xFF5B6CFF).withValues(alpha: 0.1) : Colors.grey[200],
                      child: Icon(entry.value['icon'], color: isSelected ? const Color(0xFF5B6CFF) : Colors.black87),
                    ),
                    title: Text(entry.key.tr(), style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${entry.key}_desc'.tr(), style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    trailing: isSelected ? const Icon(Icons.check_circle, color: Color(0xFF5B6CFF)) : null,
                    onTap: () {
                      setState(() => _selectedPrivacy = entry.key);
                      Navigator.pop(context);
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  // 4. نافذة إضافة الشعور/النشاط
  void _showFeelingPicker() {
    _dismissKeyboard();
    final List<Map<String, String>> feelings = [
      {'emoji': '🤩', 'text': 'حماس'},
      {'emoji': '📚', 'text': 'مذاكرة'},
      {'emoji': '☕', 'text': 'روقان'},
      {'emoji': '🎉', 'text': 'احتفال'},
      {'emoji': '😴', 'text': 'إرهاق'},
      {'emoji': '🤔', 'text': 'تفكير'},
      {'emoji': '🚀', 'text': 'إنجاز'},
      {'emoji': '💪', 'text': 'تحدي'},
    ];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(child: Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)))),
                const SizedBox(height: 16),
                Text('how_are_you_feeling'.tr(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: feelings.map((f) => InkWell(
                    onTap: () {
                      setState(() => _feeling = '${f['emoji']} ${f['text']}');
                      Navigator.pop(context);
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF5B6CFF).withValues(alpha: 0.3)),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4, offset: const Offset(0, 2))],
                      ),
                      child: Text('${f['emoji']} يشعر بـ ${f['text']}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF5B6CFF))),
                    ),
                  )).toList(),
                ),
                if (_feeling.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  TextButton.icon(
                    onPressed: () {
                      setState(() => _feeling = '');
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    label: Text('remove_current_feeling'.tr(), style: const TextStyle(color: Colors.redAccent)),
                  )
                ]
              ],
            ),
          ),
        );
      },
    );
  }

  // 5. نافذة إضافة الموقع
  void _showLocationPicker() {
    _dismissKeyboard();
    String inputLocation = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 16, right: 16, top: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(child: Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)))),
                const SizedBox(height: 16),
                Text('where_are_you'.tr(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                TextField(
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'search_location_hint'.tr(),
                    prefixIcon: const Icon(Icons.location_on, color: Color(0xFF2EC7A5)),
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                  onChanged: (val) => inputLocation = val,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2EC7A5),
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    setState(() => _location = inputLocation.trim());
                    Navigator.pop(context);
                  },
                  child: Text('set_location'.tr(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  // 6. نافذة إضافة الأشخاص
  void _showTagPicker() {
    _dismissKeyboard();
    String inputPerson = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 16, right: 16, top: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(child: Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)))),
                const SizedBox(height: 16),
                Text('with_who'.tr(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                TextField(
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'tag_person_hint'.tr(),
                    prefixIcon: const Icon(Icons.person_add, color: Color(0xFFE94057)),
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                  onChanged: (val) => inputPerson = val,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE94057),
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    if (inputPerson.trim().isNotEmpty) {
                      setState(() => _taggedPeople.add(inputPerson.trim()));
                    }
                    Navigator.pop(context);
                  },
                  child: Text('add_tag'.tr(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  // 7. إضافة القوالب (هدف، تذكير، ملاحظة)
  void _addSpecialBlock(String title, String prefixIcon) {
    _dismissKeyboard();
    String inputText = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 16, right: 16, top: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(child: Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)))),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(prefixIcon, style: const TextStyle(fontSize: 24)),
                    const SizedBox(width: 8),
                    Text('${'add'.tr()} $title', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  autofocus: true,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: '${'details'.tr()} $title...',
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                  onChanged: (val) => inputText = val,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5B6CFF),
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    if (inputText.trim().isNotEmpty) {
                      setState(() {
                        final currentText = _textController.text;
                        _textController.text = '$currentText\n\n$prefixIcon $title: $inputText\n'.trimLeft();
                      });
                    }
                    Navigator.pop(ctx);
                  },
                  child: Text('insert_into_post'.tr(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<Map<String, dynamic>> _uploadSelectedMedia() async {
    final uploadedMediaFiles = <Map<String, dynamic>>[];
    String mediaUrl = '';
    final mediaService = MediaService();

    if (_selectedMediaList.isNotEmpty) {
      final totalItems = _selectedMediaList.length;

      for (int index = 0; index < totalItems; index++) {
        final item = _selectedMediaList[index];
        final String uploadedUrl;

        if (kIsWeb && item.bytes != null) {
          uploadedUrl = await mediaService.uploadBytesWithProgress(
            item.bytes!,
            item.fileName,
            isVideo: item.mediaType == 'video',
            onProgress: (progress) {
              if (!mounted) return;
              final currentWeight = (index + progress.percentComplete) / totalItems;
              setState(() {
                _uploadProgress = currentWeight.clamp(0.0, 1.0);
              });
            },
          );
        } else if (item.file != null) {
          uploadedUrl = await mediaService.uploadFileWithProgress(
            item.file!,
            isVideo: item.mediaType == 'video',
            explicitFileName: item.fileName,
            onProgress: (progress) {
              if (!mounted) return;
              final currentWeight = (index + progress.percentComplete) / totalItems;
              setState(() {
                _uploadProgress = currentWeight.clamp(0.0, 1.0);
              });
            },
          );
        } else {
          continue;
        }

        uploadedMediaFiles.add({
          'mediaType': item.mediaType,
          'url': uploadedUrl,
          'publicId': '',
          'resourceType': item.mediaType == 'video' ? 'video' : 'image',
        });

        if (mediaUrl.isEmpty) {
          mediaUrl = uploadedUrl;
        }

        if (mounted) {
          setState(() {
            _uploadProgress = ((index + 1) / totalItems).clamp(0.0, 1.0);
          });
        }
      }
    } else if (_selectedMediaFile != null || _selectedMediaBytes != null) {
      if (kIsWeb && _selectedMediaBytes != null) {
        mediaUrl = await mediaService.uploadBytesWithProgress(
          _selectedMediaBytes!,
          _selectedMediaName,
          isVideo: _mediaType == 'video',
          onProgress: (progress) {
            if (!mounted) return;
            setState(() {
              _uploadProgress = progress.percentComplete.clamp(0.0, 1.0);
            });
          },
        );
        uploadedMediaFiles.add({
          'mediaType': _mediaType,
          'url': mediaUrl,
          'publicId': '',
          'resourceType': _mediaType == 'video' ? 'video' : 'image',
        });
      } else if (_selectedMediaFile != null) {
        mediaUrl = await mediaService.uploadFileWithProgress(
          _selectedMediaFile!,
          isVideo: _mediaType == 'video',
          explicitFileName: _selectedMediaName,
          onProgress: (progress) {
            if (!mounted) return;
            setState(() {
              _uploadProgress = progress.percentComplete.clamp(0.0, 1.0);
            });
          },
        );
        uploadedMediaFiles.add({
          'mediaType': _mediaType,
          'url': mediaUrl,
          'publicId': '',
          'resourceType': _mediaType == 'video' ? 'video' : 'image',
        });
      }
    }

    return {
      'mediaFiles': uploadedMediaFiles,
      'primaryMediaUrl': mediaUrl,
    };
  }

  Future<void> _retryUploadSelectedMedia() async {
    if (_isPublishing || !_hasSelectedMedia) return;

    setState(() {
      _isUploadingMedia = true;
      _uploadProgress = 0.0;
      _uploadError = null;
    });

    try {
      await _uploadSelectedMedia();
      if (mounted) {
        setState(() {
          _isUploadingMedia = false;
          _uploadProgress = 1.0;
          _uploadError = null;
        });
      }
    } catch (e) {
      _uploadError = e.toString();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('publish_failed'.tr(args: [e.toString()]))),
        );
      }
      if (mounted) {
        setState(() {
          _isUploadingMedia = false;
        });
      }
    }
  }

  Future<void> _handlePublish() async {
    _dismissKeyboard();
    String finalText = _textController.text.trim();

    if (_feeling.isNotEmpty) {
      finalText = '🌟 أشعر بـ $_feeling\n\n$finalText';
    }
    if (_taggedPeople.isNotEmpty) {
      finalText = '$finalText\n\n👥 مع: ${_taggedPeople.join('، ')}';
    }

    if (finalText.isEmpty && !_hasSelectedMedia) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('post_required'.tr())));
      return;
    }

    final effectiveCategoryId = _selectedCategory?.trim().isNotEmpty == true
        ? _selectedCategory!
        : SettingsProvider.resolveCategoryIdForFeedMode(
            context.read<SettingsProvider>().feedMode,
            _categories.map((category) => category.id),
          ) ?? '';

    if (effectiveCategoryId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('category_required'.tr())));
      return;
    }

    if (_selectedCategory == null || _selectedCategory!.isEmpty) {
      setState(() => _selectedCategory = effectiveCategoryId);
    }

    if (_isUploadingMedia) {
      return;
    }

    setState(() {
      _isPublishing = true;
      _isUploadingMedia = _hasSelectedMedia;
      _uploadProgress = 0.0;
      _uploadError = null;
    });

    try {
      final uploadResult = await _uploadSelectedMedia();
      final uploadedMediaFiles = uploadResult['mediaFiles'] as List<Map<String, dynamic>>? ?? const <Map<String, dynamic>>[];
      final mediaUrl = (uploadResult['primaryMediaUrl'] ?? '').toString();

      if (finalText.trim().isEmpty && uploadedMediaFiles.isEmpty) {
        throw Exception('يجب إدخال نص أو اختيار وسائط قبل النشر');
      }

      await widget.onPublish(
        finalText.trim(),
        false,
        _location,
        _mediaType,
        mediaUrl,
        null,
        null,
        _selectedMediaName.isNotEmpty ? _selectedMediaName : null,
        _selectedPrivacy,
        effectiveCategoryId,
        uploadedMediaFiles.isNotEmpty ? uploadedMediaFiles : null,
      );
    } catch (e) {
      _uploadError = e.toString();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('publish_failed'.tr(args: [e.toString()]))),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPublishing = false;
          _isUploadingMedia = false;
          _uploadProgress = _uploadError == null ? 1.0 : _uploadProgress;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final user = context.watch<AuthProvider>().currentUser;
    final username = user?.username ?? 'مستخدم';
    final initial = username.isNotEmpty ? username[0].toUpperCase() : 'م';

    if (_categories.isNotEmpty && !_hasUserSelectedCategory) {
      _syncCurrentModeToSelectedCategory();
    }

    final bool canPublish =
        !_isPublishing &&
        !_isUploadingMedia &&
        _uploadError == null &&
        (_textController.text.trim().isNotEmpty || _hasSelectedMedia || _feeling.isNotEmpty || _location.isNotEmpty || _taggedPeople.isNotEmpty) &&
        _selectedCategory != null &&
        _selectedCategory!.isNotEmpty;

    final isArabic = context.locale.languageCode == 'ar';

    return Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.black87, size: 28),
            onPressed: () {
              _dismissKeyboard();
              Navigator.of(context).pop();
            },
          ),
          title: Text('post_new'.tr(), style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.more_horiz, color: Colors.black87, size: 28),
              onPressed: () {},
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- الرأس التفاعلي (الهوية) ---
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: const Color(0xFF5B6CFF),
                          child: Text(initial, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(username, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                              if (_feeling.isNotEmpty)
                                Text('يشعر بـ $_feeling', style: const TextStyle(color: Color(0xFFF27121), fontWeight: FontWeight.bold, fontSize: 13)),
                              if (_location.isNotEmpty)
                                Row(
                                  children: [
                                    const Icon(Icons.location_on, size: 14, color: Color(0xFF2EC7A5)),
                                    const SizedBox(width: 2),
                                    Text(_location, style: const TextStyle(color: Color(0xFF2EC7A5), fontWeight: FontWeight.bold, fontSize: 13)),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    
                    // --- الأزرار العلوية المستديرة التفاعلية ---
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          _buildInteractiveChip(Icons.person_add_alt_1, 'people'.tr(), _taggedPeople.isNotEmpty ? const Color(0xFFE94057) : Colors.black87, _showTagPicker),
                          const SizedBox(width: 8),
                          _buildInteractiveChip(Icons.location_on, 'location'.tr(), _location.isNotEmpty ? const Color(0xFF2EC7A5) : Colors.black87, _showLocationPicker),
                          const SizedBox(width: 8),
                          _buildInteractiveChip(Icons.emoji_emotions, 'mood_activity'.tr(), _feeling.isNotEmpty ? const Color(0xFFF27121) : Colors.black87, _showFeelingPicker),
                        ],
                      ),
                    ),
                    
                    // عرض الأشخاص المشار إليهم (Tags) بلمسة جمالية
                    if (_taggedPeople.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _taggedPeople.map((person) => Chip(
                          label: Text(person, style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.bold)),
                          backgroundColor: const Color(0xFFE94057),
                          elevation: 2,
                          shadowColor: const Color(0xFFE94057).withValues(alpha: 0.4),
                          deleteIcon: const Icon(Icons.cancel, size: 18, color: Colors.white),
                          onDeleted: () => setState(() => _taggedPeople.remove(person)),
                        )).toList(),
                      ),
                    ],
                    const SizedBox(height: 16),

                    if (_isLoadingCategories)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text('loading_categories'.tr()),
                      )
                    else if (_categoriesError)
                      Row(
                        children: [
                          Expanded(child: Text('categories_unavailable'.tr())),
                          TextButton(
                            onPressed: _loadCategories,
                            child: Text('retry_action'.tr()),
                          ),
                        ],
                      )
                    else if (_categories.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text('categories_empty'.tr()),
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('select_category'.tr(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              if (_hasUserSelectedCategory)
                                IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  tooltip: 'مسح الفئة المختارة',
                                  onPressed: () async {
                                    setState(() {
                                      _hasUserSelectedCategory = false;
                                      _selectedCategory = null;
                                    });
                                    final prefs = await SharedPreferences.getInstance();
                                    await prefs.remove('last_selected_post_category');
                                    _applyModeCategoryDefault();
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _categories.map((category) {
                              final label = category.id.tr();
                              final selected = _selectedCategory == category.id;
                              return ChoiceChip(
                                label: Text(label),
                                selected: selected,
                                selectedColor: const Color(0xFF5B6CFF),
                                labelStyle: TextStyle(
                                  color: selected ? Colors.white : Colors.black87,
                                  fontWeight: FontWeight.bold,
                                ),
                                onSelected: (_) {
                                  setState(() {
                                    _hasUserSelectedCategory = true;
                                    _selectedCategory = category.id;
                                  });
                                  _saveLastSelectedCategoryId(category.id);
                                },
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    const SizedBox(height: 16),

                    // --- مساحة الكتابة ---
                    TextField(
                      controller: _textController,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      decoration: InputDecoration(
                        hintText: 'write_prompt'.tr(),
                        hintStyle: const TextStyle(fontSize: 22, color: Colors.black38),
                        border: InputBorder.none,
                      ),
                      style: const TextStyle(fontSize: 18, height: 1.5),
                      onChanged: (val) => setState(() {}),
                    ),
                    const SizedBox(height: 16),

                    // --- المعاينة الحية للوسائط (بصمة سينمائية) ---
                    if (_isUploadingMedia || _selectedMediaFile != null || _selectedMediaBytes != null || _selectedMediaList.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_isUploadingMedia || _uploadError != null) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.cloud_upload_outlined, size: 16, color: Color(0xFF5B6CFF)),
                                const SizedBox(width: 8),
                                Text(
                                  _uploadError == null ? 'جاري رفع الوسائط...' : 'فشل رفع الوسائط',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF5B6CFF)),
                                ),
                                const Spacer(),
                                Text('${(_uploadProgress * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF5B6CFF))),
                              ],
                            ),
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              value: _uploadProgress == 0 ? null : _uploadProgress,
                              minHeight: 8,
                              borderRadius: BorderRadius.circular(12),
                              backgroundColor: const Color(0xFF5B6CFF).withAlpha(26),
                              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF5B6CFF)),
                            ),
                            if (_uploadError != null) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _uploadError!,
                                      style: const TextStyle(color: Colors.red, fontSize: 12),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: _isPublishing ? null : _retryUploadSelectedMedia,
                                    child: const Text('إعادة المحاولة'),
                                  ),
                                ],
                              ),
                            ],
                          ],
                          if (!_isUploadingMedia && _uploadError == null && (_selectedMediaFile != null || _selectedMediaBytes != null || _selectedMediaList.isNotEmpty)) ...[
                            const SizedBox(height: 12),
                            Stack(
                              children: [
                                Container(
                                  width: double.infinity,
                                  constraints: const BoxConstraints(maxHeight: 400),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 5))],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(20),
                                    child: _mediaType == 'image'
                                        ? (_selectedMediaBytes != null
                                            ? Image.memory(_selectedMediaBytes!, fit: BoxFit.cover)
                                            : Image.file(_selectedMediaFile!, fit: BoxFit.cover))
                                        : Container(
                                            height: 250,
                                            decoration: const BoxDecoration(
                                              gradient: LinearGradient(
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                                colors: [Color(0xFF1E1E1E), Color(0xFF3A3A3A)],
                                              ),
                                            ),
                                            child: const Center(
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Icon(Icons.play_circle_fill, size: 64, color: Colors.white),
                                                  SizedBox(height: 12),
                                                  Text('مقطع فيديو جاهز للنشر', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                                ],
                                              ),
                                            ),
                                          ),
                                  ),
                                ),
                                Positioned(
                                  top: 12,
                                  right: 12,
                                  child: GestureDetector(
                                    onTap: () => setState(() {
                                      _selectedMediaFile = null;
                                      _selectedMediaBytes = null;
                                      _selectedMediaName = '';
                                      _mediaType = 'none';
                                      _selectedMediaList.clear();
                                    }),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(20),
                                      child: BackdropFilter(
                                        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                                        child: Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), shape: BoxShape.circle),
                                          child: const Icon(Icons.close, color: Colors.white, size: 20),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                  ],
                ),
              ),
            ),
            
            // --- شريط الأزرار المربعة السفلية ---  
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, -5))],
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _buildSquareButton(Icons.image_outlined, 'gallery'.tr(), _pickMedia),
                    const SizedBox(width: 10),
                    _buildSquareButton(Icons.track_changes, 'goal'.tr(), () => _addSpecialBlock('goal'.tr(), '🎯')),
                    const SizedBox(width: 10),
                    _buildSquareButton(Icons.notifications_none, 'reminder'.tr(), () => _addSpecialBlock('reminder'.tr(), '🔔')),
                    const SizedBox(width: 10),
                    _buildSquareButton(Icons.description_outlined, 'note'.tr(), () => _addSpecialBlock('note'.tr(), '📝')),
                    const SizedBox(width: 10),
                    _buildSquareButton(Icons.event_note_outlined, 'daily_plan'.tr(), () => _addSpecialBlock('daily_plan'.tr(), '📅')),
                  ],
                ),
              ),
            ),
            
            Divider(height: 1, color: Colors.grey[200]),
            
            // --- الشريط السفلي (الخصوصية + زر النشر) ---
            Container(
              padding: EdgeInsets.only(left: 16, right: 16, top: 12, bottom: MediaQuery.of(context).padding.bottom > 0 ? 20 : 12),
              color: Colors.white,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  InkWell(
                    onTap: _showPrivacySelector,
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(_privacyOptions[_selectedPrivacy]!['icon'], size: 18, color: Colors.black87),
                          const SizedBox(width: 6),
                          Text(
                            _selectedPrivacy.tr(), 
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_drop_down, size: 20, color: Colors.black87),
                        ],
                      ),
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: canPublish ? const Color(0xFF5B6CFF) : Colors.grey[300],
                      foregroundColor: canPublish ? Colors.white : Colors.grey[600],
                      elevation: canPublish ? 2 : 0,
                      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: canPublish && !_isPublishing ? _handlePublish : null,
                    child: _isPublishing
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text('publish'.tr(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInteractiveChip(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: color != Colors.black87 ? color.withValues(alpha: 0.1) : Colors.transparent,
          border: Border.all(color: color != Colors.black87 ? color.withValues(alpha: 0.5) : Colors.grey.shade300),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildSquareButton(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade200),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28, color: Colors.black87),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
