import 'package:flutter_test/flutter_test.dart';
import 'package:zamel_appp/services/comment_service.dart';

void main() {
  group('CommentService payload', () {
    test('creates a complete compatible text payload', () {
      final payload = CommentService.buildCommentPayload(
        postId: 'post-1',
        userId: 'user-1',
        username: ' User ',
        text: ' hello ',
      );

      expect(payload['postId'], 'post-1');
      expect(payload['userId'], 'user-1');
      expect(payload['username'], 'User');
      expect(payload['text'], 'hello');
      expect(payload['type'], 'text');
      expect(payload['likesCount'], 0);
      expect(payload['repliesCount'], 0);
      expect(payload['isEdited'], false);
      expect(payload['isDeleted'], false);
      expect(payload['replyToCommentId'], '');
      expect(payload['rootCommentId'], '');
    });

    test('preserves reply and audio metadata', () {
      final payload = CommentService.buildCommentPayload(
        postId: 'post-1',
        userId: 'user-1',
        username: 'User',
        text: '[AUDIO]',
        audioUrl: 'https://example.com/comment.webm',
        type: 'audio',
        duration: 7,
        replyToCommentId: 'parent-1',
        replyToUserId: 'parent-user',
        replyToUsername: 'Parent',
        rootCommentId: 'root-1',
      );

      expect(payload['type'], 'audio');
      expect(payload['audioUrl'], 'https://example.com/comment.webm');
      expect(payload['duration'], 7);
      expect(payload['replyToCommentId'], 'parent-1');
      expect(payload['rootCommentId'], 'root-1');
    });
  });
}
