import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/models/app_user.dart';
import 'package:notes_app/services/local_auth_service.dart';
import 'package:notes_app/services/secure_storage_service.dart';

void main() {
  late Directory tempDir;
  final auth = LocalAuthService.instance;
  final storage = SecureStorageService.instance;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('local_auth_test_');
    storage.setTestDirectory(tempDir.path);
  });

  tearDown(() async {
    storage.clearTestDirectory();
    await tempDir.delete(recursive: true);
  });

  group('LocalAuthService – accountExists', () {
    test('returns false when no account has been created', () async {
      expect(await auth.accountExists(), isFalse);
    });

    test('returns true after account is created', () async {
      await auth.createAccount('alice', 'password123');
      expect(await auth.accountExists(), isTrue);
    });
  });

  group('LocalAuthService – createAccount', () {
    test('returns AppUser on success', () async {
      final user = await auth.createAccount('alice', 'password123');
      expect(user, isNotNull);
      expect(user!.displayName, 'alice');
      expect(user.id, 'alice');
      expect(user.type, AuthType.local);
    });

    test('returns null if account already exists', () async {
      await auth.createAccount('alice', 'password123');
      final duplicate = await auth.createAccount('alice', 'other');
      expect(duplicate, isNull);
    });

    test('returns null for second account even with different username', () async {
      await auth.createAccount('alice', 'password123');
      // Only one local account is supported
      final second = await auth.createAccount('bob', 'password456');
      expect(second, isNull);
    });
  });

  group('LocalAuthService – signIn', () {
    setUp(() async {
      await auth.createAccount('alice', 'correct_password');
    });

    test('returns AppUser with correct credentials', () async {
      final user = await auth.signIn('alice', 'correct_password');
      expect(user, isNotNull);
      expect(user!.displayName, 'alice');
      expect(user.type, AuthType.local);
    });

    test('returns null for wrong password', () async {
      final user = await auth.signIn('alice', 'wrong_password');
      expect(user, isNull);
    });

    test('returns null for wrong username', () async {
      final user = await auth.signIn('bob', 'correct_password');
      expect(user, isNull);
    });

    test('returns null when no account exists', () async {
      // Use fresh storage with no account
      final freshDir =
          await Directory.systemTemp.createTemp('local_auth_fresh_');
      storage.setTestDirectory(freshDir.path);
      final user = await auth.signIn('alice', 'correct_password');
      expect(user, isNull);
      storage.setTestDirectory(tempDir.path);
      await freshDir.delete(recursive: true);
    });

    test('is case-sensitive for password', () async {
      final user = await auth.signIn('alice', 'Correct_Password');
      expect(user, isNull);
    });
  });

  group('LocalAuthService – deriveEncryptionKey', () {
    setUp(() async {
      await auth.createAccount('alice', 'my_password');
    });

    test('returns 32 bytes', () async {
      final key = await auth.deriveEncryptionKey('my_password');
      expect(key.length, 32);
    });

    test('same password produces same key', () async {
      final key1 = await auth.deriveEncryptionKey('my_password');
      final key2 = await auth.deriveEncryptionKey('my_password');
      expect(key1, key2);
    });

    test('different passwords produce different keys', () async {
      final key1 = await auth.deriveEncryptionKey('my_password');
      final key2 = await auth.deriveEncryptionKey('other_password');
      expect(key1, isNot(key2));
    });
  });

  group('LocalAuthService – signOut', () {
    test('completes without error', () async {
      await auth.createAccount('alice', 'password');
      await expectLater(auth.signOut(), completes);
    });
  });
}
