import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/services/secure_storage_service.dart';

void main() {
  late Directory tempDir;
  final storage = SecureStorageService.instance;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('secure_storage_test_');
    storage.setTestDirectory(tempDir.path);
  });

  tearDown(() async {
    storage.clearTestDirectory();
    await tempDir.delete(recursive: true);
  });

  group('SecureStorageService', () {
    test('read returns null for missing key', () async {
      expect(await storage.read('nonexistent'), isNull);
    });

    test('write then read returns the value', () async {
      await storage.write('key1', 'value1');
      expect(await storage.read('key1'), 'value1');
    });

    test('write overwrites existing value', () async {
      await storage.write('key1', 'first');
      await storage.write('key1', 'second');
      expect(await storage.read('key1'), 'second');
    });

    test('multiple keys coexist independently', () async {
      await storage.write('a', 'alpha');
      await storage.write('b', 'beta');
      expect(await storage.read('a'), 'alpha');
      expect(await storage.read('b'), 'beta');
    });

    test('delete removes a key', () async {
      await storage.write('key1', 'value1');
      await storage.delete('key1');
      expect(await storage.read('key1'), isNull);
    });

    test('delete of non-existent key does not throw', () async {
      await expectLater(storage.delete('ghost'), completes);
    });

    test('deleting one key does not affect others', () async {
      await storage.write('keep', 'yes');
      await storage.write('remove', 'no');
      await storage.delete('remove');
      expect(await storage.read('keep'), 'yes');
      expect(await storage.read('remove'), isNull);
    });

    test('persists across separate read calls', () async {
      await storage.write('persist', 'data');
      // Re-read without writing again
      expect(await storage.read('persist'), 'data');
      expect(await storage.read('persist'), 'data');
    });

    test('stores values with special characters', () async {
      const value = '{"ops":[{"insert":"hello\\n"}]}';
      await storage.write('json_key', value);
      expect(await storage.read('json_key'), value);
    });
  });
}
