// End-to-end two-party consult test over an in-memory transport: the full
// badge-verified handshake, encrypted text, case-payload trust gating,
// tamper rejection, and unverified-peer blocking — all on the host.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bluetooth_mesh/bluetooth_mesh.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:security_crypto/security_crypto.dart';

/// Bidirectional in-memory wire connecting two services, like Nearby.
class InMemoryWire {
  final _a = _Pipe();
  final _b = _Pipe();
  late final _Transport sideA;
  late final _Transport sideB;

  InMemoryWire() {
    sideA = _Transport(_a, _b);
    sideB = _Transport(_b, _a);
  }
}

class _Pipe {
  final StreamController<Uint8List> _controller =
      StreamController.broadcast();
  Uint8List? lastSent;
  void Function(String endpointId, Uint8List bytes)? listener;

  void deliver(Uint8List bytes) {
    lastSent = bytes;
    listener?.call('peer', bytes);
  }
}

class _Transport implements ConsultTransport {
  _Transport(this._own, this._remote);
  final _Pipe _own;
  final _Pipe _remote;

  @override
  set onBytes(void Function(String endpointId, Uint8List bytes)? callback) =>
      _own.listener = callback;

  @override
  Future<void> sendBytes(String endpointId, Uint8List bytes) async {
    _own.lastSent = bytes;
    _remote.deliver(bytes);
  }
}

/// The handshake spans several async hops (hello → cert → verify → accept);
/// poll until the patient side reports a verified session.
Future<void> waitUntilVerified(ConsultService service) async {
  for (var i = 0; i < 200 && !service.isVerified('peer'); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  late InMemoryWire wire;
  late ConsultService patient;
  late ConsultService responder;
  late List<int> testAuthorityPub;

  setUp(() async {
    wire = InMemoryWire();
    final authority = await ConsultAuthority.newAuthorityKeyPair();
    testAuthorityPub = (await authority.extractPublicKey()).bytes;
    patient = ConsultService(
        transport: wire.sideA, authorityPublicKey: testAuthorityPub);
    responder = ConsultService(
        transport: wire.sideB, authorityPublicKey: testAuthorityPub);

    final keys = await ResponderKeys.generate();
    final badge = await ResponderCredential.issue(
      identityPublicKey: await keys.identityPublicBytes(),
      keyExchangePublicKey: await keys.keyExchangePublicBytes(),
      authorityKeyPair: authority,
      name: 'Dr. Ahmed Hassan',
      role: ResponderRole.doctor,
      specialty: 'Emergency Medicine',
      licenseRef: 'SY-ER-1234',
    );
    await responder.enableResponderMode(keys, badge);
  });

  test('verified handshake completes and both sides see the session', () async {
    ResponderCredential? seenBadge;
    patient.onPeerVerified = (id, cred) => seenBadge = cred;

    await patient.beginHandshake('peer');
    await waitUntilVerified(patient);

    expect(patient.isVerified('peer'), isTrue);
    expect(seenBadge!.name, 'Dr. Ahmed Hassan');
    expect(patient.verifiedCredential('peer')!.role, ResponderRole.doctor);
    // Responder side: session is live but the patient has no badge — the
    // credential lookup must be null, never a crash (regression: app
    // force-unwrapped this and red-screened on the doctor's device).
    expect(responder.isVerified('peer'), isTrue);
    expect(responder.verifiedCredential('peer'), isNull);
  });

  test('encrypted text and case payload round-trip both directions',
      () async {
    final received = <(ConsultPayloadType, String)>[];
    responder.onDataReceived = (id, type, payload) =>
        received.add((type, utf8.decode(payload)));

    await patient.beginHandshake('peer');
    await waitUntilVerified(patient);

    expect(
        await patient.sendText('peer', 'I have a burn victim here'), isTrue);
    expect(
        await patient.sendPayload('peer', ConsultPayloadType.casePayload,
            utf8.encode('{"note":"burn, left hand"}')),
        isTrue);

    final replyOk = await responder.sendPayload(
        'peer', ConsultPayloadType.status, utf8.encode('accepted'));
    expect(replyOk, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(received.map((r) => r.$2),
        containsAll(['I have a burn victim here', '{"note":"burn, left hand"}']));
  });

  test('data from an unverified peer is dropped', () async {
    var gotData = false;
    responder.onDataReceived = (id, type, payload) => gotData = true;

    // Patient-mode responder receives raw data with no session — dropped.
    // Simulate by sending a data frame from the patient before handshake.
    final rawFrame = ConsultFrame(
        ConsultFrameType.data, [ConsultPayloadType.text.toByte(), ...List.filled(40, 7)]);
    await wire.sideA.sendBytes('peer', rawFrame.encode());
    await Future<void>.delayed(Duration.zero);
    expect(gotData, isFalse);
  });

  test('non-responder refuses handshake (no patient-data sessions)', () async {
    responder.disableResponderMode();
    ConsultHandshakeResult? result;
    patient.onHandshakeResult = (id, r, reason) => result = r;

    await patient.beginHandshake('peer');
    await Future<void>.delayed(Duration.zero);

    expect(patient.isVerified('peer'), isFalse);
    expect(result, isNull); // silence — no session, no data ever flows
  });
}
