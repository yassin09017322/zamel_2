import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';

class BannedScreen extends StatelessWidget {
  const BannedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.read<AuthProvider>();
    final l10n = AppLocalizations.of(context);

    if (l10n == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.bannedTitle),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.block, size: 90, color: Colors.red),
              const SizedBox(height: 20),
              Text(
                l10n.bannedMessage,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, height: 1.4),
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () async {
                  await authProvider.signOut();
                },
                child: Text(l10n.bannedLogout),
              ),
            ],
          ),
        ),
      ),
    );
  }
}