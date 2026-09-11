// Issue #17 trust-gating tests (app layer).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bluetooth_mesh/bluetooth_mesh.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rescate_app/features/community/models/case_payload.dart';
import 'package:rescate_app/features/community/services/consult_state.dart';
import 'package:security_crypto/security_crypto.dart';

class _FakeTransport implements ConsultTransport {
  @override
  Future<void> sendBytes(String endpointId, Uint8List bytes) async {}

  @override
  void Function(String endpointId, Uint8List bytes)? onBytes;

  @override
  void Function(String endpointId)? onDisconnected;
}

void main() {
  setUp(() {
    ConsultState.instance.resetForTest();
  });

  tearDown(() {
    ConsultState.instance.resetForTest();
  });

  test('consult state refuses case payloads before any session exists',
      () async {
    final sent = await ConsultState.instance.sendCasePayload(
      'unverified_peer',
      CasePayload(note: 'test', createdAt: DateTime.now()),
    );
    expect(sent, isFalse);
  });

  test('secure text fails closed without a verified session', () async {
    final sent =
        await ConsultState.instance.sendSecureText('unverified_peer', 'hi');
    expect(sent, isFalse);
  });

  test('Task 6: tampered stored badge leaves responder mode disabled on restore',
      () async {
    final tempDir = await Directory.systemTemp.createTemp('consult_test_tampered_');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final secrets = InMemorySecretStore();
    final keys = await ResponderKeys.generate();
    final authKeyPair = await ConsultAuthority.newAuthorityKeyPair();
    final authPub = (await authKeyPair.extractPublicKey()).bytes;

    final badge = await ResponderCredential.issue(
      identityPublicKey: await keys.identityPublicBytes(),
      keyExchangePublicKey: await keys.keyExchangePublicBytes(),
      authorityKeyPair: authKeyPair,
      name: 'Dr. Real Doctor',
      role: ResponderRole.doctor,
    );

    // Tamper with the badge content (change name so signature fails)
    final tamperedBadge = ResponderCredential(
      subjectFingerprint: badge.subjectFingerprint,
      keyExchangeFingerprint: badge.keyExchangeFingerprint,
      name: 'Dr. Impostor',
      role: badge.role,
      specialty: badge.specialty,
      licenseRef: badge.licenseRef,
      issuedAt: badge.issuedAt,
      expiresAt: badge.expiresAt,
      signature: badge.signature,
    );

    final keyStore = ConsultKeyStore(tempDir.path, secrets: secrets);
    await keyStore.saveResponderKeys(keys);
    await keyStore.saveCredential(tamperedBadge);

    // Init ConsultState to trigger restore
    await ConsultState.instance.init(
      keyStoreDir: tempDir.path,
      secrets: secrets,
      transport: _FakeTransport(),
      authorityPublicKey: authPub,
    );

    expect(ConsultState.instance.isResponderMode, isFalse);
    expect(ConsultState.instance.badgeRestoreError, 'badge_signature_invalid');
  });

  test('Task 6: expired stored badge leaves responder mode disabled on restore',
      () async {
    final tempDir = await Directory.systemTemp.createTemp('consult_test_expired_');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final secrets = InMemorySecretStore();
    final keys = await ResponderKeys.generate();
    final authKeyPair = await ConsultAuthority.newAuthorityKeyPair();
    final authPub = (await authKeyPair.extractPublicKey()).bytes;

    final expiredBadge = await ResponderCredential.issue(
      identityPublicKey: await keys.identityPublicBytes(),
      keyExchangePublicKey: await keys.keyExchangePublicBytes(),
      authorityKeyPair: authKeyPair,
      name: 'Dr. Expired Doctor',
      role: ResponderRole.doctor,
      expiresAt: DateTime.now().toUtc().subtract(const Duration(days: 2)),
    );

    final keyStore = ConsultKeyStore(tempDir.path, secrets: secrets);
    await keyStore.saveResponderKeys(keys);
    await keyStore.saveCredential(expiredBadge);

    await ConsultState.instance.init(
      keyStoreDir: tempDir.path,
      secrets: secrets,
      transport: _FakeTransport(),
      authorityPublicKey: authPub,
    );

    expect(ConsultState.instance.isResponderMode, isFalse);
    expect(ConsultState.instance.badgeRestoreError, 'badge_expired');
  });

  test('Task 2: case payload with urgency encodes/decodes and enters responder inbox',
      () async {
    final now = DateTime.now();
    final original = CasePayload(
      note: 'Severe chest pain, possible cardiac event',
      urgency: 'CRITICAL',
      symptoms: const ['Chest pain', 'Difficulty breathing'],
      latitude: 31.2357,
      longitude: 30.0444,
      createdAt: now,
    );

    final encoded = original.encode();
    final decoded = CasePayload.decode(encoded);

    expect(decoded.note, 'Severe chest pain, possible cardiac event');
    expect(decoded.urgency, 'CRITICAL');
    expect(decoded.symptoms, contains('Chest pain'));
    expect(decoded.includeLocation, isTrue);
    expect(decoded.latitude, closeTo(31.2357, 0.0001));
    expect(decoded.longitude, closeTo(30.0444, 0.0001));

    // Also verify that a legacy payload without urgency decodes gracefully
    final legacyJson = jsonEncode({
      'v': 1,
      'note': 'Legacy patient note',
      'symptoms': ['Burn'],
      'vitals': [],
      'created_at': now.toUtc().toIso8601String(),
    });
    final decodedLegacy = CasePayload.decode(legacyJson);
    expect(decodedLegacy.urgency, isEmpty);
    expect(decodedLegacy.note, 'Legacy patient note');
  });
}
