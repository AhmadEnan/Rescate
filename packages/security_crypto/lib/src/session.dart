// Authenticated consult channel between a patient and a verified responder.
//
// Handshake (patient initiates):
//   1. HELLO       patient -> responder : patient ephemeral X25519 pub + 16B challenge
//   2. CERT_OFFER  responder -> patient : badge, X25519 static pub, responder
//                  ephemeral X25519 pub, nonce prefix, challenge echo, and an
//                  Ed25519 signature (identity key) over the transcript
//   3. Patient verifies the badge (authority signature + fingerprint match)
//      and the identity signature, then derives session keys and sends
//   4. ACCEPT      patient -> responder : challenge echo
//
// Session keys: HKDF-SHA256 over (X25519(eph_p, kx_r) || X25519(eph_p, eph_r)),
// salted with the transcript hash, separate c2r / r2c keys. Every data frame
// is ChaCha20-Poly1305 with nonce = prefix || counter(AEAD big-endian) and
// the frame header as AAD; the receiver rejects any counter it has already
// seen (replay protection).
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'credential.dart';
import 'identity.dart';

enum ConsultPayloadType {
  text,
  casePayload,
  status,
  close;

  int toByte() => index;
  static ConsultPayloadType fromByte(int b) => ConsultPayloadType.values[b];
}

class ConsultProtocolException implements Exception {
  const ConsultProtocolException(this.code);
  final String code;

  @override
  String toString() => 'ConsultProtocolException($code)';
}

/// Thrown when a frame's counter was already seen — replay or reordering.
class ReplayDetectedException extends ConsultProtocolException {
  const ReplayDetectedException() : super('replay_detected');
}

class BadgeVerificationException extends ConsultProtocolException {
  const BadgeVerificationException(this.reason) : super(reason);
  final String reason;
}

// ── Handshake messages ──────────────────────────────────────────────────────

Map<String, dynamic> _decodeMessage(Uint8List bytes, String wantType) {
  Map<String, dynamic> json;
  try {
    json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  } on FormatException {
    throw const ConsultProtocolException('malformed_json');
  }
  if ((json['t'] as String?) != wantType) {
    throw ConsultProtocolException('unexpected_message_type');
  }
  return json;
}

// ── Patient side ────────────────────────────────────────────────────────────

class PatientHandshake {
  PatientHandshake._(this._ephemeralKeyPair, this._challenge, this._helloBytes);

  static final X25519 _x25519 = X25519();

  final SimpleKeyPair _ephemeralKeyPair;
  final Uint8List _challenge;
  final Uint8List _helloBytes;

  static Future<PatientHandshake> begin() async {
    final eph = await _x25519.newKeyPair();
    final challenge = randomBytes(16);
    final hello = utf8.encode(jsonEncode(<String, dynamic>{
      'v': 1,
      't': 'hello',
      'eph': bytesToHex((await eph.extractPublicKey()).bytes),
      'challenge': base64Encode(challenge),
    }));
    return PatientHandshake._(eph, challenge, Uint8List.fromList(hello));
  }

  Uint8List get helloBytes => Uint8List.fromList(_helloBytes);

  /// Verifies the responder's CERT_OFFER and derives the session. Returns
  /// the ACCEPT message to send, the ready-to-use session, and the verified
  /// badge of the responder.
  Future<({Uint8List accept, ConsultSession session, ResponderCredential credential})>
      complete(
    Uint8List certOfferBytes, {
    required List<int> authorityPublicKey,
  }) async {
    final json = _decodeMessage(certOfferBytes, 'cert');
    final credential = ResponderCredential.fromEnvelopeJson(
      json['cred'] as Map<String, dynamic>,
    );
    final kxPub = hexToBytes(json['kx_pub'] as String);
    final responderEphPub = hexToBytes(json['eph'] as String);
    final noncePrefix = base64Decode(json['nonce_prefix'] as String);
    final identitySig = base64Decode(json['identity_sig'] as String);
    final challengeEcho = base64Decode(json['challenge_echo'] as String);

    if (!_listEquals(challengeEcho, _challenge)) {
      throw const ConsultProtocolException('challenge_mismatch');
    }
    if (noncePrefix.length != 4) {
      throw const ConsultProtocolException('bad_nonce_prefix');
    }

    // Badge check: authority signature + badge names exactly the keys
    // presented in this handshake.
    final presentedIdentityPub = json['identity_pub'] is String
        ? hexToBytes(json['identity_pub'] as String)
        : null;
    if (presentedIdentityPub == null) {
      throw const ConsultProtocolException('missing_identity_pub');
    }
    final reason = await credential.verify(
      authorityPublicKey: authorityPublicKey,
      identityPublicKey: presentedIdentityPub,
      keyExchangePublicKey: kxPub,
    );
    if (reason != null) {
      throw BadgeVerificationException(reason);
    }

    // Responder proves possession of the certified identity key by signing
    // the transcript: sha256(hello || certOffer sans signature fields).
    final transcript = await Sha256().hash([
      ..._helloBytes,
      ..._certOfferTranscriptPart(json),
    ]);
    final identityOk = await verifyEd25519(
      transcript.bytes,
      identitySig,
      presentedIdentityPub,
    );
    if (!identityOk) {
      throw const BadgeVerificationException('identity_proof_failed');
    }

    // X25519 is symmetric: the patient computes the two shared secrets from
    // its ephemeral key; the responder computes the identical secrets from
    // its static kx key and its ephemeral key.
    final s1 = await _sessionX25519.sharedSecretKey(
      keyPair: _ephemeralKeyPair,
      remotePublicKey: SimplePublicKey(kxPub, type: KeyPairType.x25519),
    );
    final s2 = await _sessionX25519.sharedSecretKey(
      keyPair: _ephemeralKeyPair,
      remotePublicKey:
          SimplePublicKey(responderEphPub, type: KeyPairType.x25519),
    );
    final ikm = <int>[
      ...(await s1.extractBytes()),
      ...(await s2.extractBytes()),
    ];
    final session = await ConsultSession._derive(
      isResponder: false,
      ikm: ikm,
      transcriptHash: transcript.bytes,
      noncePrefix: Uint8List.fromList(noncePrefix),
    );

    final accept = utf8.encode(jsonEncode(<String, dynamic>{
      'v': 1,
      't': 'accept',
      'challenge_echo': base64Encode(_challenge),
    }));
    return (
      accept: Uint8List.fromList(accept),
      session: session,
      credential: credential,
    );
  }

  /// The part of the CERT_OFFER the responder signed — everything except
  /// identity_sig itself.
  static List<int> _certOfferTranscriptPart(Map<String, dynamic> certOffer) {
    final copy = <String, dynamic>{...certOffer}..remove('identity_sig');
    return utf8.encode(jsonEncode(copy));
  }
}

// ── Responder side ──────────────────────────────────────────────────────────

class ResponderHandshake {
  ResponderHandshake._(this._keys, this._credential);

  static final X25519 _x25519 = X25519();

  final ResponderKeys _keys;
  final ResponderCredential _credential;

  Uint8List? _helloBytes;
  SimpleKeyPair? _ephemeral;
  Uint8List? _noncePrefix;

  static Future<ResponderHandshake> begin(
    ResponderKeys keys,
    ResponderCredential credential,
  ) async =>
      ResponderHandshake._(keys, credential);

  /// Consumes the patient HELLO, produces the CERT_OFFER to send back.
  Future<Uint8List> onHello(Uint8List helloBytes) async {
    final json = _decodeMessage(helloBytes, 'hello');
    // Reject a malformed ephemeral key here rather than letting it fail
    // during key agreement. The key itself is re-read from the stored HELLO
    // in [onAccept], which is the copy the transcript is bound to.
    if (hexToBytes(json['eph'] as String).length != 32) {
      throw const ConsultProtocolException('bad_ephemeral_key');
    }
    final challenge = base64Decode(json['challenge'] as String);
    if (challenge.length != 16) {
      throw const ConsultProtocolException('bad_challenge');
    }

    _helloBytes = Uint8List.fromList(helloBytes);
    _ephemeral = await _x25519.newKeyPair();
    _noncePrefix = randomBytes(4);

    final responderEphPub = (await _ephemeral!.extractPublicKey()).bytes;
    final certOffer = <String, dynamic>{
      'v': 1,
      't': 'cert',
      'cred': _credential.toEnvelopeJson(),
      'identity_pub': bytesToHex(await _keys.identityPublicBytes()),
      'kx_pub': bytesToHex(await _keys.keyExchangePublicBytes()),
      'eph': bytesToHex(responderEphPub),
      'nonce_prefix': base64Encode(_noncePrefix!),
      'challenge_echo': base64Encode(challenge),
    };

    // Identity proof over the transcript (everything we're about to send).
    final transcript = await Sha256().hash([
      ...helloBytes,
      ...utf8.encode(jsonEncode(certOffer)),
    ]);
    certOffer['identity_sig'] =
        base64Encode(await _keys.signWithIdentity(transcript.bytes));

    return Uint8List.fromList(utf8.encode(jsonEncode(certOffer)));
  }

  /// Consumes the patient ACCEPT and derives the responder-side session.
  Future<ConsultSession> onAccept(Uint8List acceptBytes) async {
    final json = _decodeMessage(acceptBytes, 'accept');
    final challengeEcho = base64Decode(json['challenge_echo'] as String);
    if (_helloBytes == null ||
        _ephemeral == null ||
        _noncePrefix == null) {
      throw const ConsultProtocolException('handshake_out_of_order');
    }
    final helloJson =
        jsonDecode(utf8.decode(_helloBytes!)) as Map<String, dynamic>;
    if (!_listEquals(challengeEcho,
        base64Decode(helloJson['challenge'] as String))) {
      throw const ConsultProtocolException('challenge_mismatch');
    }
    final patientEphPub = SimplePublicKey(
      hexToBytes(helloJson['eph'] as String),
      type: KeyPairType.x25519,
    );

    // Mirror of the patient's derivation — see PatientHandshake.complete.
    final s1 = await _sessionX25519.sharedSecretKey(
      keyPair: await _keys.keyExchangeKeyPair,
      remotePublicKey: patientEphPub,
    );
    final s2 = await _sessionX25519.sharedSecretKey(
      keyPair: _ephemeral!,
      remotePublicKey: patientEphPub,
    );
    final ikm = <int>[
      ...(await s1.extractBytes()),
      ...(await s2.extractBytes()),
    ];

    // Recompute the transcript exactly as the patient did: hello ||
    // certOffer sans identity_sig. We rebuild the sans-sig map by deleting
    // the signature from what we sent.
    final certOfferSansSig = <String, dynamic>{
      'v': 1,
      't': 'cert',
      'cred': _credential.toEnvelopeJson(),
      'identity_pub': bytesToHex(await _keys.identityPublicBytes()),
      'kx_pub': bytesToHex(await _keys.keyExchangePublicBytes()),
      'eph': bytesToHex((await _ephemeral!.extractPublicKey()).bytes),
      'nonce_prefix': base64Encode(_noncePrefix!),
      'challenge_echo': base64Encode(challengeEcho),
    };
    final transcript = await Sha256().hash([
      ..._helloBytes!,
      ...utf8.encode(jsonEncode(certOfferSansSig)),
    ]);

    return ConsultSession._derive(
      isResponder: true,
      ikm: ikm,
      transcriptHash: transcript.bytes,
      noncePrefix: _noncePrefix!,
    );
  }
}

// ── Established session ─────────────────────────────────────────────────────

final Chacha20 _aead = Chacha20.poly1305Aead();
final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
final X25519 _sessionX25519 = X25519();

class ConsultSession {
  ConsultSession._({
    required bool isResponder,
    required SecretKey txKey,
    required SecretKey rxKey,
    required Uint8List noncePrefix,
  })  : _isResponder = isResponder,
        _txKey = txKey,
        _rxKey = rxKey,
        _noncePrefix = noncePrefix;

  static Future<ConsultSession> _derive({
    required bool isResponder,
    required List<int> ikm,
    required List<int> transcriptHash,
    required Uint8List noncePrefix,
  }) async {
    final txKey = await _hkdf.deriveKey(
      secretKey: SecretKey(ikm),
      nonce: transcriptHash,
      info: utf8.encode(
        'rescate-consult-v1:${isResponder ? 'r2c' : 'c2r'}',
      ),
    );
    final rxKey = await _hkdf.deriveKey(
      secretKey: SecretKey(ikm),
      nonce: transcriptHash,
      info: utf8.encode(
        'rescate-consult-v1:${isResponder ? 'c2r' : 'r2c'}',
      ),
    );
    return ConsultSession._(
      isResponder: isResponder,
      txKey: txKey,
      rxKey: rxKey,
      noncePrefix: noncePrefix,
    );
  }

  final bool _isResponder;
  final SecretKey _txKey;
  final SecretKey _rxKey;
  final Uint8List _noncePrefix;
  int _txCounter = 0;
  int _rxMaxSeen = -1;

  bool get isResponder => _isResponder;

  /// Encrypts one payload. Wire layout: counter(u64 BE) || ciphertext || mac.
  Future<Uint8List> seal(ConsultPayloadType type, List<int> payload) async {
    final counter = _txCounter++;
    final nonce = _nonce(counter);
    final aad = [type.toByte(), ..._u64be(counter)];
    final box = await _aead.encrypt(
      payload,
      secretKey: _txKey,
      nonce: nonce,
      aad: aad,
    );
    return Uint8List.fromList([
      ..._u64be(counter),
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  /// Decrypts one frame. The payload-type byte arrives in the outer frame
  /// header and is authenticated as AAD. Throws [ReplayDetectedException]
  /// for any counter already seen and [ConsultProtocolException] on
  /// tampering.
  Future<(ConsultPayloadType, Uint8List)> openTyped(
    int typeByte,
    Uint8List wire,
  ) async {
    if (wire.length < 8 + 16) {
      throw const ConsultProtocolException('frame_too_short');
    }
    final counter = _be64u(wire.sublist(0, 8));
    if (counter <= _rxMaxSeen) {
      throw const ReplayDetectedException();
    }
    if (typeByte < 0 || typeByte >= ConsultPayloadType.values.length) {
      throw const ConsultProtocolException('bad_payload_type');
    }
    final mac = wire.sublist(wire.length - 16);
    final cipherText = wire.sublist(8, wire.length - 16);
    final box = SecretBox(
      cipherText,
      nonce: _nonce(counter),
      mac: Mac(mac),
    );
    final Uint8List clear;
    try {
      clear = Uint8List.fromList(
        await _aead.decrypt(
          box,
          secretKey: _rxKey,
          aad: [typeByte, ..._u64be(counter)],
        ),
      );
    } on SecretBoxAuthenticationError {
      throw const ConsultProtocolException('decrypt_failed');
    }
    _rxMaxSeen = counter;
    return (ConsultPayloadType.fromByte(typeByte), clear);
  }

  Uint8List _nonce(int counter) =>
      Uint8List.fromList([..._noncePrefix, ..._u64be(counter)]);
}

// ── helpers ─────────────────────────────────────────────────────────────────

Uint8List _u64be(int v) {
  final out = Uint8List(8);
  for (var i = 7; i >= 0; i--) {
    out[i] = v & 0xFF;
    v >>= 8;
  }
  return out;
}

int _be64u(List<int> bytes) {
  var v = 0;
  for (final b in bytes) {
    v = (v << 8) | b;
  }
  return v;
}

bool _listEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
