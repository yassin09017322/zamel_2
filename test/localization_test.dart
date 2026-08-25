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

    test(
      'loads every supported runtime locale without an unsupported-locale error',
      () {
        for (final locale in const [
          Locale('ar'),
          Locale('en'),
          Locale('fr'),
          Locale('es'),
          Locale('tr'),
        ]) {
          final localizations = lookupAppLocalizations(locale);
          expect(localizations.localeName, locale.languageCode);
        }
      },
    );
  });
}
