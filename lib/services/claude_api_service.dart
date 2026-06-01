import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'app_logger.dart';
import 'secure_storage_service.dart';

enum ClaudeErrorKind { auth, rateLimit, network, timeout, server }

class ClaudeException implements Exception {
  final ClaudeErrorKind kind;
  const ClaudeException(this.kind);

  @override
  String toString() => 'ClaudeException(kind: $kind)';
}

class ClaudeApiService {
  static final ClaudeApiService instance = ClaudeApiService._();
  ClaudeApiService._();

  static const _keyApiKey = 'claude_api_key';
  static const _keyVerified = 'claude_api_key_verified';
  static const _apiUrl = 'https://api.anthropic.com/v1/messages';
  static const _model = 'claude-haiku-4-5-20251001';
  static const _activateTimeout = Duration(seconds: 20);
  static const _rewriteTimeout = Duration(seconds: 60);

  http.Client _client = http.Client();

  @visibleForTesting
  void setClient(http.Client client) => _client = client;

  Future<String?> readKey() => SecureStorageService.instance.read(_keyApiKey);

  Future<bool> isVerified() async {
    final flag = await SecureStorageService.instance.read(_keyVerified);
    return flag == 'true';
  }

  Future<void> clearKey() =>
      SecureStorageService.instance.deleteKeys([_keyApiKey, _keyVerified]);

  /// Returns null on success, or a user-facing error message on failure.
  Future<String?> activateKey(String apiKey) async {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) return 'Please enter an API key.';
    final error = await _testKey(trimmed);
    if (error != null) return error;
    await SecureStorageService.instance.write(_keyApiKey, trimmed);
    await SecureStorageService.instance.write(_keyVerified, 'true');
    AppLogger.instance.info('ClaudeApiService', 'API key activated');
    return null;
  }

  Future<String?> _testKey(String apiKey) async {
    try {
      final response = await _post(
        apiKey: apiKey,
        body: _buildBody(prompt: 'hi', maxTokens: 1),
        timeout: _activateTimeout,
      );
      if (response.statusCode == 200) return null;
      if (response.statusCode == 401) return 'Invalid API key. Check your key and try again.';
      return 'Activation failed (HTTP ${response.statusCode}). Try again later.';
    } on TimeoutException {
      return 'Connection timed out. Check your network and try again.';
    } on SocketException {
      return 'No internet connection.';
    } catch (e) {
      AppLogger.instance.error('ClaudeApiService', 'testKey failed', e);
      return 'An unexpected error occurred.';
    }
  }

  Future<String> rewriteNote(String plainText) async {
    final apiKey = await readKey();
    if (apiKey == null) throw const ClaudeException(ClaudeErrorKind.auth);
    try {
      final response = await _post(
        apiKey: apiKey,
        body: _buildBody(
          prompt: 'Rewrite the following note to be clearer and better written. '
              'Use plain paragraphs and headings only — do not use dashes or hyphens as list markers. '
              'A dash may only appear as a subtraction operator in a math expression. '
              'Return only the rewritten text, no explanations or commentary:\n\n$plainText',
          maxTokens: 4096,
        ),
        timeout: _rewriteTimeout,
      );
      if (response.statusCode == 401) {
        await SecureStorageService.instance.write(_keyVerified, 'false');
        throw const ClaudeException(ClaudeErrorKind.auth);
      }
      if (response.statusCode == 429) throw const ClaudeException(ClaudeErrorKind.rateLimit);
      if (response.statusCode != 200) throw const ClaudeException(ClaudeErrorKind.server);
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return (json['content'] as List).first['text'] as String;
    } on ClaudeException {
      rethrow;
    } on TimeoutException {
      throw const ClaudeException(ClaudeErrorKind.timeout);
    } on SocketException {
      throw const ClaudeException(ClaudeErrorKind.network);
    }
  }

  Future<http.Response> _post({
    required String apiKey,
    required Map<String, dynamic> body,
    required Duration timeout,
  }) =>
      _client
          .post(
            Uri.parse(_apiUrl),
            headers: {
              'x-api-key': apiKey,
              'anthropic-version': '2023-06-01',
              'content-type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);

  Map<String, dynamic> _buildBody({
    required String prompt,
    required int maxTokens,
  }) =>
      {
        'model': _model,
        'max_tokens': maxTokens,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
      };
}
