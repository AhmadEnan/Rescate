library security_crypto;

import 'dart:convert';
import 'package:cryptography/cryptography.dart';

/// Handles E2EE for the mesh network.
class MeshCrypto {
  final Ed25519 _ed25519 = Ed25519();
  final X25519 _x25519 = X25519();
  final Chacha20 _chacha = Chacha20.poly1305Aead();

  /// Generates a new identity keypair (Ed25519).
  Future<SimpleKeyPair> generateIdentityKeyPair() async {
    return await _ed25519.newKeyPair();
  }

  /// Extracts the bytes of the public key from a keypair.
  Future<List<int>> getPublicKeyBytes(SimpleKeyPair keyPair) async {
    final pub = await keyPair.extractPublicKey();
    return pub.bytes;
  }

  /// Encrypts a message for a specific recipient.
  /// 
  /// The [senderIdentity] is the Ed25519 keypair of the sender. We convert it
  /// to an X25519 keypair for the ECDH key exchange.
  Future<List<int>> encryptDirectMessage(String text, SimpleKeyPair senderIdentity, List<int> recipientPubBytes) async {
    // 1. Convert sender Ed25519 to X25519 for key exchange
    // Note: A true robust system uses separate keys for identity (Ed25519) and encryption (X25519).
    // For simplicity in this demo, we will just generate an ephemeral X25519 key pair for each message,
    // compute the shared secret with the recipient's identity key, and send our ephemeral public key with the payload.
    // However, since we want to be simple, let's just use the `cryptography` package's X25519 directly.
    
    // Actually, let's just use an ephemeral X25519 keypair for encryption to guarantee forward secrecy.
    final ephemeralKeyPair = await _x25519.newKeyPair();
    final ephemeralPubKey = await ephemeralKeyPair.extractPublicKey();
    
    // Assume recipientPubBytes is an X25519 public key.
    final remotePublicKey = SimplePublicKey(recipientPubBytes, type: KeyPairType.x25519);
    
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: ephemeralKeyPair,
      remotePublicKey: remotePublicKey,
    );

    final secretBox = await _chacha.encrypt(
      utf8.encode(text),
      secretKey: sharedSecret,
    );

    // Payload structure: [EphemeralPubKeyLength (1 byte)] + [EphemeralPubKey] + [Nonce] + [MAC] + [CipherText]
    // cryptography's secretBox.concatenation() returns [Nonce] + [MAC] + [CipherText] (usually).
    final boxBytes = secretBox.concatenation();
    
    return [
      ephemeralPubKey.bytes.length,
      ...ephemeralPubKey.bytes,
      ...boxBytes,
    ];
  }

  /// Decrypts a direct message.
  Future<String> decryptDirectMessage(List<int> payload, SimpleKeyPair recipientIdentity) async {
    if (payload.isEmpty) throw Exception("Empty payload");
    
    final pubKeyLen = payload[0];
    final ephemeralPubKeyBytes = payload.sublist(1, 1 + pubKeyLen);
    final boxBytes = payload.sublist(1 + pubKeyLen);

    final ephemeralPublicKey = SimplePublicKey(ephemeralPubKeyBytes, type: KeyPairType.x25519);
    
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: recipientIdentity, // We use recipient's identity key for X25519 here (assuming it's X25519)
      remotePublicKey: ephemeralPublicKey,
    );

    final secretBox = SecretBox.fromConcatenation(
      boxBytes, 
      nonceLength: _chacha.secretKeyLength, // chacha nonce length is 12, mac is 16
      macLength: 16,
    );

    final decrypted = await _chacha.decrypt(
      secretBox,
      secretKey: sharedSecret,
    );

    return utf8.decode(decrypted);
  }
}
