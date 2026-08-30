import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/group.dart';
import '../providers/auth_provider.dart';
import '../services/group_service.dart';
import 'group_details_screen.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  final GroupService _groupService = GroupService();
  final TextEditingController _searchController = TextEditingController();
  bool _isCreating = false;
  int _selectedTab = 0;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _createGroupDialog() async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    bool isPrivate = false;

    final created = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('إنشاء مجموعة جديدة'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'اسم المجموعة',
                          hintText: 'مثال: مطورون زاميل',
                        ),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                                ? 'اسم المجموعة مطلوب'
                                : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: descriptionController,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'وصف المجموعة',
                          hintText: 'اكتب هدف المجموعة...',
                        ),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('مجموعة خاصة'),
                        subtitle: const Text('يتطلب طلب انضمام أو دعوة'),
                        value: isPrivate,
                        onChanged: (value) => setState(() => isPrivate = value),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: () {
                    if (formKey.currentState?.validate() ?? false) {
                      Navigator.pop(context, true);
                    }
                  },
                  child: const Text('إنشاء'),
                ),
              ],
            );
          },
        );
      },
    );

    if (created != true) return;

    setState(() => _isCreating = true);
    try {
      final groupId = await _groupService.createGroup(
        name: nameController.text,
        description: descriptionController.text,
        isPrivate: isPrivate,
      );

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GroupDetailsScreen(groupId: groupId),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final currentUser = authProvider.currentUser;

    if (currentUser == null) {
      return const Scaffold(
        body: Center(child: Text('يجب تسجيل الدخول أولاً')),
      );
    }

    final discoverStream = _groupService.discoverGroups(currentUser.id);
    final myGroupsStream = _groupService.myGroups(currentUser.id);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FF),
      appBar: AppBar(
        title: const Text('المجموعات'),
        centerTitle: false,
        backgroundColor: const Color(0xFF5B6CFF),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _isCreating ? null : _createGroupDialog,
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
        ],
      ),
      body: Column(
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
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'بحث في المجموعات...',
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
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _selectedTab = 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _selectedTab == 0 ? const Color(0xFF5B6CFF) : Colors.transparent,
                        borderRadius: const BorderRadius.horizontal(left: Radius.circular(18)),
                      ),
                      child: Text(
                        'اكتشف',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _selectedTab == 0 ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _selectedTab = 1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _selectedTab == 1 ? const Color(0xFF5B6CFF) : Colors.transparent,
                        borderRadius: const BorderRadius.horizontal(right: Radius.circular(18)),
                      ),
                      child: Text(
                        'مجموعاتي',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _selectedTab == 1 ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _selectedTab == 0
                ? StreamBuilder<List<Group>>(
                    stream: discoverStream,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(child: Text('تعذر تحميل المجموعات: ${snapshot.error}'));
                      }

                      final groups = snapshot.data ?? [];
                      final query = _searchController.text.trim().toLowerCase();
                      final filteredGroups = query.isEmpty
                          ? groups
                          : groups.where((group) {
                              final haystack = '${group.name} ${group.description} ${group.ownerName}'.toLowerCase();
                              return haystack.contains(query);
                            }).toList();

                      if (groups.isEmpty) {
                        return const Center(child: Text('لا توجد مجموعات حتى الآن'));
                      }

                      if (filteredGroups.isEmpty) {
                        return const Center(child: Text('لا توجد نتائج مطابقة'));
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: filteredGroups.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final group = filteredGroups[index];
                          final isMember = group.memberIds.contains(currentUser.id);
                          return InkWell(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => GroupDetailsScreen(groupId: group.id),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(18),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEAF0FF),
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: const Icon(
                                      Icons.groups_2_rounded,
                                      size: 30,
                                      color: Color(0xFF5B6CFF),
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
                                                group.name,
                                                style: const TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: group.isPrivate
                                                    ? const Color(0xFFFFF3E0)
                                                    : const Color(0xFFE8F5E9),
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                group.isPrivate ? 'خاص' : 'عام',
                                                style: TextStyle(
                                                  color: group.isPrivate
                                                      ? Colors.orange.shade800
                                                      : Colors.green.shade800,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          group.description.isEmpty ? 'لا يوجد وصف' : group.description,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: Colors.grey),
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            const Icon(Icons.person_outline, size: 16, color: Colors.grey),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                group.ownerName,
                                                style: const TextStyle(color: Colors.black87, fontSize: 12),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            const Icon(Icons.group_rounded, size: 16, color: Colors.grey),
                                            const SizedBox(width: 4),
                                            Text(
                                              '${group.memberCount}',
                                              style: const TextStyle(color: Colors.black87, fontSize: 12),
                                            ),
                                            const SizedBox(width: 8),
                                            if (isMember)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFE9F5FF),
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                                child: const Text(
                                                  'عضو',
                                                  style: TextStyle(
                                                    color: Color(0xFF5B6CFF),
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                  ),
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
                          );
                        },
                      );
                    },
                  )
                : StreamBuilder<List<Group>>(
                    stream: myGroupsStream,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(child: Text('تعذر تحميل مجموعاتك: ${snapshot.error}'));
                      }

                      final groups = snapshot.data ?? [];
                      if (groups.isEmpty) {
                        return const Center(child: Text('أنت لست عضوًا في أي مجموعة بعد'));
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: groups.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final group = groups[index];
                          return InkWell(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => GroupDetailsScreen(groupId: group.id),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(18),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 56,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEAF0FF),
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: const Icon(Icons.group, color: Color(0xFF5B6CFF)),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          group.name,
                                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          group.description.isEmpty ? 'لا يوجد وصف' : group.description,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
