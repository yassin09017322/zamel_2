import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/channel.dart';
import '../providers/auth_provider.dart';
import '../services/channel_service.dart';
import 'channel_screen.dart';

class ChannelsScreen extends StatefulWidget {
  const ChannelsScreen({super.key});

  @override
  State<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen> {
  final ChannelService _channelService = ChannelService();
  final TextEditingController _searchController = TextEditingController();
  bool _isCreating = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final currentUser = authProvider.currentUser;
    final isAdmin = currentUser?.role == 'admin';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FF),
      appBar: AppBar(
        title: const Text('القنوات'),
        centerTitle: false,
        elevation: 0,
        backgroundColor: const Color(0xFF5B6CFF),
        foregroundColor: Colors.white,
        actions: [
          if (isAdmin)
            IconButton(
              onPressed: _isCreating ? null : () => _showCreateChannelDialog(context),
              icon: const Icon(Icons.add_circle_outline_rounded),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isCreating ? null : () => _showCreateChannelDialog(context),
        backgroundColor: const Color(0xFF5B6CFF),
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('قناة جديدة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: StreamBuilder<List<Channel>>(
        stream: _channelService.channelsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 42),
                  const SizedBox(height: 8),
                  Text('تعذر تحميل القنوات: ${snapshot.error}'),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => setState(() {}),
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            );
          }

          final channels = snapshot.data ?? [];
          final query = _searchController.text.trim().toLowerCase();
          final filteredChannels = query.isEmpty
              ? channels
              : channels.where((channel) {
                  final haystack = '${channel.name} ${channel.description} ${channel.adminName}'.toLowerCase();
                  return haystack.contains(query);
                }).toList();

          if (channels.isEmpty) {
            return const Center(
              child: Text(
                'لا توجد قنوات متاحة حالياً',
                style: TextStyle(fontSize: 16, color: Colors.black54),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              await Future<void>.delayed(const Duration(milliseconds: 200));
            },
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: TextField(
                    controller: _searchController,
                    textDirection: TextDirection.rtl,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'بحث في القنوات...',
                      prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF5B6CFF)),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.close_rounded),
                            )
                          : null,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                Expanded(
                  child: filteredChannels.isEmpty
                      ? const Center(
                          child: Text(
                            'لا توجد نتائج مطابقة',
                            style: TextStyle(fontSize: 16, color: Colors.black54),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: filteredChannels.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (_, index) {
                            final channel = filteredChannels[index];
                            final isPrivate = channel.isPrivate;
                            final isReadOnly = channel.isReadOnly;

                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(22),
                                onTap: () {
                                  Navigator.of(context).push(MaterialPageRoute(
                                    builder: (_) => ChannelScreen(channelId: channel.id),
                                  ));
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(22),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.04),
                                        blurRadius: 10,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(18),
                                        child: CachedNetworkImage(
                                          imageUrl: channel.imageUrl,
                                          width: 76,
                                          height: 76,
                                          fit: BoxFit.cover,
                                          placeholder: (_, __) => const SizedBox(
                                            width: 76,
                                            height: 76,
                                            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                          ),
                                          errorWidget: (_, __, ___) => Container(
                                            width: 76,
                                            height: 76,
                                            color: const Color(0xFFEAEFFF),
                                            child: const Icon(Icons.broken_image_outlined, color: Color(0xFF5B6CFF)),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    channel.name,
                                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                                                  ),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: isPrivate ? const Color(0xFFFFF1E6) : const Color(0xFFEAFBEE),
                                                    borderRadius: BorderRadius.circular(12),
                                                  ),
                                                  child: Text(
                                                    isPrivate ? 'خاص' : 'عام',
                                                    style: TextStyle(
                                                      color: isPrivate ? Colors.orange.shade800 : Colors.green.shade800,
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              channel.description,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(color: Colors.grey, height: 1.4),
                                            ),
                                            const SizedBox(height: 10),
                                            Row(
                                              children: [
                                                Icon(Icons.person_outline_rounded, size: 15, color: Colors.grey.shade600),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    channel.adminName,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                                                  ),
                                                ),
                                                if (isReadOnly)
                                                  Container(
                                                    margin: const EdgeInsets.only(right: 6),
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: Colors.grey.shade100,
                                                      borderRadius: BorderRadius.circular(10),
                                                    ),
                                                    child: const Text(
                                                      'قراءة فقط',
                                                      style: TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.bold),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showCreateChannelDialog(BuildContext context) async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final imageController = TextEditingController();
    final authProvider = context.read<AuthProvider>();
    final messenger = ScaffoldMessenger.of(context);
    String accessType = 'public';
    bool isReadOnly = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              title: const Text('إنشاء قناة جديدة', style: TextStyle(fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'اسم القناة', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(labelText: 'الوصف', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: imageController,
                      decoration: const InputDecoration(labelText: 'رابط الصورة (اختياري)', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      value: accessType,
                      decoration: const InputDecoration(labelText: 'نوع المشاركة', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'public', child: Text('عام')),
                        DropdownMenuItem(value: 'private', child: Text('خاص')),
                        DropdownMenuItem(value: 'guest-only', child: Text('ضيوف فقط')),
                      ],
                      onChanged: (value) => setState(() => accessType = value ?? 'public'),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('وضع القراءة فقط'),
                      subtitle: const Text('المشرف فقط يضيف المنشورات'),
                      value: isReadOnly,
                      onChanged: (value) => setState(() => isReadOnly = value),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5B6CFF)),
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('إنشاء', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) return;

    final name = nameController.text.trim();
    final description = descriptionController.text.trim();
    final imageUrl = imageController.text.trim();

    if (name.isEmpty || description.isEmpty) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('الرجاء إدخال اسم ووصف للقناة')),
      );
      return;
    }

    if (authProvider.currentUser == null) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('يجب تسجيل الدخول أولاً')),
      );
      return;
    }

    setState(() => _isCreating = true);
    try {
      await _channelService.createChannel(
        name: name,
        description: description,
        imageUrl: imageUrl,
        isPrivate: accessType == 'private',
        accessType: accessType,
        isReadOnly: isReadOnly,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('تم إنشاء القناة بنجاح')),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('فشل إنشاء القناة: ${error.toString()}')),
      );
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }
}
