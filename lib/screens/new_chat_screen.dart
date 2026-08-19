import 'dart:async';

import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../services/chat_service.dart';
import '../services/user_service.dart';
import 'chat_room_screen.dart';

class NewChatScreen extends StatefulWidget {
  final AppUser currentUser;

  const NewChatScreen({super.key, required this.currentUser});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final TextEditingController _searchController = TextEditingController();
  final UserService _userService = UserService();
  final ChatService _chatService = ChatService();

  String _searchTerm = '';
  Timer? _debounce;
  bool _isSearching = false;

  List<AppUser> _friends = [];
  bool _isLoadingFriends = true;
  String? _friendError;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    setState(() {
      _isLoadingFriends = true;
      _friendError = null;
    });

    try {
      final followingIds = widget.currentUser.following;
      final friends = await _userService.usersByIds(followingIds);
      if (!mounted) return;
      setState(() {
        _friends = friends.where((user) => user.id != widget.currentUser.id).toList();
        _isLoadingFriends = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _friendError = error.toString();
        _isLoadingFriends = false;
      });
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      setState(() {
        _searchTerm = value.trim();
        _isSearching = _searchTerm.isNotEmpty;
      });
    });
  }

  Future<void> _openChatWith(AppUser user) async {
    final roomId = await _chatService.createOrGetChatRoom(
      currentUserId: widget.currentUser.id,
      currentUsername: widget.currentUser.username,
      otherUserId: user.id,
      otherUsername: user.username,
    );

    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => ChatRoomScreen(currentUser: widget.currentUser, roomId: roomId),
    ));
  }

  Widget _buildUserTile(AppUser user) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      tileColor: Colors.grey[100],
      leading: CircleAvatar(
        backgroundImage: user.photoURL?.isNotEmpty == true ? NetworkImage(user.photoURL!) : null,
        child: user.photoURL?.isEmpty == true ? Text(user.username.isNotEmpty ? user.username[0] : 'م') : null,
      ),
      title: Text(user.username.isNotEmpty ? user.username : 'مستخدم'),
      onTap: () => _openChatWith(user),
    );
  }

  Widget _buildFriendList() {
    if (_isLoadingFriends) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_friendError != null) {
      return Center(child: Text('فشل تحميل قائمة المتابعين: $_friendError'));
    }
    if (_friends.isEmpty) {
      return const Center(child: Text('لا يوجد أشخاص تتابعهم حالياً.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _friends.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _buildUserTile(_friends[index]),
    );
  }

  Widget _buildSearchResults() {
    return StreamBuilder<List<AppUser>>(
      stream: _userService.searchUsers(_searchTerm),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('حدث خطأ أثناء البحث: ${snapshot.error}'));
        }
        final users = snapshot.data?.where((user) => user.id != widget.currentUser.id).toList() ?? [];
        if (users.isEmpty) {
          return const Center(child: Text('لا يوجد نتائج.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: users.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) => _buildUserTile(users[index]),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إضافة محادثة جديدة')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'ابحث بالاسم أو اسم المستخدم',
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchController.clear();
                          _debounce?.cancel();
                          setState(() {
                            _searchTerm = '';
                            _isSearching = false;
                          });
                        },
                      )
                    : const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          Expanded(
            child: _isSearching ? _buildSearchResults() : _buildFriendList(),
          ),
        ],
      ),
    );
  }
}
