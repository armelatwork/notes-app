import 'dart:async';

import 'package:http/http.dart' as http;

const _kFormspreeEndpoint = 'https://formspree.io/f/mjgzpkpb';
const _kTimeout = Duration(seconds: 15);

class FeedbackAlreadySubmittedException implements Exception {
  @override
  String toString() => 'FeedbackAlreadySubmittedException';
}

class FeedbackSubmissionException implements Exception {
  final int statusCode;
  const FeedbackSubmissionException(this.statusCode);

  @override
  String toString() => 'FeedbackSubmissionException(statusCode: $statusCode)';
}

class FeedbackService {
  FeedbackService._() : _client = http.Client();
  FeedbackService.withClient(http.Client client) : _client = client;

  static final instance = FeedbackService._();

  final http.Client _client;
  bool _submittedThisSession = false;

  bool get hasSubmittedThisSession => _submittedThisSession;

  Future<void> submit({
    required String message,
    String? senderEmail,
    required String appVersion,
    required String platform,
  }) async {
    if (_submittedThisSession) throw FeedbackAlreadySubmittedException();

    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(_kFormspreeEndpoint),
            headers: {'Accept': 'application/json'},
            body: {
              'message': message,
              'email': senderEmail ?? '',
              '_platform': platform,
              '_version': appVersion,
              '_gotcha': '',
            },
          )
          .timeout(_kTimeout);
    } on TimeoutException {
      // The request was dispatched and Formspree likely received it.
      // Mark as submitted to prevent a duplicate send on retry.
      _submittedThisSession = true;
      rethrow;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FeedbackSubmissionException(response.statusCode);
    }

    _submittedThisSession = true;
  }
}
