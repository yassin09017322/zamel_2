import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_user.dart';
import '../providers/auth_provider.dart';
import '../screens/user_profile_screen.dart';

class UserSearchScreen extends StatefulWidget {
  const UserSearchScreen({super.key});

  @override
  State<UserSearchScreen> createState() => _UserSearchScreenState();
}

class _UserSearchScreenState extends State<UserSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchTerm = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = context.watch<AuthProvider>().currentUser;
    if (currentUser == null) {
      return const Scaffold(body: Center(child: Text('الرجاء تسجيل الدخول')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('بحث المستخدمين')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'ابحث باسم المستخدم أو البريد الإلكتروني',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => setState(() => _searchTerm = _searchController.text.trim()),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onSubmitted: (_) => setState(() => _searchTerm = _searchController.text.trim()),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('users').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('حدث خطأ: ${snapshot.error}'));
                }
                final users = snapshot.data?.docs
                        .map((doc) => AppUser.fromFirestore(doc.data(), doc.id))
                        .where((user) => user.id != currentUser.id)
                        .where((user) {
                          final query = _searchTerm.toLowerCase();
                          if (query.isEmpty) return true;
                          return user.username.toLowerCase().contains(query) || user.email.toLowerCase().contains(query);
                        })
                        .toList() ?? [];

                if (users.isEmpty) {
                  return const Center(child: Text('لا يوجد نتائج.'));
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: users.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final user = users[index];
                    return ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      tileColor: Colors.grey[100],
                      leading: CircleAvatar(
                        backgroundImage: user.photoURL?.isNotEmpty == true ? NetworkImage(user.photoURL!) : null,
                        child: user.photoURL?.isEmpty == true ? Text(user.username.isNotEmpty ? user.username[0] : 'م') : null,
                      ),
                      title: Text(user.username),
                      subtitle: Text(user.email),
                      onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => UserProfileScreen(userId: user.id)));
                      },
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
