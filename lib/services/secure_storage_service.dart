import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'app_logger.dart';

// Stores key-value pairs as JSON in the app's sandboxed support directory.
// On macOS the sandbox blocks all other processes from reading this file.
class SecureStorageService {
  static final SecureStorageService instance = SecureStorageService._();
  SecureStorageService._();

  String? _testDirectoryPath;

  @visibleForTesting
  void setTestDirectory(String path) => _testDirectoryPath = path;

  @visibleForTesting
  void clearTestDirectory() => _testDirectoryPath = null;

  Future<File> _storageFile() async {
    final dirPath =
        _testDirectoryPath ?? (await getApplicationSupportDirectory()).path;
    return File('$dirPath/.app_secure_store');
  }

  Future<Map<String, String>> _readAll() async {
    final file = await _storageFile();
    if (!await file.exists()) return {};
    try {
      final content = await file.readAsString();
      final map = jsonDecode(content) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, v as String));
    } catch (e) {
      AppLogger.instance.error('SecureStorageService', 'failed to read storage file', e);
      return {};
    }
  }

  Future<void> _writeAll(Map<String, String> data) async {
    final file = await _storageFile();
    await file.writeAsString(jsonEncode(data));
  }

  Future<String?> read(String key) async {
    final data = await _readAll();
    return data[key];
  }

  Future<void> write(String key, String value) async {
    final data = await _readAll();
    data[key] = value;
    await _writeAll(data);
  }

  Future<void> delete(String key) async {
    final data = await _readAll();
    data.remove(key);
    await _writeAll(data);
  }
}
