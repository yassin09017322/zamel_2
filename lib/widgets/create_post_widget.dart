import 'package:zamel_appp/src/platform_file.dart';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

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
  bool _isPublishing = false;
  
  // متغيرات التفاعل المباشر
  String _selectedPrivacy = 'public';
  String _feeling = '';
  String _location = '';
  List<String> _taggedPeople = [];

  final Map<String, Map<String, dynamic>> _privacyOptions = {
    'public': {'label': 'العامة', 'icon': Icons.public, 'desc': 'أي شخص داخل التطبيق أو خارجه'},
    'friends': {'label': 'الأصدقاء', 'icon': Icons.group, 'desc': 'أصدقاؤك على زامل فقط'},
    'private': {'label': 'أنا فقط', 'icon': Icons.lock, 'desc': 'أنت الوحيد الذي يمكنه رؤية هذا'},
  };

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  // 1. إغلاق الكيبورد (تحسين UX احترافي)
  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
  }

  // 2. دالة فتح المعرض
  Future<void> _pickMedia() async {
    _dismissKeyboard();
    try {
      final XFile? pickedFile = await _picker.pickMedia(imageQuality: 80);
      if (pickedFile != null) {
        final lowerName = pickedFile.name.toLowerCase();
        final isVideo = lowerName.endsWith('.mp4') || lowerName.endsWith('.mov') || lowerName.endsWith('.mkv') || lowerName.endsWith('.webm');

        final bool shouldUseBytesUpload = kIsWeb || pickedFile.path.isEmpty;

        if (shouldUseBytesUpload) {
          final bytes = await pickedFile.readAsBytes();
          setState(() {
            _selectedMediaFile = null;
            _selectedMediaBytes = bytes;
            _selectedMediaName = pickedFile.name;
            _mediaType = isVideo ? 'video' : 'image';
          });
        } else {
          setState(() {
            _selectedMediaFile = File(pickedFile.path);
            _selectedMediaBytes = null;
            _selectedMediaName = pickedFile.name;
            _mediaType = isVideo ? 'video' : 'image';
          });
        }
      }
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
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Text('من يمكنه رؤية منشورك؟', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 12),
                ..._privacyOptions.entries.map((entry) {
                  final isSelected = _selectedPrivacy == entry.key;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isSelected ? const Color(0xFF5B6CFF).withOpacity(0.1) : Colors.grey[200],
                      child: Icon(entry.value['icon'], color: isSelected ? const Color(0xFF5B6CFF) : Colors.black87),
                    ),
                    title: Text(entry.value['label'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(entry.value['desc'], style: TextStyle(fontSize: 12, color: Colors.grey[600])),
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
                const Text('بم تشعر الآن؟', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                        border: Border.all(color: const Color(0xFF5B6CFF).withOpacity(0.3)),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4, offset: const Offset(0, 2))],
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
                    label: const Text('إزالة الشعور الحالي', style: TextStyle(color: Colors.redAccent)),
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
                const Text('أين أنت؟', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                TextField(
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'ابحث عن موقع (مثال: الخرطوم)',
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
                  child: const Text('تحديد الموقع', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
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
                const Text('مع من أنت؟', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                TextField(
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'اكتب اسم الشخص للإشارة إليه...',
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
                  child: const Text('إضافة إشارة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
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
                    Text('إضافة $title', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  autofocus: true,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'تفاصيل الـ $title...',
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
                  child: const Text('إدراج في المنشور', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  // 8. دالة النشر النهائية المدمجة
  Future<void> _handlePublish() async {
    _dismissKeyboard();
    String finalText = _textController.text.trim();
    
    // دمج الإشارات والشعور بذكاء لضمان الحفظ
    if (_feeling.isNotEmpty) {
      finalText = '🌟 أشعر بـ $_feeling\n\n$finalText';
    }
    if (_taggedPeople.isNotEmpty) {
      finalText = '$finalText\n\n👥 مع: ${_taggedPeople.join('، ')}';
    }

    if (finalText.isEmpty && _selectedMediaFile == null && _selectedMediaBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الرجاء كتابة شيء أو إرفاق وسائط')));
      return;
    }

    setState(() => _isPublishing = true);
    try {
      await widget.onPublish(
        finalText.trim(),
        false,
        _location,
        _mediaType,
        '',
        _selectedMediaFile,
        _selectedMediaBytes,
        _selectedMediaName.isNotEmpty ? _selectedMediaName : null,
        _selectedPrivacy,
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('حدث خطأ أثناء النشر: $e')));
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final username = user?.username ?? 'مستخدم';
    final initial = username.isNotEmpty ? username[0].toUpperCase() : 'م';
    final bool canPublish = _textController.text.trim().isNotEmpty || _selectedMediaFile != null || _selectedMediaBytes != null || _feeling.isNotEmpty || _location.isNotEmpty || _taggedPeople.isNotEmpty;

    return Directionality(
      textDirection: TextDirection.rtl,
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
          title: const Text('منشور جديد', style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
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
                          _buildInteractiveChip(Icons.person_add_alt_1, 'الأشخاص', _taggedPeople.isNotEmpty ? const Color(0xFFE94057) : Colors.black87, _showTagPicker),
                          const SizedBox(width: 8),
                          _buildInteractiveChip(Icons.location_on, 'الموقع', _location.isNotEmpty ? const Color(0xFF2EC7A5) : Colors.black87, _showLocationPicker),
                          const SizedBox(width: 8),
                          _buildInteractiveChip(Icons.emoji_emotions, 'شعور/نشاط', _feeling.isNotEmpty ? const Color(0xFFF27121) : Colors.black87, _showFeelingPicker),
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
                          shadowColor: const Color(0xFFE94057).withOpacity(0.4),
                          deleteIcon: const Icon(Icons.cancel, size: 18, color: Colors.white),
                          onDeleted: () => setState(() => _taggedPeople.remove(person)),
                        )).toList(),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // --- مساحة الكتابة ---
                    TextField(
                      controller: _textController,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      decoration: const InputDecoration(
                        hintText: 'اكتب شيئاً مفيداً...',
                        hintStyle: TextStyle(fontSize: 22, color: Colors.black38),
                        border: InputBorder.none,
                      ),
                      style: const TextStyle(fontSize: 18, height: 1.5),
                      onChanged: (val) => setState(() {}),
                    ),
                    const SizedBox(height: 16),

                    // --- المعاينة الحية للوسائط (بصمة سينمائية) ---
                    if (_selectedMediaFile != null || _selectedMediaBytes != null)
                      Stack(
                        children: [
                          Container(
                            width: double.infinity,
                            constraints: const BoxConstraints(maxHeight: 400),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 5))],
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
                                  }),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), shape: BoxShape.circle),
                                    child: const Icon(Icons.close, color: Colors.white, size: 20),
                                  ),
                                ),
                              ),
                            ),
                          ),
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
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, -5))],
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _buildSquareButton(Icons.image_outlined, 'المعرض', _pickMedia),
                    const SizedBox(width: 10),
                    _buildSquareButton(Icons.track_changes, 'هدف', () => _addSpecialBlock('هدف', '🎯')),
                    const SizedBox(width: 10),
                    _buildSquareButton(Icons.notifications_none, 'تذكير', () => _addSpecialBlock('تذكير', '🔔')),
                    const SizedBox(width: 10),
                    _buildSquareButton(Icons.description_outlined, 'ملاحظة', () => _addSpecialBlock('ملاحظة', '📝')),
                    const SizedBox(width: 10),
                    _buildSquareButton(Icons.event_note_outlined, 'المخطط اليومي', () => _addSpecialBlock('مخطط اليوم', '📅')),
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
                            _privacyOptions[_selectedPrivacy]!['label'], 
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
                        : const Text('نشر', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
          color: color != Colors.black87 ? color.withOpacity(0.1) : Colors.transparent,
          border: Border.all(color: color != Colors.black87 ? color.withOpacity(0.5) : Colors.grey.shade300),
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
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))],
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
