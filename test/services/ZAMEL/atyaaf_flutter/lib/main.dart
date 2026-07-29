import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'views/atyaaf_feed_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const ZamelApp());
}

class ZamelApp extends StatelessWidget {
  const ZamelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ZAMEL',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7B61FF)),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const AtyaafFeedView(),
        '/lesson': (context) => const PlaceholderRoutePage(title: 'صفحة الشرح'),
        '/questions': (context) => const PlaceholderRoutePage(title: 'بنك الأسئلة'),
      },
    );
  }
}

class PlaceholderRoutePage extends StatelessWidget {
  const PlaceholderRoutePage({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text(
          'سيتم ربط هذا الجزء بالصفحة المناسبة داخل التطبيق لاحقاً',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    );
  }
}
