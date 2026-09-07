// Host tests for the authenticated consult channel (issue #17).
//
// Two peers are simulated in-process. Everything here runs on the VM with
// real Ed25519/X25519/ChaCha20-Poly1305 primitives.
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart' show SimpleKeyPair;
import 'package:flutter_test/flutter_test.dart';
import 'package:security_crypto/security_crypto.dart';

/// Test authority key — NOT the pinned production key.
Future<(SimpleKeyPair, List<int>)> newAuthority() async {
  final keyPair = await ConsultAuthority.newAuthorityKeyPair();
  final pub = (await (keyPair).extractPublicKey()).bytes;
  return (keyPair, pub);
}

Future<ResponderKeys> newResponder() => ResponderKeys.generate();

Future<ResponderCredential> issueBadge(
  SimpleKeyPair authority,
  ResponderKeys responder, {
  String name = 'Dr. Ahmed Hassan',
  DateTime? expiresAt,
}) async {
  return ResponderCredential.issue(
    identityPublicKey: await responder.identityPublicBytes(),
    keyExchangePublicKey: await responder.keyExchangePublicBytes(),
    authorityKeyPair: authority,
    name: name,
    role: ResponderRole.doctor,
    specialty: 'Emergency Medicine',
    licenseRef: 'SY-ER-1234',
    expiresAt: expiresAt,
  );
}

/// Runs the full handshake between the two sides and returns both sessions.
Future<(ConsultSession patient, ConsultSession responder)> doHandshake({
  required SimpleKeyPair authority,
  required ResponderKeys responderKeys,
  required ResponderCredential badge,
  List<int>? authorityPublicKeyOverride,
}) async {
  final patient = await PatientHandshake.begin();
  final responder = await ResponderHandshake.begin(responderKeys, badge);

  final certOffer = await responder.onHello(patient.helloBytes);
  final result = await patient.complete(
    certOffer,
    authorityPublicKey:
        authorityPublicKeyOverride ?? (await (authority).extractPublicKey()).bytes,
  );
  final responderSession = await responder.onAccept(result.accept);
  return (result.session, responderSession);
}

void main() {
  test('badge request / issue / verify round-trip', () async {
    final (authority, authorityPub) = await newAuthority();
    final responder = await newResponder();

    final request = BadgeRequest(
      identityPublicKey: await responder.identityPublicBytes(),
      keyExchangePublicKey: await responder.keyExchangePublicBytes(),
      displayName: 'Dr. Ahmed Hassan',
      deviceName: 'Pixel 6',
      createdAt: DateTime.now().toUtc(),
    );

    final badge = await issueBadge(authority, responder);
    // Badge must certify the keys from the request.
    expect(badge.subjectFingerprint,
        await publicKeyFingerprint(request.identityPublicKey));
    expect(badge.keyExchangeFingerprint,
        await publicKeyFingerprint(request.keyExchangePublicKey));

    final reason = await badge.verify(
      authorityPublicKey: authorityPub,
      identityPublicKey: request.identityPublicKey,
      keyExchangePublicKey: request.keyExchangePublicKey,
    );
    expect(reason, isNull);

    // JSON round-trip survives.
    final parsed = ResponderCredential.decode(badge.encode());
    expect(parsed.name, badge.name);
    expect(parsed.signature, badge.signature);
    expect(parsed.expiresAt, isNull, reason: 'v1 badges do not expire');
  });

  test('badge with a forged body fails authority signature', () async {
    final (authority, authorityPub) = await newAuthority();
    final responder = await newResponder();
    final badge = await issueBadge(authority, responder);

    // Tamper with the name after signing.
    final forged = ResponderCredential(
      subjectFingerprint: badge.subjectFingerprint,
      keyExchangeFingerprint: badge.keyExchangeFingerprint,
      name: 'Dr. Attacker',
      role: badge.role,
      specialty: badge.specialty,
      licenseRef: badge.licenseRef,
      issuedAt: badge.issuedAt,
      signature: badge.signature,
    );
    final reason = await forged.verify(
      authorityPublicKey: authorityPub,
      identityPublicKey: await responder.identityPublicBytes(),
      keyExchangePublicKey: await responder.keyExchangePublicBytes(),
    );
    expect(reason, 'badge_signature_invalid');
  });

  test('badge signed by a non-authority key is rejected', () async {
    final (_, authorityPub) = await newAuthority();
    final (fakeAuthority, _) = await newAuthority();
    final responder = await newResponder();
    final badge = await issueBadge(fakeAuthority, responder);

    final reason = await badge.verify(
      authorityPublicKey: authorityPub,
      identityPublicKey: await responder.identityPublicBytes(),
      keyExchangePublicKey: await responder.keyExchangePublicBytes(),
    );
    expect(reason, 'badge_signature_invalid');
  });

  test('badge copied to different keys fails fingerprint match', () async {
    final (authority, authorityPub) = await newAuthority();
    final responder = await newResponder();
    final impostor = await newResponder();
    final badge = await issueBadge(authority, responder);

    // Impostor presents the stolen badge file with its OWN keys.
    final reason = await badge.verify(
      authorityPublicKey: authorityPub,
      identityPublicKey: await impostor.identityPublicBytes(),
      keyExchangePublicKey: await impostor.keyExchangePublicBytes(),
    );
    expect(reason, 'identity_key_mismatch');
  });

  test('expired badge is rejected', () async {
    final (authority, authorityPub) = await newAuthority();
    final responder = await newResponder();
    final badge = await issueBadge(
      authority,
      responder,
      expiresAt: DateTime.now().toUtc().subtract(const Duration(days: 1)),
    );
    final reason = await badge.verify(
      authorityPublicKey: authorityPub,
      identityPublicKey: await responder.identityPublicBytes(),
      keyExchangePublicKey: await responder.keyExchangePublicBytes(),
    );
    expect(reason, 'badge_expired');
  });

  test('handshake establishes matching sessions; text round-trips', () async {
    final (authority, _) = await newAuthority();
    final responderKeys = await newResponder();
    final badge = await issueBadge(authority, responderKeys);

    final (patient, responder) = await doHandshake(
      authority: authority,
      responderKeys: responderKeys,
      badge: badge,
    );
    expect(patient.isResponder, isFalse);
    expect(responder.isResponder, isTrue);

    final wire = await patient.seal(ConsultPayloadType.text,
        utf8.encode('I have a burn on my hand'));
    final (type, clear) = await responder.openTyped(ConsultPayloadType.text.toByte(), wire);
    expect(type, ConsultPayloadType.text);
    expect(utf8.decode(clear), 'I have a burn on my hand');

    final reply = await responder.seal(
        ConsultPayloadType.status, utf8.encode('accepted'));
    final (rtype, rclear) = await patient
        .openTyped(ConsultPayloadType.status.toByte(), reply);
    expect(rtype, ConsultPayloadType.status);
    expect(utf8.decode(rclear), 'accepted');
  });

  test('tampered data frame fails authentication', () async {
    final (authority, _) = await newAuthority();
    final responderKeys = await newResponder();
    final badge = await issueBadge(authority, responderKeys);
    final (patient, responder) = await doHandshake(
      authority: authority,
      responderKeys: responderKeys,
      badge: badge,
    );

    final wire = await patient.seal(
        ConsultPayloadType.casePayload, utf8.encode('{"note":"benign"}'));
    wire[wire.length - 1] ^= 0xFF; // flip a bit in the MAC

    expect(() => responder.openTyped(ConsultPayloadType.text.toByte(), wire),
        throwsA(isA<ConsultProtocolException>()));
  });

  test('replayed frame is rejected', () async {
    final (authority, _) = await newAuthority();
    final responderKeys = await newResponder();
    final badge = await issueBadge(authority, responderKeys);
    final (patient, responder) = await doHandshake(
      authority: authority,
      responderKeys: responderKeys,
      badge: badge,
    );

    final wire = await patient.seal(
        ConsultPayloadType.text, utf8.encode('hello'));
    final (_, clear) = await responder.openTyped(ConsultPayloadType.text.toByte(), wire);
    expect(utf8.decode(clear), 'hello');

    // Same exact frame again — replay.
    expect(() => responder.openTyped(ConsultPayloadType.text.toByte(), wire), throwsA(isA<ReplayDetectedException>()));
  });

  test('MITM with impostor keys fails handshake verification', () async {
    final (authority, authorityPub) = await newAuthority();
    final responderKeys = await newResponder();
    final badge = await issueBadge(authority, responderKeys);
    final impostorKeys = await newResponder();

    // Attacker replays a real badge but performs the handshake with their
    // own keys (identity proof must fail because the badge fingerprints
    // don't match the impostor keys).
    final patient = await PatientHandshake.begin();
    final impostor = await ResponderHandshake.begin(impostorKeys, badge);
    final certOffer = await impostor.onHello(patient.helloBytes);

    expect(
      () => patient.complete(certOffer, authorityPublicKey: authorityPub),
      throwsA(isA<BadgeVerificationException>()),
    );
  });

  test('key store persists keys and badge', () async {
    final (authority, _) = await newAuthority();
    final responder = await newResponder();
    final badge = await issueBadge(authority, responder);

    final store = ConsultKeyStore(
        '${Directory.systemTemp.path}/rescate_test_${DateTime.now().microsecondsSinceEpoch}');
    await store.saveResponderKeys(responder);
    await store.saveCredential(badge);

    final loadedKeys = await store.loadResponderKeys();
    final loadedBadge = await store.loadCredential();
    expect(loadedKeys!.sameKeys(responder), isTrue);
    expect(loadedBadge!.name, badge.name);

    await store.clearResponder();
    expect(await store.loadResponderKeys(), isNull);
    expect(await store.loadCredential(), isNull);
  });
}
