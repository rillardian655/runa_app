import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class EncryptionService {
  final _storage = const FlutterSecureStorage();
  final _algorithm = AesGcm.with256bits();

  Future<SecretKey> _getOrGenerateKey(String chatId) async {
    final keyString = await _storage.read(key: 'key_\$chatId');
    if (keyString != null) {
      final keyBytes = base64Decode(keyString);
      return SecretKey(keyBytes);
    } else {
      final secretKey = await _algorithm.newSecretKey();
      final keyBytes = await secretKey.extractBytes();
      await _storage.write(key: 'key_\$chatId', value: base64Encode(keyBytes));
      return secretKey;
    }
  }

  Future<String> encryptMessage(String plainText, String chatId) async {
    final secretKey = await _getOrGenerateKey(chatId);
    final secretBox = await _algorithm.encrypt(
      utf8.encode(plainText),
      secretKey: secretKey,
    );
    final concatenated = secretBox.concatenation();
    return base64Encode(concatenated);
  }

  Future<String> decryptMessage(String cipherText, String chatId) async {
    try {
      final secretKey = await _getOrGenerateKey(chatId);
      final decoded = base64Decode(cipherText);
      final secretBox = SecretBox.fromConcatenation(decoded, nonceLength: 12, macLength: 16);
      final clearTextBytes = await _algorithm.decrypt(
        secretBox,
        secretKey: secretKey,
      );
      return utf8.decode(clearTextBytes);
    } catch (e) {
      return "[Encrypted Message]";
    }
  }
}
