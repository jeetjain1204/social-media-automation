// file: linkedin_token_crypto.dart
// OPT: Harden config validation, authenticated decryption (AES-GCM with tag), and robust parsing.
// OPT: Preserve API: same function name + return type + behavior (decrypt a base64 combined blob to cleartext).
// OPT: No core data shape changes; no external dependencies added beyond existing imports.

import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

import 'package:blob/config/app_config.dart';

/// Source of truth for the encryption key:
/// - Uses AppConfig for centralized configuration
/// - Prefer compile-time `--dart-define=ENCRYPTION_KEY`
/// - Fallback to runtime `.env` via flutter_dotenv
///
/// Requirements:
/// - Provide at least 32 bytes of entropy. We derive a 256-bit key via HKDF
///   to normalize length and avoid weak short keys.
/// - DO NOT check this into source control; never log this value.
final String rawKey = AppConfig.encryptionKey;

/// Decrypts a base64-encoded blob in the framing:
/// [12-byte IV][ciphertext][16-byte GCM tag]
///
/// Notes:
/// - We *verify* the tag (integrity/authenticity). If verification fails,
///   a SecretBoxAuthenticationError is thrown.
/// - We use HKDF-SHA256 to derive a 32-byte key from the provided raw string,
///   allowing variable-length secrets while standardizing to AES-256 key size.
/// - Behavior preserved: returns the original plaintext token string on success.
///
/// Throws:
/// - FormatException for malformed base64
/// - StateError for config issues
/// - SecretBoxAuthenticationError if tag verification fails (wrong key/blob)
Future<String> decryptLinkedInToken(String base64Combined) async {
  if (rawKey.isEmpty) {
    // Redundant guard; should be caught in initializer but kept for safety.
    throw StateError('Missing ENCRYPTION_KEY at runtime');
  }

  // 1) Decode base64 safely.
  final Uint8List combined;
  try {
    combined = base64.decode(base64Combined);
  } on FormatException {
    // OPT: Clear error for DX without leaking secrets.
    throw const FormatException(
        'Invalid base64 payload for LinkedIn token blob');
  }

  // 2) Validate minimum length: 12 (IV) + 16 (GCM tag) + 1 (ciphertext min)
  if (combined.length < 12 + 16 + 1) {
    throw const FormatException('Encrypted blob too short');
  }

  // 3) Parse framing: IV (12), ciphertext (n-28), tag (16)
  final iv = combined.sublist(0, 12);
  final tag = combined.sublist(combined.length - 16);
  final cipher = combined.sublist(12, combined.length - 16);

  // 4) Key derivation: HKDF-SHA256 to 32 bytes (AES-256)
  //    Info/salt are static here to normalize; if you ever support key rotation,
  //    you can prefix a keyId byte and switch on it without changing API.
  final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  final derivedKeyBytes = await hkdf.deriveKey(
    secretKey: SecretKey(
      utf8.encode(rawKey),
    ),
    // OPT: Static salt+info to avoid requiring storage changes; do not treat as secret.
    nonce: utf8.encode('blob.linkedIn.hkdf.salt.v1'),
    info: utf8.encode('blob.linkedIn.hkdf.info.v1'),
  );
  final secretKey = SecretKey(await derivedKeyBytes.extractBytes());

  // 5) AES-GCM with tag verification.
  final algorithm = AesGcm.with256bits();

  // Compose the SecretBox with cipher + tag explicitly.
  final box = SecretBox(
    cipher,
    nonce: iv,
    mac: Mac(tag),
  );

  final clearBytes = await algorithm.decrypt(
    box,
    secretKey: secretKey,
  );

  // 6) Decode UTF-8 token.
  return utf8.decode(clearBytes);
}
