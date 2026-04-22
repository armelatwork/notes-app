import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/services/encryption_service.dart';
import 'package:notes_app/services/secure_storage_service.dart';

void main() {
  late Directory tempDir;
  final enc = EncryptionService.instance;
  final storage = SecureStorageService.instance;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('enc_test_');
    storage.setTestDirectory(tempDir.path);
    enc.clear();
  });

  tearDown(() async {
    enc.clear();
    storage.clearTestDirectory();
    await tempDir.delete(recursive: true);
  });

  group('EncryptionService – initialization', () {
    test('isInitialized is false before init', () {
      expect(enc.isInitialized, isFalse);
    });

    test('initForGoogleUser sets isInitialized', () async {
      await enc.initForGoogleUser('user123');
      expect(enc.isInitialized, isTrue);
    });

    test('initWithKey sets isInitialized', () {
      enc.initWithKey(Uint8List(32));
      expect(enc.isInitialized, isTrue);
    });

    test('clear resets isInitialized', () async {
      await enc.initForGoogleUser('user123');
      enc.clear();
      expect(enc.isInitialized, isFalse);
    });

    test('initForGoogleUser persists the same key across calls', () async {
      await enc.initForGoogleUser('user_persist');
      const plaintext = 'hello world';
      final ciphertext = await enc.encrypt(plaintext);

      // Re-init for same user — should reload stored key
      enc.clear();
      await enc.initForGoogleUser('user_persist');
      final decrypted = await enc.decrypt(ciphertext);
      expect(decrypted, plaintext);
    });

    test('different user IDs produce different keys', () async {
      await enc.initForGoogleUser('userA');
      const plaintext = 'secret';
      final ciphertextA = await enc.encrypt(plaintext);

      enc.clear();
      await enc.initForGoogleUser('userB');
      // Decrypting A's ciphertext with B's key should throw
      expect(() => enc.decrypt(ciphertextA), throwsA(anything));
    });
  });

  group('EncryptionService – encrypt / decrypt', () {
    setUp(() => enc.initWithKey(Uint8List(32)));

    test('decrypt(encrypt(x)) == x', () async {
      const plaintext = 'The quick brown fox';
      final ciphertext = await enc.encrypt(plaintext);
      expect(await enc.decrypt(ciphertext), plaintext);
    });

    test('round-trip preserves empty string', () async {
      final ciphertext = await enc.encrypt('');
      expect(await enc.decrypt(ciphertext), '');
    });

    test('round-trip preserves JSON content (Quill delta)', () async {
      const delta = '{"ops":[{"insert":"Hello\\n"}]}';
      final ciphertext = await enc.encrypt(delta);
      expect(await enc.decrypt(ciphertext), delta);
    });

    test('round-trip preserves unicode', () async {
      const text = 'こんにちは 🌍';
      expect(await enc.decrypt(await enc.encrypt(text)), text);
    });

    test('same plaintext produces different ciphertexts (random nonce)', () async {
      const plaintext = 'same input';
      final c1 = await enc.encrypt(plaintext);
      final c2 = await enc.encrypt(plaintext);
      expect(c1, isNot(c2));
    });

    test('ciphertext is not the plaintext', () async {
      const plaintext = 'sensitive data';
      final ciphertext = await enc.encrypt(plaintext);
      expect(ciphertext, isNot(contains('sensitive data')));
    });
  });

  group('EncryptionService – uninitialized errors', () {
    test('encrypt throws StateError when not initialized', () async {
      expect(() => enc.encrypt('x'), throwsStateError);
    });

    test('decrypt throws StateError when not initialized', () async {
      expect(() => enc.decrypt('{}'), throwsStateError);
    });
  });
}
