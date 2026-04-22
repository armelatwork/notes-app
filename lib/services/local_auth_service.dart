import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import '../models/app_user.dart';
import 'secure_storage_service.dart';

class LocalAuthService {
  static final LocalAuthService instance = LocalAuthService._();
  LocalAuthService._();

  final _storage = SecureStorageService.instance;
  static const _usernameKey = 'local_username';
  static const _hashKey = 'local_password_hash';
  static const _saltKey = 'local_password_salt';

  Future<bool> accountExists() async {
    final username = await _storage.read(_usernameKey);
    return username != null;
  }

  Future<AppUser?> createAccount(String username, String password) async {
    if (await accountExists()) return null;
    final salt = _generateSalt();
    final hash = await _hashPassword(password, salt);
    await _storage.write(_usernameKey, username);
    await _storage.write(_hashKey, hash);
    await _storage.write(_saltKey, salt);
    return AppUser(id: username, displayName: username, type: AuthType.local);
  }

  Future<void> signOut() async {
    // Encryption key is held only in memory and cleared by EncryptionService.
  }

  Future<AppUser?> signIn(String username, String password) async {
    final storedUsername = await _storage.read(_usernameKey);
    final storedHash = await _storage.read(_hashKey);
    final salt = await _storage.read(_saltKey);
    if (storedUsername == null || storedHash == null || salt == null) return null;
    if (storedUsername != username) return null;
    final hash = await _hashPassword(password, salt);
    if (hash != storedHash) return null;
    return AppUser(id: username, displayName: username, type: AuthType.local);
  }

  Future<Uint8List> deriveEncryptionKey(String password) async {
    final salt = await _storage.read(_saltKey) ?? 'fallback_salt';
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 100000,
      bits: 256,
    );
    final secretKey = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: utf8.encode('enc_$salt'),
    );
    return Uint8List.fromList(await secretKey.extractBytes());
  }

  String _generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Encode(bytes);
  }

  Future<String> _hashPassword(String password, String salt) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 100000,
      bits: 256,
    );
    final secretKey = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: utf8.encode('auth_$salt'),
    );
    return base64Encode(await secretKey.extractBytes());
  }
}
