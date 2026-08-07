import 'package:cloud_firestore/cloud_firestore.dart' as firestore;
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_core/firebase_core.dart' as firebase_core;
import 'package:firebase_messaging/firebase_messaging.dart'; // تم الإضافة للإشعارات
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'config.dart';
import 'l10n/app_localizations.dart';
import 'firebase_options.dart';
import 'providers/atyaaf_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/engagement_provider.dart';
import 'providers/feed_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/admin_screen.dart';
import 'screens/atyaaf_reels_screen.dart';
import 'screens/banned_screen.dart';
import 'screens/channels_screen.dart';
import 'screens/feature_ideas_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'services/local_storage_service.dart';
import 'services/callkit_service.dart'; // تم الإضافة لاستدعاء شاشة الاتصال

// تم الإضافة: هذه الدالة تعمل في الخلفية وتستقبل المكالمة والتطبيق مغلق
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await firebase_core.Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // التحقق مما إذا كان الإشعار القادم هو مكالمة
  if (message.data['type'] == 'call') {
    final callId = message.data['callId'] ?? '';
    final callerName = message.data['callerName'] ?? 'مكالمة واردة';
    final callType = message.data['callType'] ?? 'audio'; // 'video' أو 'audio'

    if (callId.isNotEmpty) {
      await CallKitService.instance.showIncomingCall(
        callId: callId,
        callerName: callerName,
        type: callType,
      );
    }
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  timeago.setLocaleMessages('ar', timeago.ArMessages());

  try {
    await firebase_core.Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // تم الإضافة: طلب صلاحية الإشعارات للمستخدم وتفعيل الاستماع في الخلفية
    if (!kIsWeb) {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    }
  } catch (error, stackTrace) {
    debugPrint('Firebase initialization failed: $error');
    debugPrint(stackTrace.toString());
  }

  await LocalStorageService().init();

  try {
    if (kIsWeb) {
      firestore.FirebaseFirestore.instance.settings = const firestore.Settings(
        persistenceEnabled: true,
        cacheSizeBytes: firestore.Settings.CACHE_SIZE_UNLIMITED,
      );
    } else {
      firestore.FirebaseFirestore.instance.settings = const firestore.Settings(
        persistenceEnabled: true,
      );
    }
  } catch (_) {}

  runApp(
    EasyLocalization(
      supportedLocales: const [
        Locale('ar'),
        Locale('en'),
        Locale('fr'),
        Locale('es'),
      ],
      fallbackLocale: const Locale('en'),
      path: 'assets/translations',
      child: const ZamelApp(),
    ),
  );
}

class ZamelApp extends StatelessWidget {
  const ZamelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
        ChangeNotifierProvider<SettingsProvider>(create: (_) => SettingsProvider()),
        ChangeNotifierProvider<AtyaafProvider>(create: (_) => AtyaafProvider()),
        ChangeNotifierProvider<EngagementProvider>(create: (_) => EngagementProvider()),
        ChangeNotifierProvider<FeedProvider>(create: (_) => FeedProvider()), 
        Provider<LocalStorageService>(create: (_) => LocalStorageService()),
      ],
      child: PresenceTracker(
        child: Consumer<SettingsProvider>(
          builder: (context, settingsProvider, _) {
            final lightColorScheme = ColorScheme.fromSeed(
            seedColor: const Color(0xFF5B6CFF),
            secondary: const Color(0xFF2EC7A5),
            tertiary: const Color(0xFFFF8A65),
            brightness: Brightness.light,
          );

          final darkColorScheme = ColorScheme.fromSeed(
            seedColor: const Color(0xFF5B6CFF),
            secondary: const Color(0xFF2EC7A5),
            tertiary: const Color(0xFFFF8A65),
            brightness: Brightness.dark,
          );

          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'ZAMEL',
            theme: ThemeData(
              colorScheme: lightColorScheme,
              scaffoldBackgroundColor: const Color(0xFFF7F8FF),
              useMaterial3: true,
              fontFamily: 'Segoe UI',
              appBarTheme: const AppBarTheme(
                elevation: 0,
                centerTitle: true,
                backgroundColor: Color(0xFF5B6CFF),
                foregroundColor: Colors.white,
              ),
              cardTheme: const CardThemeData(
                elevation: 2,
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                ),
              ),
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5B6CFF),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              inputDecorationTheme: InputDecorationTheme(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            darkTheme: ThemeData(
              colorScheme: darkColorScheme,
              brightness: Brightness.dark,
              useMaterial3: true,
              scaffoldBackgroundColor: const Color(0xFF0F172A),
              cardTheme: const CardThemeData(
                elevation: 2,
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                ),
              ),
            ),
            themeMode: settingsProvider.darkMode ? ThemeMode.dark : ThemeMode.light,
            localizationsDelegates: [
              ...context.localizationDelegates,
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            routes: {
              '/admin': (_) => const AdminScreen(),
              '/banned': (_) => const BannedScreen(),
              '/atyaaf': (_) => const AtyaafReelsScreen(),
              '/channels': (_) => const ChannelsScreen(),
              '/ideas': (_) => const FeatureIdeasScreen(),
              '/registration': (_) => const RegisterScreen(),
              '/home': (_) => const HomeScreen(),
            },
            home: const AuthStateHandler(),
          );
        },
      ),
    ));
  }
}

class PresenceTracker extends StatefulWidget {
  final Widget child;
  const PresenceTracker({super.key, required this.child});

  @override
  State<PresenceTracker> createState() => _PresenceTrackerState();
}

class _PresenceTrackerState extends State<PresenceTracker> with WidgetsBindingObserver {
  bool _hasInitializedPresence = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hasInitializedPresence) {
        _hasInitializedPresence = true;
        _updatePresence(online: true);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _updatePresence(online: true);
    } else if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _updatePresence(online: false);
    }
  }

  Future<void> _updatePresence({required bool online}) async {
    if (!mounted) return;
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (authProvider.currentUser == null) return;
      await authProvider.updateUserPresence(online: online);
    } catch (_) {
      // ignore exceptions intentionally to avoid lifecycle crashes
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class AuthStateHandler extends StatelessWidget {
  const AuthStateHandler({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<firebase_auth.User?>(
      stream: firebase_auth.FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData) {
          return const HomeScreen();
        }

        return const LoginScreen();
      },
    );
  }
}
