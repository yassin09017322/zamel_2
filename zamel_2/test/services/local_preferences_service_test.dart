import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zamel_appp/services/local_preferences_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalPreferencesService.clearAll();
  });

  test('saves and restores draft content', () async {
    await LocalPreferencesService.saveDraft(
      text: 'مرحبا بالعالم',
      location: 'الرياض',
      cloudUrl: 'https://example.com/image.jpg',
      mediaType: 'image',
      isTemporary: true,
    );

    final draft = await LocalPreferencesService.loadDraft();
    expect(draft, isNotNull);
    expect(draft!['text'], 'مرحبا بالعالم');
    expect(draft['location'], 'الرياض');
    expect(draft['cloudUrl'], 'https://example.com/image.jpg');
    expect(draft['mediaType'], 'image');
    expect(draft['isTemporary'], true);
  });

  test('toggles saved posts correctly', () async {
    expect(await LocalPreferencesService.isPostSaved('post_1'), isFalse);

    await LocalPreferencesService.toggleSavedPost('post_1');
    expect(await LocalPreferencesService.isPostSaved('post_1'), isTrue);

    await LocalPreferencesService.toggleSavedPost('post_1');
    expect(await LocalPreferencesService.isPostSaved('post_1'), isFalse);
  });
}
