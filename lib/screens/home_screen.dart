import 'dart:async';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'login_screen.dart'; 
import '../models/app_user.dart';
// 🔥 الحل الجذري هنا: إعطاء اسم مستعار للاستيراد لمنع اللخبطة
import '../providers/auth_provider.dart' as my_auth; 
import '../providers/engagement_provider.dart';
import '../services/call_service.dart';
import '../services/callkit_service.dart'; 
import 'admin_screen.dart';
import 'call_screen.dart';
import 'chat_screen.dart';
import 'atyaaf_reels_screen.dart';
import 'channels_screen.dart';
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
    // 🔥 التعديل هنا: استخدام الاسم المستعار
    final currentUser = context.watch<my_auth.AuthProvider>().currentUser;
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

    await CallKitService.instance.showIncomingCall(
      callId: incomingCall.callId,
      callerName: incomingCall.callerName,
      type: incomingCall.type,
    );

    StreamSubscription? callSubscription;
    callSubscription = CallKitService.instance.callEventStream.listen((eventData) async {
      
      if (eventData['callId'] != incomingCall.callId) return;

      final action = eventData['event'];

      if (action == 'accept') {
        callSubscription?.cancel(); 
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
            SnackBar(content: Text('فشل استقبال المكالمة: $error')),
          );
        }
      } else if (action == 'decline' || action == 'timeout') {
        callSubscription?.cancel(); 
        await CallService.instance.rejectCall(incomingCall.callId); 
      }
    });
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
    // 🔥 التعديل هنا: استخدام الاسم المستعار
    final authProvider = context.watch<my_auth.AuthProvider>();
    final engagementProvider = context.watch<EngagementProvider>();

    final isArabic = context.locale.languageCode == 'ar';

    return Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
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
                  icon: const Icon(Icons.group_work_outlined),
                  tooltip: 'القنوات',
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChannelsScreen()));
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
                          color: const Color(0xFFE94057).withValues(alpha: 0.4),
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
                  tooltip: 'تسجيل الخروج',
                  onPressed: () async {
                    try {
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => const Center(child: CircularProgressIndicator(color: Colors.white)),
                      );

                      final prefs = await SharedPreferences.getInstance();
                      await prefs.clear();

                      await FirebaseAuth.instance.signOut();

                      if (context.mounted) {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const LoginScreen()),
                          (route) => false,
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        Navigator.pop(context); 
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('فشل تسجيل الخروج: $e')),
                        );
                      }
                    }
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
