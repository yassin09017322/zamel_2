import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsProvider = context.watch<SettingsProvider>();
    final authProvider = context.read<AuthProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('الإعدادات'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SettingsSection(
            title: 'الواجهة',
            children: [
              SwitchListTile(
                title: const Text('الوضع الداكن'),
                subtitle: const Text('واجهة مريحة للليل أو النهار'),
                value: settingsProvider.darkMode,
                onChanged: settingsProvider.toggleDarkMode,
              ),
              ListTile(
                leading: const Icon(Icons.language),
                title: const Text('اللغة'),
                subtitle: Text(settingsProvider.locale.languageCode == 'ar' ? 'العربية' : 'English'),
                trailing: DropdownButton<String>(
                  value: settingsProvider.locale.languageCode,
                  items: const [
                    DropdownMenuItem(value: 'ar', child: Text('العربية')),
                    DropdownMenuItem(value: 'en', child: Text('English')),
                  ],
                  onChanged: (value) async {
                    if (value != null) {
                      await settingsProvider.setLanguage(value);
                    }
                  },
                ),
              ),
              SwitchListTile(
                title: const Text('الوضع المخصص'),
                subtitle: const Text('إخفاء العناصر غير الضرورية وتبسيط الشاشة'),
                value: settingsProvider.privateMode,
                onChanged: settingsProvider.togglePrivateMode,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SettingsSection(
            title: 'الإشعارات والتحديث',
            children: [
              SwitchListTile(
                title: const Text('التنبيهات الصوتية'),
                subtitle: const Text('تنبيهات واضحة عند الرسائل والمكالمات'),
                value: settingsProvider.soundNotifications,
                onChanged: settingsProvider.toggleSoundNotifications,
              ),
              SwitchListTile(
                title: const Text('التحديث التلقائي للمنشورات'),
                subtitle: const Text('تحديث مستمر للمنشورات الجديدة'),
                value: settingsProvider.autoRefresh,
                onChanged: settingsProvider.toggleAutoRefresh,
              ),
              SwitchListTile(
                title: const Text('إظهار حالة الاتصال'),
                subtitle: const Text('عرض متصل الآن وآخر ظهور في الدردشات والمحادثات'),
                value: settingsProvider.sharePresence,
                onChanged: (value) async {
                  await settingsProvider.toggleSharePresence(value);
                  if (authProvider.currentUser != null) {
                    await authProvider.updateSharePresenceSetting(value);
                  }
                },
              ),
              SwitchListTile(
                title: const Text('التخطيط المدمج'),
                subtitle: const Text('تقليل المسافات والعناصر لعرض أكثر سلاسة'),
                value: settingsProvider.compactMode,
                onChanged: settingsProvider.toggleCompactMode,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.public),
              title: const Text('التطبيق عالمي'),
              subtitle: const Text('يدعم لغات متعددة ويوفر تجربة مناسبة للمستخدمين حول العالم.'),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.restart_alt),
              title: const Text('إعادة تعيين الإعدادات'),
              subtitle: const Text('استعادة القيم الافتراضية لجميع الخيارات.'),
              onTap: () async {
                await settingsProvider.resetSettings();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تمت إعادة تعيين الإعدادات بنجاح')),
                  );
                }
              },
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('عن التطبيق'),
            subtitle: const Text('ZAMEL نسخة مخصصة من التطبيق السابق مع دعم Firebase وميزات عالمية.'),
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}
