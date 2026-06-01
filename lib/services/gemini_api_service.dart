import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'ai_service.dart';
import 'app_logger.dart';
import 'secure_storage_service.dart';

class GeminiApiService implements AiService {
  static final GeminiApiService instance = GeminiApiService._();
  GeminiApiService._();

  static const _keyApiKey = 'gemini_api_key';
  static const _keyVerified = 'gemini_api_key_verified';
  static const _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent';
  static const _activateTimeout = Duration(seconds: 20);
  static const _rewriteTimeout = Duration(seconds: 60);

  http.Client _client = http.Client();

  @visibleForTesting
  void setClient(http.Client client) => _client = client;

  Future<String?> readKey() => SecureStorageService.instance.read(_keyApiKey);

  @override
  Future<bool> isVerified() async {
    final flag = await SecureStorageService.instance.read(_keyVerified);
    return flag == 'true';
  }

  @override
  Future<void> clearKey() =>
      SecureStorageService.instance.deleteKeys([_keyApiKey, _keyVerified]);

  @override
  Future<String?> activateKey(String apiKey) async {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) return 'Please enter an API key.';
    final error = await _testKey(trimmed);
    if (error != null) return error;
    await SecureStorageService.instance.write(_keyApiKey, trimmed);
    await SecureStorageService.instance.write(_keyVerified, 'true');
    AppLogger.instance.info('GeminiApiService', 'API key activated');
    return null;
  }

  Future<String?> _testKey(String apiKey) async {
    try {
      final response = await _post(
        apiKey: apiKey,
        body: _buildBody('hi', maxTokens: 1),
        timeout: _activateTimeout,
      );
      if (response.statusCode == 200) return null;
      if (response.statusCode == 400 || response.statusCode == 401 ||
          response.statusCode == 403) {
        return 'Invalid API key. Check your key and try again.';
      }
      return 'Activation failed (HTTP ${response.statusCode}). Try again later.';
    } on TimeoutException {
      return 'Connection timed out. Check your network and try again.';
    } on SocketException {
      return 'No internet connection.';
    } catch (e) {
      AppLogger.instance.error('GeminiApiService', 'testKey failed', e);
      return 'An unexpected error occurred.';
    }
  }

  @override
  Future<String> rewriteNote(String plainText) async {
    final apiKey = await readKey();
    if (apiKey == null) throw const AiException(AiErrorKind.auth);
    try {
      final response = await _post(
        apiKey: apiKey,
        body: _buildBody('$kRewritePrompt$plainText', maxTokens: 4096),
        timeout: _rewriteTimeout,
      );
      if (response.statusCode == 401 || response.statusCode == 403) {
        await SecureStorageService.instance.write(_keyVerified, 'false');
        throw const AiException(AiErrorKind.auth);
      }
      if (response.statusCode == 429) throw const AiException(AiErrorKind.rateLimit);
      if (response.statusCode != 200) throw const AiException(AiErrorKind.server);
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = json['candidates'] as List;
      return candidates.first['content']['parts'].first['text'] as String;
    } on AiException {
      rethrow;
    } on TimeoutException {
      throw const AiException(AiErrorKind.timeout);
    } on SocketException {
      throw const AiException(AiErrorKind.network);
    }
  }

  Future<http.Response> _post({
    required String apiKey,
    required Map<String, dynamic> body,
    required Duration timeout,
  }) =>
      _client
          .post(
            Uri.parse('$_baseUrl?key=$apiKey'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(timeout);

  Map<String, dynamic> _buildBody(String prompt, {required int maxTokens}) => {
        'contents': [
          {
            'parts': [
              {'text': prompt}
            ]
          }
        ],
        'generationConfig': {'maxOutputTokens': maxTokens},
      };
}
