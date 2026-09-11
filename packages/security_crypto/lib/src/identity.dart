// Responder identity keys: a distinct Ed25519 signing identity plus a
// separate X25519 key-exchange key (issue #17 requirement — never reuse the
// identity key for ECDH). Seeds are the persisted form; everything else is
// derived on demand so no key material lingers in memory longer than needed.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

final Ed25519 _ed25519 = Ed25519();
final X25519 _x25519 = X25519();

String bytesToHex(List<int> bytes) {
  const digits = '0123456789abcdef';
  final out = StringBuffer();
  for (final b in bytes) {
    out.write(digits[(b >> 4) & 0xF]);
    out.write(digits[b & 0xF]);
  }
  return out.toString();
}

Uint8List hexToBytes(String hex) {
  final clean = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
  if (clean.length.isOdd) {
    throw const FormatException('hex string must have even length');
  }
  final out = Uint8List(clean.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

Uint8List randomBytes(int length) {
  final rng = Random.secure();
  return Uint8List.fromList(
    List<int>.generate(length, (_) => rng.nextInt(256)),
  );
}

/// SHA-256 fingerprint of a public key, lowercase hex.
Future<String> publicKeyFingerprint(List<int> publicKeyBytes) async {
  final hash = await Sha256().hash(publicKeyBytes);
  return bytesToHex(hash.bytes);
}

/// The two keypairs a verified responder keeps on their device.
class ResponderKeys {
  ResponderKeys._(Uint8List identitySeed, Uint8List kxSeed)
      : _identitySeed = Uint8List.fromList(identitySeed),
        _kxSeed = Uint8List.fromList(kxSeed) {
    if (_identitySeed.length != 32 || _kxSeed.length != 32) {
      throw ArgumentError('seeds must be 32 bytes');
    }
  }

  final Uint8List _identitySeed;
  final Uint8List _kxSeed;

  static Future<ResponderKeys> generate() async => ResponderKeys._(
        randomBytes(32),
        randomBytes(32),
      );

  factory ResponderKeys.fromSeeds(List<int> identitySeed, List<int> kxSeed) =>
      ResponderKeys._(Uint8List.fromList(identitySeed),
          Uint8List.fromList(kxSeed));

  Future<SimpleKeyPair> get identityKeyPair =>
      _ed25519.newKeyPairFromSeed(_identitySeed);
  Future<SimpleKeyPair> get keyExchangeKeyPair =>
      _x25519.newKeyPairFromSeed(_kxSeed);

  Future<List<int>> identityPublicBytes() async =>
      (await (await identityKeyPair).extractPublicKey()).bytes;
  Future<List<int>> keyExchangePublicBytes() async =>
      (await (await keyExchangeKeyPair).extractPublicKey()).bytes;

  /// Signs a handshake transcript with the Ed25519 identity key.
  Future<List<int>> signWithIdentity(List<int> message) async {
    final signature =
        await _ed25519.sign(message, keyPair: await identityKeyPair);
    return signature.bytes;
  }

  bool sameKeys(ResponderKeys other) =>
      bytesToHex(_identitySeed) == bytesToHex(other._identitySeed) &&
      bytesToHex(_kxSeed) == bytesToHex(other._kxSeed);

  /// SECRET. Contains both raw private seeds — the responder's entire
  /// identity. This is the secure-storage serialization only: it must never
  /// be written to a file, logged, or sent over the wire. See
  /// [ConsultKeyStore.saveResponderKeys].
  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': 1,
        'type': 'rescate_responder_keys',
        'identity_seed': base64Encode(_identitySeed),
        'kx_seed': base64Encode(_kxSeed),
      };

  static ResponderKeys fromJson(Map<String, dynamic> json) =>
      ResponderKeys._(
        base64Decode(json['identity_seed'] as String),
        base64Decode(json['kx_seed'] as String),
      );
}

/// The medical authority that signs responder credentials. Its Ed25519
/// public key is pinned in the app; the private key never leaves the
/// provisioning machine.
class ConsultAuthority {
  ConsultAuthority._();

  /// Public key of the Rescate Medical Authority. Verify with
  /// `verifyAuthoritySignature` before trusting any credential.
  /// (Generated 2026-09-06; private key kept offline by the coordinator —
  /// see packages/security_crypto/tool/credential_provisioner.dart.)
  static const String defaultPublicKeyHex =
      '11bf0e3bb33dfbd1827cd7163f6e890072beed267cd51600409da12509d64742';

  static SimplePublicKey defaultPublicKey() => SimplePublicKey(
        hexToBytes(defaultPublicKeyHex),
        type: KeyPairType.ed25519,
      );

  static Future<SimpleKeyPair> newAuthorityKeyPair() =>
      _ed25519.newKeyPair();

  static Future<SimpleKeyPair> authorityKeyPairFromSeed(List<int> seed) =>
      _ed25519.newKeyPairFromSeed(seed);

  static Future<bool> verifyAuthoritySignature(
    List<int> message,
    List<int> signatureBytes, {
    List<int>? authorityPublicKey,
  }) {
    final pk = SimplePublicKey(
      authorityPublicKey ?? hexToBytes(defaultPublicKeyHex),
      type: KeyPairType.ed25519,
    );
    return _ed25519.verify(
      message,
      signature: Signature(signatureBytes, publicKey: pk),
    );
  }
}

/// Exposed for tests and the provisioning tool.
Future<bool> verifyEd25519(
  List<int> message,
  List<int> signatureBytes,
  List<int> publicKeyBytes,
) async {
  return _ed25519.verify(
    message,
    signature: Signature(
      signatureBytes,
      publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519),
    ),
  );
}

Future<List<int>> signEd25519(
  List<int> message,
  SimpleKeyPair keyPair,
) async {
  final signature = await _ed25519.sign(message, keyPair: keyPair);
  return signature.bytes;
}
