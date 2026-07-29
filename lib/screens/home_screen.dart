import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_user.dart';
import '../providers/auth_provider.dart';
import '../providers/engagement_provider.dart';
import '../services/call_service.dart';
import 'admin_screen.dart';
import 'call_screen.dart';
import 'chat_screen.dart';
import 'atyaaf_reels_screen.dart';
import 'feature_ideas_screen.dart';
import 'feed_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import 'user_search_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  bool _incomingListenerStarted = false;
  StreamSubscription<IncomingCall>? _incomingCallSubscription;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final currentUser = context.watch<AuthProvider>().currentUser;
    if (!_incomingListenerStarted && currentUser != null) {
      _incomingListenerStarted = true;
      CallService.instance.startIncomingCallListener(
        currentUserId: currentUser.id,
      );
      _incomingCallSubscription = CallService.instance.incomingCallStream.listen(
        (incomingCall) => _handleIncomingCall(incomingCall, currentUser),
      );
    }
  }

  Future<void> _handleIncomingCall(IncomingCall incomingCall, AppUser currentUser) async {
    if (!mounted) return;
    final accept = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('مكالمة واردة'),
        content: Text('لديك مكالمة ${incomingCall.type == 'video' ? 'فيديو' : 'صوت'} من ${incomingCall.callerName}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('رفض'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('استقبال'),
          ),
        ],
      ),
    );

    if (accept != true) {
      await CallService.instance.rejectCall(incomingCall.callId);
      return;
    }

    try {
      final session = await CallService.instance.answerCall(
        callId: incomingCall.callId,
        type: incomingCall.type,
        callerId: incomingCall.callerId,
        callerName: incomingCall.callerName,
        receiverId: incomingCall.receiverId,
        receiverName: incomingCall.receiverName,
        chatId: incomingCall.chatId,
      );
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CallScreen(session: session),
      ));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل استقبال المكالمة: ${error.toString()}')),
      );
    }
  }

  @override
  void dispose() {
    _incomingCallSubscription?.cancel();
    CallService.instance.stopIncomingCallListener();
    super.dispose();
  }

  static const List<Widget> _pages = <Widget>[
    FeedScreen(),
    ChatScreen(),
    NotificationsScreen(),
    FeatureIdeasScreen(),
    SettingsScreen(),
    ProfileScreen(),
  ];

  static const List<BottomNavigationBarItem> _navItems = [
    BottomNavigationBarItem(icon: Icon(Icons.home), label: 'الرئيسية'),
    BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_outline), label: 'الدردشات'),
    BottomNavigationBarItem(icon: Icon(Icons.notifications_none), label: 'الإشعارات'),
    BottomNavigationBarItem(icon: Icon(Icons.lightbulb_outline), label: 'أفكار'),
    BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: 'الإعدادات'),
    BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'الملف الشخصي'),
  ];

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final engagementProvider = context.watch<EngagementProvider>();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color(0xFF5B6CFF), Color(0xFF7B61FF)],
              ),
            ),
            child: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              title: Text(_navItems[_selectedIndex].label ?? ''),
              actions: [
                if (authProvider.currentUser?.role == 'admin')
                  IconButton(
                    icon: const Icon(Icons.admin_panel_settings),
                    tooltip: 'لوحة المشرف',
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminScreen()));
                    },
                  ),
                IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: 'بحث عن مستخدمين',
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UserSearchScreen()));
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.public),
                  tooltip: 'ميزات عالمية',
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('التطبيق الآن يدعم تجربة أكثر عالمية مع لغات وإعدادات متقدمة.')),
                    );
                  },
                ),
                // الأيقونة الاحترافية الجديدة لقسم أطياف
                IconButton(
                  tooltip: 'أطياف',
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AtyaafReelsScreen()));
                  },
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF8A2387), Color(0xFFE94057)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFE94057).withOpacity(0.4),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        )
                      ],
                    ),
                    child: const Icon(
                      Icons.video_library_rounded, 
                      color: Colors.white, 
                      size: 22,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.logout),
                  onPressed: () async {
                    await authProvider.signOut();
                  },
                )
              ],
            ),
          ),
        ),
        body: Column(
          children: [
            if (_selectedIndex == 0)
              Container(
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF5B6CFF), Color(0xFF2EC7A5)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            engagementProvider.challengeText,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${engagementProvider.points} نقطة • ${engagementProvider.streak} يوم متتالي',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        await engagementProvider.completeDailyChallenge();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('تم إكمال التحدي اليومي بنجاح 🎉')),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF5B6CFF)),
                      child: const Text('إكمال'),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Theme.of(context).colorScheme.primary.withAlpha(26),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: _pages[_selectedIndex],
              ),
            ),
          ],
        ),
        bottomNavigationBar: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withAlpha(240),
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BottomNavigationBar(
              currentIndex: _selectedIndex,
              items: _navItems,
              onTap: (index) {
                setState(() {
                  _selectedIndex = index;
                });
              },
              selectedItemColor: Theme.of(context).colorScheme.primary,
              unselectedItemColor: Colors.grey,
              backgroundColor: Colors.transparent,
              type: BottomNavigationBarType.fixed,
              elevation: 0,
              selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ),
      ),
    );
  }
}