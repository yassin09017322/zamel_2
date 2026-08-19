import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zamel_appp/services/engagement_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await EngagementService.reset();
  });

  test('increments streak on consecutive active days', () async {
    final first = await EngagementService.recordActivity();
    expect(first['streak'], 1);

    final second = await EngagementService.recordActivity();
    expect(second['streak'], 2);
  });

  test('returns achievement summary with progress', () async {
    final summary = await EngagementService.getSummary();
    expect(summary['achievementLabel'], isNotEmpty);
    expect(summary['streak'], 0);
  });
}
