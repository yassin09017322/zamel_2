import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsProvider = context.watch<SettingsProvider>();
    final authProvider = context.read<AuthProvider>();
    final l10n = AppLocalizations.of(context);

    if (l10n == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsTitle),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SettingsSection(
            title: l10n.settingsInterface,
            children: [
              SwitchListTile(
                title: Text(l10n.settingsDarkMode),
                subtitle: Text(l10n.settingsDarkModeSubtitle),
                value: settingsProvider.darkMode,
                onChanged: settingsProvider.toggleDarkMode,
              ),
              ListTile(
                leading: const Icon(Icons.language),
                title: Text(l10n.settingsLanguage),
                subtitle: Text(l10n.settingsLanguageSubtitle),
                trailing: DropdownButton<String>(
                  value: settingsProvider.locale.languageCode,
                  items: const [
                    DropdownMenuItem(value: 'ar', child: Text('العربية')),
                    DropdownMenuItem(value: 'en', child: Text('English')),
                    DropdownMenuItem(value: 'fr', child: Text('Français')),
                    DropdownMenuItem(value: 'de', child: Text('Deutsch')),
                    DropdownMenuItem(value: 'es', child: Text('Español')),
                    DropdownMenuItem(value: 'tr', child: Text('Türkçe')),
                  ],
                  onChanged: (value) async {
                    if (value != null) {
                      await settingsProvider.setLanguage(value);
                    }
                  },
                ),
              ),
              SwitchListTile(
                title: Text(l10n.settingsCustomMode),
                subtitle: Text(l10n.settingsCustomModeSubtitle),
                value: settingsProvider.privateMode,
                onChanged: settingsProvider.togglePrivateMode,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SettingsSection(
            title: l10n.settingsNotifications,
            children: [
              SwitchListTile(
                title: Text(l10n.settingsSoundNotifications),
                subtitle: Text(l10n.settingsSoundNotificationsSubtitle),
                value: settingsProvider.soundNotifications,
                onChanged: settingsProvider.toggleSoundNotifications,
              ),
              SwitchListTile(
                title: Text(l10n.settingsAutoRefresh),
                subtitle: Text(l10n.settingsAutoRefreshSubtitle),
                value: settingsProvider.autoRefresh,
                onChanged: settingsProvider.toggleAutoRefresh,
              ),
              SwitchListTile(
                title: Text(l10n.settingsPresence),
                subtitle: Text(l10n.settingsPresenceSubtitle),
                value: settingsProvider.sharePresence,
                onChanged: (value) async {
                  await settingsProvider.toggleSharePresence(value);
                  if (authProvider.currentUser != null) {
                    await authProvider.updateSharePresenceSetting(value);
                  }
                },
              ),
              SwitchListTile(
                title: Text(l10n.settingsCompactMode),
                subtitle: Text(l10n.settingsCompactModeSubtitle),
                value: settingsProvider.compactMode,
                onChanged: settingsProvider.toggleCompactMode,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.public),
              title: Text(l10n.settingsGlobalTitle),
              subtitle: Text(l10n.settingsGlobalSubtitle),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.restart_alt),
              title: Text(l10n.settingsResetTitle),
              subtitle: Text(l10n.settingsResetSubtitle),
              onTap: () async {
                await settingsProvider.resetSettings();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.settingsResetSuccess)),
                  );
                }
              },
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(l10n.settingsAboutTitle),
            subtitle: Text(l10n.settingsAboutSubtitle),
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
