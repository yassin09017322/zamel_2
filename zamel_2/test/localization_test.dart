import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:zamel_appp/l10n/app_localizations.dart';

void main() {
  group('AppLocalizations', () {
    test('returns Arabic strings for Arabic locale', () {
      final localizations = lookupAppLocalizations(const Locale('ar'));
      expect(localizations.loginTitle, 'تسجيل الدخول إلى حسابك');
    });

    test('returns English strings for English locale', () {
      final localizations = lookupAppLocalizations(const Locale('en'));
      expect(localizations.loginTitle, 'Sign in to your account');
    });
  });
}
