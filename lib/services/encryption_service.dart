import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'secure_storage_service.dart';

class EncryptionService {
  static final EncryptionService instance = EncryptionService._();
  EncryptionService._();

  final _storage = SecureStorageService.instance;
  final _algorithm = AesGcm.with256bits();

  SecretKey? _secretKey;

  bool get isInitialized => _secretKey != null;

  Future<void> initForGoogleUser(String userId) async {
    final storageKey = 'enc_key_$userId';
    var keyBase64 = await _storage.read(storageKey);
    if (keyBase64 == null) {
      final keyBytes = _randomBytes(32);
      keyBase64 = base64Encode(keyBytes);
      await _storage.write(storageKey, keyBase64);
    }
    _secretKey = SecretKey(base64Decode(keyBase64));
  }

  void initWithKey(Uint8List keyBytes) {
    _secretKey = SecretKey(keyBytes);
  }

  void clear() => _secretKey = null;

  Future<String> encrypt(String plaintext) async {
    final key = _secretKey;
    if (key == null) throw StateError('EncryptionService not initialized');
    final nonce = _algorithm.newNonce();
    final secretBox = await _algorithm.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: nonce,
    );
    return jsonEncode({
      'n': base64Encode(secretBox.nonce),
      'm': base64Encode(secretBox.mac.bytes),
      'c': base64Encode(secretBox.cipherText),
    });
  }

  Future<String> decrypt(String ciphertext) async {
    final key = _secretKey;
    if (key == null) throw StateError('EncryptionService not initialized');
    final map = jsonDecode(ciphertext) as Map<String, dynamic>;
    final secretBox = SecretBox(
      base64Decode(map['c'] as String),
      nonce: base64Decode(map['n'] as String),
      mac: Mac(base64Decode(map['m'] as String)),
    );
    final plaintext = await _algorithm.decrypt(secretBox, secretKey: key);
    return utf8.decode(plaintext);
  }

  Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
  }
}
