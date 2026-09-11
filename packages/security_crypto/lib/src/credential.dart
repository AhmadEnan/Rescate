// The responder "ID badge": a statement signed by the Rescate Medical
// Authority (RMA) binding a responder's real-world identity to two public
// keys — their Ed25519 identity key and their X25519 key-exchange key.
// The badge contains only public material; possession of the file grants
// nothing without the matching private keys (see session.dart handshake).
import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'identity.dart';

enum ResponderRole {
  doctor,
  nurse,
  emt;

  static ResponderRole fromName(String? name) =>
      ResponderRole.values.firstWhere(
        (r) => r.name == name,
        orElse: () => ResponderRole.doctor,
      );

  String get title {
    switch (this) {
      case ResponderRole.doctor:
        return 'Doctor';
      case ResponderRole.nurse:
        return 'Nurse';
      case ResponderRole.emt:
        return 'EMT';
    }
  }
}

/// Payload a responder phone exports for the authority to sign.
class BadgeRequest {
  BadgeRequest({
    required this.identityPublicKey,
    required this.keyExchangePublicKey,
    this.displayName = '',
    this.deviceName = '',
    required this.createdAt,
  });

  final List<int> identityPublicKey;
  final List<int> keyExchangePublicKey;
  final String displayName;
  final String deviceName;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': 1,
        'type': 'rescate_badge_request',
        'identity_pub': bytesToHex(identityPublicKey),
        'kx_pub': bytesToHex(keyExchangePublicKey),
        'display_name': displayName,
        'device_name': deviceName,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  String encode() => jsonEncode(toJson());

  static BadgeRequest fromJson(Map<String, dynamic> json) => BadgeRequest(
        identityPublicKey: hexToBytes(json['identity_pub'] as String),
        keyExchangePublicKey: hexToBytes(json['kx_pub'] as String),
        displayName: (json['display_name'] as String?) ?? '',
        deviceName: (json['device_name'] as String?) ?? '',
        createdAt:
            DateTime.parse(json['created_at'] as String? ?? DateTime.now().toUtc().toIso8601String()),
      );

  static BadgeRequest decode(String raw) =>
      BadgeRequest.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

/// A signed responder badge. [signature] covers the canonical JSON of the
/// body fields (everything except the signature itself).
class ResponderCredential {
  ResponderCredential({
    required this.subjectFingerprint,
    required this.keyExchangeFingerprint,
    required this.name,
    required this.role,
    required this.specialty,
    required this.licenseRef,
    required this.issuedAt,
    this.expiresAt,
    required this.signature,
  });

  final String subjectFingerprint; // hex SHA-256 of Ed25519 identity public key
  final String keyExchangeFingerprint; // hex SHA-256 of X25519 static public key
  final String name;
  final ResponderRole role;
  final String specialty;
  final String licenseRef;
  final DateTime issuedAt;

  /// Reserved for v2 — always null in v1 (badges do not expire).
  final DateTime? expiresAt;

  /// Base64 Ed25519 signature by the authority over [canonicalBodyJson].
  final String signature;

  Map<String, dynamic> bodyMap() => <String, dynamic>{
        'version': 1,
        'type': 'rescate_badge',
        'subject_fp': subjectFingerprint,
        'kx_fp': keyExchangeFingerprint,
        'name': name,
        'role': role.name,
        'specialty': specialty,
        'license_ref': licenseRef,
        'issued_at': issuedAt.toUtc().toIso8601String(),
        if (expiresAt != null) 'expires_at': expiresAt!.toUtc().toIso8601String(),
      };

  /// Deterministic serialization — issuer and verifier must agree byte for
  /// byte. Dart maps preserve insertion order and jsonEncode is stable for
  /// ASCII-safe strings, so encoding [bodyMap] directly is canonical.
  String canonicalBodyJson() => jsonEncode(bodyMap());

  Map<String, dynamic> toEnvelopeJson() => <String, dynamic>{
        ...bodyMap(),
        'signature': signature,
      };

  String encode() => jsonEncode(toEnvelopeJson());

  static ResponderCredential fromEnvelopeJson(Map<String, dynamic> json) {
    final signature = json['signature'];
    if (signature is! String || signature.isEmpty) {
      throw const FormatException('badge envelope missing signature');
    }
    return ResponderCredential(
      subjectFingerprint: json['subject_fp'] as String,
      keyExchangeFingerprint: json['kx_fp'] as String,
      name: json['name'] as String? ?? '',
      role: ResponderRole.fromName(json['role'] as String?),
      specialty: json['specialty'] as String? ?? '',
      licenseRef: json['license_ref'] as String? ?? '',
      issuedAt: DateTime.parse(json['issued_at'] as String),
      expiresAt: json['expires_at'] == null
          ? null
          : DateTime.parse(json['expires_at'] as String),
      signature: signature,
    );
  }

  static ResponderCredential decode(String raw) =>
      ResponderCredential.fromEnvelopeJson(jsonDecode(raw) as Map<String, dynamic>);

  /// Signs a badge with the authority key. Only ever runs on the
  /// provisioning machine — the app never calls this.
  static Future<ResponderCredential> issue({
    required List<int> identityPublicKey,
    required List<int> keyExchangePublicKey,
    required SimpleKeyPair authorityKeyPair,
    required String name,
    ResponderRole role = ResponderRole.doctor,
    String specialty = '',
    String licenseRef = '',
    DateTime? expiresAt,
  }) async {
    final credential = ResponderCredential(
      subjectFingerprint: await publicKeyFingerprint(identityPublicKey),
      keyExchangeFingerprint: await publicKeyFingerprint(keyExchangePublicKey),
      name: name,
      role: role,
      specialty: specialty,
      licenseRef: licenseRef,
      issuedAt: DateTime.now().toUtc(),
      expiresAt: expiresAt,
      signature: '',
    );
    final signature = await signEd25519(
      utf8.encode(credential.canonicalBodyJson()),
      authorityKeyPair,
    );
    return ResponderCredential(
      subjectFingerprint: credential.subjectFingerprint,
      keyExchangeFingerprint: credential.keyExchangeFingerprint,
      name: credential.name,
      role: credential.role,
      specialty: credential.specialty,
      licenseRef: credential.licenseRef,
      issuedAt: credential.issuedAt,
      expiresAt: credential.expiresAt,
      signature: base64Encode(signature),
    );
  }

  /// Full verification: authority signature over the canonical body, plus
  /// the badge actually belonging to the keys being presented (fingerprint
  /// match). Returns a reason string on failure, null on success.
  Future<String?> verify({
    required List<int> authorityPublicKey,
    required List<int> identityPublicKey,
    required List<int> keyExchangePublicKey,
  }) async {
    if (expiresAt != null && DateTime.now().toUtc().isAfter(expiresAt!)) {
      return 'badge_expired';
    }
    final signatureBytes = base64Decode(signature);
    final valid = await verifyEd25519(
      utf8.encode(canonicalBodyJson()),
      signatureBytes,
      authorityPublicKey,
    );
    if (!valid) return 'badge_signature_invalid';
    if (await publicKeyFingerprint(identityPublicKey) != subjectFingerprint) {
      return 'identity_key_mismatch';
    }
    if (await publicKeyFingerprint(keyExchangePublicKey) !=
        keyExchangeFingerprint) {
      return 'key_exchange_key_mismatch';
    }
    return null;
  }
}
