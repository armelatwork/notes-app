import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notes_app/services/ai_service.dart';
import 'package:notes_app/services/openai_api_service.dart';
import 'package:notes_app/services/secure_storage_service.dart';

void main() {
  late Directory tempDir;
  final service = OpenAiApiService.instance;
  final storage = SecureStorageService.instance;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('openai_api_service_test_');
    storage.setTestDirectory(tempDir.path);
  });

  tearDown(() async {
    service.setClient(http.Client());
    storage.clearTestDirectory();
    await tempDir.delete(recursive: true);
  });

  group('isVerified', () {
    test('isVerified_noKeyStored_returnsFalse', () async {
      expect(await service.isVerified(), isFalse);
    });

    test('isVerified_verifiedFlagTrue_returnsTrue', () async {
      await storage.write('openai_api_key_verified', 'true');
      expect(await service.isVerified(), isTrue);
    });
  });

  group('clearKey', () {
    test('clearKey_withStoredKey_removesKeyAndVerifiedFlag', () async {
      await storage.write('openai_api_key', 'sk-test');
      await storage.write('openai_api_key_verified', 'true');
      await service.clearKey();
      expect(await storage.read('openai_api_key'), isNull);
      expect(await storage.read('openai_api_key_verified'), isNull);
    });
  });

  group('activateKey', () {
    test('activateKey_emptyKey_returnsError', () async {
      expect(await service.activateKey('   '), isNotNull);
    });

    test('activateKey_validKey_savesKeyAndReturnsNull', () async {
      service.setClient(MockClient((_) async =>
          http.Response(jsonEncode(_successBody()), 200)));
      final result = await service.activateKey('sk-valid');
      expect(result, isNull);
      expect(await storage.read('openai_api_key'), 'sk-valid');
      expect(await storage.read('openai_api_key_verified'), 'true');
    });

    test('activateKey_invalidKey_returnsErrorAndDoesNotSave', () async {
      service.setClient(MockClient((_) async => http.Response('', 401)));
      final result = await service.activateKey('sk-bad');
      expect(result, isNotNull);
      expect(await storage.read('openai_api_key'), isNull);
    });

    test('activateKey_trimsWhitespace_savesCleanKey', () async {
      service.setClient(MockClient((_) async =>
          http.Response(jsonEncode(_successBody()), 200)));
      await service.activateKey('  sk-trimmed  ');
      expect(await storage.read('openai_api_key'), 'sk-trimmed');
    });
  });

  group('rewriteNote', () {
    test('rewriteNote_noKeyStored_throwsAuthException', () async {
      await expectLater(
        service.rewriteNote('hello'),
        throwsA(isA<AiException>()
            .having((e) => e.kind, 'kind', AiErrorKind.auth)),
      );
    });

    test('rewriteNote_success_returnsRewrittenText', () async {
      await storage.write('openai_api_key', 'sk-valid');
      service.setClient(MockClient((_) async =>
          http.Response(jsonEncode(_successBody(text: 'Better text.')), 200)));
      final result = await service.rewriteNote('Original text.');
      expect(result, 'Better text.');
    });

    test('rewriteNote_401Response_throwsAuthAndClearsVerifiedFlag', () async {
      await storage.write('openai_api_key', 'sk-valid');
      await storage.write('openai_api_key_verified', 'true');
      service.setClient(MockClient((_) async => http.Response('', 401)));
      await expectLater(
        service.rewriteNote('hello'),
        throwsA(isA<AiException>()
            .having((e) => e.kind, 'kind', AiErrorKind.auth)),
      );
      expect(await storage.read('openai_api_key_verified'), 'false');
    });

    test('rewriteNote_429Response_throwsRateLimitException', () async {
      await storage.write('openai_api_key', 'sk-valid');
      service.setClient(MockClient((_) async => http.Response('', 429)));
      await expectLater(
        service.rewriteNote('hello'),
        throwsA(isA<AiException>()
            .having((e) => e.kind, 'kind', AiErrorKind.rateLimit)),
      );
    });

    test('rewriteNote_networkError_throwsNetworkException', () async {
      await storage.write('openai_api_key', 'sk-valid');
      service.setClient(MockClient(
          (_) async => throw const SocketException('offline')));
      await expectLater(
        service.rewriteNote('hello'),
        throwsA(isA<AiException>()
            .having((e) => e.kind, 'kind', AiErrorKind.network)),
      );
    });
  });
}

Map<String, dynamic> _successBody({String text = 'OK'}) => {
  'choices': [
    {'message': {'role': 'assistant', 'content': text}}
  ],
};
