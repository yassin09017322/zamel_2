import 'package:flutter_test/flutter_test.dart';
import 'package:zamel_appp/providers/atyaaf_provider.dart';

void main() {
  group('AtyaafProvider cinematic mode', () {
    test('toggleCinematicMode switches the shared flag', () {
      final provider = AtyaafProvider();

      expect(provider.cinematicModeEnabled, isFalse);

      provider.toggleCinematicMode();
      expect(provider.cinematicModeEnabled, isTrue);

      provider.toggleCinematicMode();
      expect(provider.cinematicModeEnabled, isFalse);
    });
  });
}
