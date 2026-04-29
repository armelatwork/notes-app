import 'dart:convert';
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

  group('EncryptionService – Drive key methods', () {
    test('tryInitFromLocalStorage_withNoKeyStored_returnsFalse', () async {
      expect(await enc.tryInitFromLocalStorage('user1'), isFalse);
      expect(enc.isInitialized, isFalse);
    });

    test('tryInitFromLocalStorage_afterGenerateAndStore_returnsTrue', () async {
      await enc.generateAndStoreKey('user2');
      enc.clear();
      expect(await enc.tryInitFromLocalStorage('user2'), isTrue);
      expect(enc.isInitialized, isTrue);
    });

    test('generateAndStoreKey_returnsBase64String', () async {
      final key = await enc.generateAndStoreKey('user3');
      expect(key, isNotEmpty);
      expect(base64Decode(key).length, 32);
    });

    test('generateAndStoreKey_thenDecryptWithRestoredKey_succeeds', () async {
      await enc.generateAndStoreKey('user4');
      const plaintext = 'cross-device test';
      final ciphertext = await enc.encrypt(plaintext);

      enc.clear();
      await enc.tryInitFromLocalStorage('user4');
      expect(await enc.decrypt(ciphertext), plaintext);
    });

    test('initWithBase64Key_initializesWithProvidedKey', () async {
      final key = await enc.generateAndStoreKey('user5');
      enc.clear();

      await enc.initWithBase64Key('user5_copy', key);
      const plaintext = 'shared key test';
      final ciphertext = await enc.encrypt(plaintext);

      enc.clear();
      await enc.tryInitFromLocalStorage('user5_copy');
      expect(await enc.decrypt(ciphertext), plaintext);
    });

    test('initWithBase64Key_differentDevice_decryptsOtherDeviceCiphertext',
        () async {
      // Simulate macOS: generate key and encrypt
      final key = await enc.generateAndStoreKey('shared_user');
      const plaintext = 'note from macOS';
      final ciphertext = await enc.encrypt(plaintext);
      enc.clear();

      // Simulate Android: receives key from Drive
      await enc.initWithBase64Key('shared_user_android', key);
      expect(await enc.decrypt(ciphertext), plaintext);
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
