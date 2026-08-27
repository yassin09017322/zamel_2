import 'package:flutter_test/flutter_test.dart';
import 'package:zamel_appp/services/post_translation_service.dart';

void main() {
  test('does not translate when target language is unsupported', () async {
    final service = PostTranslationService();

    final result = await service.translateIfNeeded(
      postId: 'post-arabic',
      text: 'مرحبا بكم',
      targetLanguage: 'unsupported',
    );

    expect(result, isNull);
  });

  test('does not translate empty text', () async {
    final service = PostTranslationService();

    final result = await service.translateIfNeeded(
      postId: 'empty-post',
      text: '   ',
      targetLanguage: 'en',
    );

    expect(result, isNull);
  });
}
