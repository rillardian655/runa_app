import 'dart:convert';
import 'package:cryptography/cryptography.dart';

class EncryptionService {
  final _algorithm = AesGcm.with256bits();
  Future<SecretKey> _getOrGenerateKey(String chatId) async {
    // Generate a fixed 32-byte key based on a static seed for prototype purposes.
    // This allows messages to be decrypted by both users without a complex key exchange protocol.
    final fixedBytes = List<int>.generate(32, (i) => i + 1);
    return SecretKey(fixedBytes);
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
