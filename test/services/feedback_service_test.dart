import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notes_app/services/feedback_service.dart';

http.Response _response(int statusCode) =>
    http.Response('{"ok":true}', statusCode);

FeedbackService _serviceWith(MockClient client) =>
    FeedbackService.withClient(client);

const _kArgs = (
  message: 'This is a test feedback message that is long enough.',
  appVersion: '1.5.0',
  platform: 'macOS',
);

void main() {
  group('FeedbackService', () {
    test('submit_withValidMessage_postsToFormspreeAndMarksSession', () async {
      // Arrange
      final client = MockClient((_) async => _response(200));
      final service = _serviceWith(client);

      // Act
      await service.submit(
        message: _kArgs.message,
        appVersion: _kArgs.appVersion,
        platform: _kArgs.platform,
      );

      // Assert
      expect(service.hasSubmittedThisSession, isTrue);
    });

    test('submit_includesSenderEmail_whenProvided', () async {
      // Arrange
      http.Request? captured;
      final client = MockClient((req) async {
        captured = req;
        return _response(200);
      });

      // Act
      await _serviceWith(client).submit(
        message: _kArgs.message,
        senderEmail: 'user@example.com',
        appVersion: _kArgs.appVersion,
        platform: _kArgs.platform,
      );

      // Assert
      expect(captured?.bodyFields['email'], 'user@example.com');
    });

    test('submit_withNoEmail_sendsEmptyEmailField', () async {
      // Arrange
      http.Request? captured;
      final client = MockClient((req) async {
        captured = req;
        return _response(200);
      });

      // Act
      await _serviceWith(client).submit(
        message: _kArgs.message,
        appVersion: _kArgs.appVersion,
        platform: _kArgs.platform,
      );

      // Assert
      expect(captured?.bodyFields['email'], '');
    });

    test('submit_secondCallInSameSession_throwsFeedbackAlreadySubmittedException',
        () async {
      // Arrange
      final client = MockClient((_) async => _response(200));
      final service = _serviceWith(client);
      await service.submit(
        message: _kArgs.message,
        appVersion: _kArgs.appVersion,
        platform: _kArgs.platform,
      );

      // Act & Assert
      expect(
        () => service.submit(
          message: _kArgs.message,
          appVersion: _kArgs.appVersion,
          platform: _kArgs.platform,
        ),
        throwsA(isA<FeedbackAlreadySubmittedException>()),
      );
    });

    test('submit_withServerError_throwsFeedbackSubmissionException', () async {
      // Arrange
      final client = MockClient((_) async => _response(500));

      // Act & Assert
      expect(
        () => _serviceWith(client).submit(
          message: _kArgs.message,
          appVersion: _kArgs.appVersion,
          platform: _kArgs.platform,
        ),
        throwsA(isA<FeedbackSubmissionException>()),
      );
    });

    test('submit_withServerError_doesNotMarkSessionAsSubmitted', () async {
      // Arrange
      final client = MockClient((_) async => _response(422));
      final service = _serviceWith(client);

      // Act
      try {
        await service.submit(
          message: _kArgs.message,
          appVersion: _kArgs.appVersion,
          platform: _kArgs.platform,
        );
      } catch (_) {}

      // Assert
      expect(service.hasSubmittedThisSession, isFalse);
    });

    test('hasSubmittedThisSession_beforeAnySubmit_returnsFalse', () {
      // Arrange
      final service = _serviceWith(MockClient((_) async => _response(200)));

      // Assert
      expect(service.hasSubmittedThisSession, isFalse);
    });

    test('submit_withTimeout_marksSessionAsSubmitted', () async {
      // Arrange — client times out after the request is dispatched
      final client =
          MockClient((_) async => throw TimeoutException('timeout'));
      final service = _serviceWith(client);

      // Act
      try {
        await service.submit(
          message: _kArgs.message,
          appVersion: _kArgs.appVersion,
          platform: _kArgs.platform,
        );
      } on TimeoutException {
        // expected — testing behaviour after the timeout
      }

      // Assert — message likely reached Formspree; block a duplicate
      expect(service.hasSubmittedThisSession, isTrue);
    });

    test('submit_afterTimeout_throwsFeedbackAlreadySubmittedException',
        () async {
      // Arrange — first call times out
      final client =
          MockClient((_) async => throw TimeoutException('timeout'));
      final service = _serviceWith(client);
      try {
        await service.submit(
          message: _kArgs.message,
          appVersion: _kArgs.appVersion,
          platform: _kArgs.platform,
        );
      } on TimeoutException {
        // expected — testing behaviour after the timeout
      }

      // Act & Assert — second call must be blocked
      expect(
        () => service.submit(
          message: _kArgs.message,
          appVersion: _kArgs.appVersion,
          platform: _kArgs.platform,
        ),
        throwsA(isA<FeedbackAlreadySubmittedException>()),
      );
    });
  });
}
