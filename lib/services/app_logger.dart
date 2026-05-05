import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

enum LogLevel { debug, info, warn, error }

class AppLogger {
  AppLogger._();
  static final AppLogger instance = AppLogger._();

  static const _maxLogFileSizeBytes = 2 * 1024 * 1024; // 2 MB
  static const _logFileName = 'app.log';

  IOSink? _sink;
  File? _logFile;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized || kIsWeb) return;
    try {
      final dir = await getApplicationSupportDirectory();
      _logFile = File('${dir.path}/$_logFileName');
      await _rotateIfNeeded();
      _sink = _logFile!.openWrite(mode: FileMode.append);
      _initialized = true;
    } catch (e) {
      debugPrint('[AppLogger] init failed: $e');
    }
  }

  Future<void> _rotateIfNeeded() async {
    final file = _logFile!;
    if (!await file.exists()) return;
    if (await file.length() < _maxLogFileSizeBytes) return;
    final backup = File('${file.path}.1');
    await file.rename(backup.path);
    _logFile = File(file.path);
  }

  void debug(String tag, String message) =>
      _log(LogLevel.debug, tag, message);

  void info(String tag, String message) =>
      _log(LogLevel.info, tag, message);

  void warn(String tag, String message, [Object? error]) =>
      _log(LogLevel.warn, tag, message, error);

  void error(String tag, String message, [Object? error]) =>
      _log(LogLevel.error, tag, message, error);

  void _log(LogLevel level, String tag, String message, [Object? error]) {
    final entry = _format(level, tag, message, error);
    debugPrint(entry);
    _sink?.writeln(entry);
  }

  String _format(LogLevel level, String tag, String message, [Object? error]) {
    final ts = DateTime.now().toIso8601String();
    final lvl = level.name.toUpperCase().padRight(5);
    final base = '$ts [$lvl] [$tag] $message';
    return error != null ? '$base — $error' : base;
  }

  Future<void> close() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
    _initialized = false;
  }
}
