import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notes_app/services/claude_api_service.dart';
import 'package:notes_app/services/secure_storage_service.dart';

void main() {
  late Directory tempDir;
  final service = ClaudeApiService.instance;
  final storage = SecureStorageService.instance;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('claude_api_service_test_');
    storage.setTestDirectory(tempDir.path);
  });

  tearDown(() async {
    service.setClient(http.Client());
    storage.clearTestDirectory();
    await tempDir.delete(recursive: true);
  });

  // ── isVerified ────────────────────────────────────────────────────────────

  group('isVerified', () {
    test('isVerified_noKeyStored_returnsFalse', () async {
      expect(await service.isVerified(), isFalse);
    });

    test('isVerified_verifiedFlagTrue_returnsTrue', () async {
      await storage.write('claude_api_key_verified', 'true');
      expect(await service.isVerified(), isTrue);
    });

    test('isVerified_verifiedFlagFalse_returnsFalse', () async {
      await storage.write('claude_api_key_verified', 'false');
      expect(await service.isVerified(), isFalse);
    });
  });

  // ── clearKey ──────────────────────────────────────────────────────────────

  group('clearKey', () {
    test('clearKey_withStoredKey_removesKeyAndVerifiedFlag', () async {
      await storage.write('claude_api_key', 'sk-ant-test');
      await storage.write('claude_api_key_verified', 'true');
      await service.clearKey();
      expect(await storage.read('claude_api_key'), isNull);
      expect(await storage.read('claude_api_key_verified'), isNull);
    });

    test('clearKey_withNoKey_completesWithoutError', () async {
      await expectLater(service.clearKey(), completes);
    });
  });

  // ── activateKey ───────────────────────────────────────────────────────────

  group('activateKey', () {
    test('activateKey_emptyKey_returnsError', () async {
      final result = await service.activateKey('   ');
      expect(result, isNotNull);
    });

    test('activateKey_validKey_savesKeyAndReturnsNull', () async {
      service.setClient(MockClient((_) async =>
          http.Response(jsonEncode(_successBody()), 200)));
      final result = await service.activateKey('sk-ant-valid');
      expect(result, isNull);
      expect(await storage.read('claude_api_key'), 'sk-ant-valid');
      expect(await storage.read('claude_api_key_verified'), 'true');
    });

    test('activateKey_invalidKey_returnsErrorAndDoesNotSave', () async {
      service.setClient(MockClient((_) async => http.Response('', 401)));
      final result = await service.activateKey('sk-ant-bad');
      expect(result, isNotNull);
      expect(await storage.read('claude_api_key'), isNull);
    });

    test('activateKey_serverError_returnsError', () async {
      service.setClient(MockClient((_) async => http.Response('', 500)));
      final result = await service.activateKey('sk-ant-valid');
      expect(result, isNotNull);
    });

    test('activateKey_networkError_returnsError', () async {
      service.setClient(MockClient((_) async => throw const SocketException('offline')));
      final result = await service.activateKey('sk-ant-valid');
      expect(result, isNotNull);
    });

    test('activateKey_trimsWhitespace_savesCleanKey', () async {
      service.setClient(MockClient((_) async =>
          http.Response(jsonEncode(_successBody()), 200)));
      await service.activateKey('  sk-ant-trimmed  ');
      expect(await storage.read('claude_api_key'), 'sk-ant-trimmed');
    });
  });

  // ── rewriteNote ───────────────────────────────────────────────────────────

  group('rewriteNote', () {
    test('rewriteNote_noKeyStored_throwsAuthException', () async {
      await expectLater(
        service.rewriteNote('hello'),
        throwsA(isA<ClaudeException>()
            .having((e) => e.kind, 'kind', ClaudeErrorKind.auth)),
      );
    });

    test('rewriteNote_success_returnsRewrittenText', () async {
      await storage.write('claude_api_key', 'sk-ant-valid');
      service.setClient(MockClient((_) async =>
          http.Response(jsonEncode(_successBody(text: 'Better text.')), 200)));
      final result = await service.rewriteNote('Original text.');
      expect(result, 'Better text.');
    });

    test('rewriteNote_401Response_throwsAuthAndClearsVerifiedFlag', () async {
      await storage.write('claude_api_key', 'sk-ant-valid');
      await storage.write('claude_api_key_verified', 'true');
      service.setClient(MockClient((_) async => http.Response('', 401)));
      await expectLater(
        service.rewriteNote('hello'),
        throwsA(isA<ClaudeException>()
            .having((e) => e.kind, 'kind', ClaudeErrorKind.auth)),
      );
      expect(await storage.read('claude_api_key_verified'), 'false');
    });

    test('rewriteNote_429Response_throwsRateLimitException', () async {
      await storage.write('claude_api_key', 'sk-ant-valid');
      service.setClient(MockClient((_) async => http.Response('', 429)));
      await expectLater(
        service.rewriteNote('hello'),
        throwsA(isA<ClaudeException>()
            .having((e) => e.kind, 'kind', ClaudeErrorKind.rateLimit)),
      );
    });

    test('rewriteNote_networkError_throwsNetworkException', () async {
      await storage.write('claude_api_key', 'sk-ant-valid');
      service.setClient(MockClient((_) async => throw const SocketException('offline')));
      await expectLater(
        service.rewriteNote('hello'),
        throwsA(isA<ClaudeException>()
            .having((e) => e.kind, 'kind', ClaudeErrorKind.network)),
      );
    });
  });
}

Map<String, dynamic> _successBody({String text = 'OK'}) => {
  'content': [{'type': 'text', 'text': text}],
};
