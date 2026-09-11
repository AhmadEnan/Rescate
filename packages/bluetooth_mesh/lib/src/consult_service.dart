// ConsultService — authenticated patient↔responder sessions on top of a
// byte transport (issue #17). Patients only exchange patient data with
// peers that completed the badge-verified handshake; responders receive
// consult requests in their inbox.
//
// The service is transport-agnostic: [ConsultTransport] is implemented by
// [NearbyService] on device and by an in-memory pipe in tests, so the full
// two-party protocol is testable on the host.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dev_profiler/dev_profiler.dart';
import 'package:flutter/foundation.dart';
import 'package:security_crypto/security_crypto.dart';

import 'consult_frame.dart';

/// Byte-transport abstraction. The app wires [NearbyService] in; tests use
/// an in-memory pipe.
abstract class ConsultTransport {
  Future<void> sendBytes(String endpointId, Uint8List bytes);

  /// Deliver incoming raw bytes from a connected peer to the service.
  set onBytes(void Function(String endpointId, Uint8List bytes)? callback);

  /// Fired when the underlying connection to a peer goes away, so the
  /// service can tear the session down instead of leaving it "verified"
  /// with keys nobody can use (issue #17 review).
  set onDisconnected(void Function(String endpointId)? callback);
}

/// Outcome of a patient-side handshake attempt.
enum ConsultHandshakeResult { verified, rejected, failed }

class ConsultService extends ChangeNotifier {
  ConsultService({
    required ConsultTransport transport,
    List<int>? authorityPublicKey,
  })  : _transport = transport,
        _authorityPublicKey =
            authorityPublicKey ?? ConsultAuthority.defaultPublicKey().bytes {
    transport.onBytes = _onBytes;
    transport.onDisconnected = handlePeerDisconnected;
  }

  final ConsultTransport _transport;

  /// Pinned RMA key by default; injectable so tests can use their own.
  final List<int> _authorityPublicKey;

  // ── Responder mode ─────────────────────────────────────────
  ResponderKeys? _responderKeys;
  ResponderCredential? _credential;
  bool _responderMode = false;

  bool get isResponderMode => _responderMode;
  ResponderCredential? get credential => _credential;

  Future<void> enableResponderMode(
    ResponderKeys keys,
    ResponderCredential verifiedBadge,
  ) async {
    _responderKeys = keys;
    _credential = verifiedBadge;
    _responderMode = true;
    notifyListeners();
  }

  void disableResponderMode() {
    _responderMode = false;
    _responderKeys = null;
    _credential = null;
    _pendingResponderHandshakes.clear();
    notifyListeners();
  }

  // ── Patient-side sessions ──────────────────────────────────
  final Map<String, PatientHandshake> _pendingHandshakes = {};
  final Map<String, ConsultSession> _sessions = {};
  final Map<String, ResponderCredential> _verifiedPeers = {};

  bool isVerified(String endpointId) => _sessions.containsKey(endpointId);
  ResponderCredential? verifiedCredential(String endpointId) =>
      _verifiedPeers[endpointId];
  Iterable<String> get verifiedEndpoints => _sessions.keys;

  /// Starts a badge-verified handshake with a connected endpoint. The
  /// outcome arrives via [onHandshakeResult]. Safe to call repeatedly — a
  /// stale unanswered handshake is replaced (self-healing retry).
  Future<void> beginHandshake(String endpointId) async {
    if (_responderMode) return; // responders don't initiate consults
    if (_sessions.containsKey(endpointId)) return;
    debugPrint('[consult] HELLO → $endpointId');
    final handshake = await PatientHandshake.begin();
    _pendingHandshakes[endpointId] = handshake;
    await Profiler.span('mesh.consult.hello', () async {
      await _transport.sendBytes(
        endpointId,
        ConsultFrame(ConsultFrameType.hello, handshake.helloBytes).encode(),
      );
    });
  }

  ConsultSession? sessionFor(String endpointId) => _sessions[endpointId];

  void closeSession(String endpointId, {bool notifyPeer = true}) {
    _sessions.remove(endpointId);
    _verifiedPeers.remove(endpointId);
    _pendingHandshakes.remove(endpointId);
    _pendingResponderHandshakes.remove(endpointId);
    if (notifyPeer) {
      unawaited(_transport.sendBytes(endpointId,
              ConsultFrame(ConsultFrameType.close, const []).encode())
          .catchError((Object _) {
        // Peer is already unreachable — the local teardown below is what
        // matters.
      }));
    }
    onPeerClosed?.call(endpointId);
    notifyListeners();
  }

  /// The transport lost this peer. Drop the session immediately: keeping it
  /// would leave [isVerified] true for a device that is gone, and would make
  /// [beginHandshake] a no-op on reconnect (it skips endpoints that already
  /// have a session), so the peer could never re-verify. No close frame —
  /// there is nothing to send it to.
  void handlePeerDisconnected(String endpointId) {
    if (!_sessions.containsKey(endpointId) &&
        !_pendingHandshakes.containsKey(endpointId) &&
        !_pendingResponderHandshakes.containsKey(endpointId)) {
      return;
    }
    debugPrint('[consult] peer disconnected → tearing down session '
        '$endpointId');
    Profiler.count('mesh.consult.sessions.dropped', 1);
    closeSession(endpointId, notifyPeer: false);
  }

  /// Sends application data over a verified session. Patient data
  /// ([ConsultPayloadType.casePayload]) is refused on unverified sessions.
  ///
  /// Returns false — never true — when the transport cannot deliver the
  /// frame, so callers never tell a patient their case was sent when it was
  /// not.
  Future<bool> sendPayload(
    String endpointId,
    ConsultPayloadType type,
    List<int> payload,
  ) async {
    final session = _sessions[endpointId];
    if (session == null) return false;
    if (type == ConsultPayloadType.casePayload && !_verifiedPeers.containsKey(endpointId)) {
      return false; // hard trust gate
    }
    final sealed = await session.seal(type, payload);
    try {
      await _transport.sendBytes(
        endpointId,
        ConsultFrame(ConsultFrameType.data, [type.toByte(), ...sealed]).encode(),
      );
    } catch (e) {
      debugPrint('[consult] send FAILED $endpointId: $e');
      Profiler.count('mesh.consult.frames.failed', 1);
      return false;
    }
    Profiler.count('mesh.consult.frames.sent', 1);
    return true;
  }

  Future<bool> sendText(String endpointId, String text) => sendPayload(
        endpointId,
        ConsultPayloadType.text,
        utf8.encode(text),
      );

  // ── Callbacks ──────────────────────────────────────────────
  void Function(String endpointId, ResponderCredential credential)?
      onPeerVerified;
  void Function(String endpointId, ConsultHandshakeResult result, String reason)?
      onHandshakeResult;
  void Function(String endpointId)? onPeerClosed;
  void Function(String endpointId, ConsultPayloadType type, List<int> payload)?
      onDataReceived;

  // ── Responder-side pending handshakes ──────────────────────
  final Map<String, ResponderHandshake> _pendingResponderHandshakes = {};

  // ── Incoming frame routing ─────────────────────────────────
  void _onBytes(String endpointId, Uint8List bytes) {
    final ConsultFrame frame;
    try {
      frame = ConsultFrame.decode(bytes);
    } on ConsultFrameException {
      // Not a consult frame (e.g. legacy plain-text chat) — ignore here;
      // NearbyService routes text separately.
      return;
    }

    switch (frame.type) {
      case ConsultFrameType.hello:
        _handleHello(endpointId, frame);
      case ConsultFrameType.accept:
        _handleAccept(endpointId, frame);
      case ConsultFrameType.cert:
        _handleCert(endpointId, frame);
      case ConsultFrameType.data:
        _handleData(endpointId, frame);
      case ConsultFrameType.close:
        closeSession(endpointId, notifyPeer: false);
    }
  }

  Future<void> _handleHello(String endpointId, ConsultFrame frame) async {
    debugPrint('[consult] HELLO ← $endpointId responderMode=$_responderMode');
    if (!_responderMode || _responderKeys == null || _credential == null) {
      // Patients must not be able to establish data sessions with a
      // non-responder — no reply at all.
      onHandshakeResult?.call(endpointId, ConsultHandshakeResult.rejected,
          'not_responder_mode');
      return;
    }
    try {
      final handshake = await ResponderHandshake.begin(
        _responderKeys!,
        _credential!,
      );
      final certOffer = await handshake.onHello(frame.payload);
      _pendingResponderHandshakes[endpointId] = handshake;
      debugPrint('[consult] CERT → $endpointId');
      await _transport.sendBytes(
        endpointId,
        ConsultFrame(ConsultFrameType.cert, certOffer).encode(),
      );
    } on ConsultProtocolException catch (e) {
      debugPrint('[consult] hello failed from $endpointId: ${e.code}');
      onHandshakeResult?.call(endpointId, ConsultHandshakeResult.failed, e.code);
    }
  }

  Future<void> _handleAccept(String endpointId, ConsultFrame frame) async {
    final handshake = _pendingResponderHandshakes.remove(endpointId);
    if (handshake == null) return;
    try {
      final session = await handshake.onAccept(frame.payload);
      _sessions[endpointId] = session;
      debugPrint('[consult] SESSION READY (responder) $endpointId');
      // The responder verified nothing about the patient (by design —
      // patients are not badged); mark the channel ready for consults.
      Profiler.count('mesh.consult.sessions.opened', 1);
      onHandshakeResult?.call(
          endpointId, ConsultHandshakeResult.verified, 'session_ready');
      notifyListeners();
    } on ConsultProtocolException catch (e) {
      onHandshakeResult?.call(endpointId, ConsultHandshakeResult.failed, e.code);
    }
  }

  Future<void> _handleCert(String endpointId, ConsultFrame frame) async {
    final handshake = _pendingHandshakes.remove(endpointId);
    if (handshake == null) return;
    try {
      final result = await handshake.complete(
        frame.payload,
        authorityPublicKey: _authorityPublicKey,
      );
      _sessions[endpointId] = result.session;
      _verifiedPeers[endpointId] = result.credential;
      await _transport.sendBytes(
        endpointId,
        ConsultFrame(ConsultFrameType.accept, result.accept).encode(),
      );
      debugPrint('[consult] VERIFIED ✓ $endpointId '
          '(${result.credential.name})');
      Profiler.count('mesh.consult.peers.verified', 1);
      onPeerVerified?.call(endpointId, result.credential);
      notifyListeners();
    } on ConsultProtocolException catch (e) {
      debugPrint('[consult] verify FAILED $endpointId: ${e.toString()}');
      onHandshakeResult?.call(
          endpointId, ConsultHandshakeResult.rejected, e.toString());
    }
  }

  Future<void> _handleData(String endpointId, ConsultFrame frame) async {
    final session = _sessions[endpointId];
    if (frame.payload.isEmpty) return;
    final typeByte = frame.payload[0];
    final sealed = Uint8List.sublistView(frame.payload, 1);
    if (session == null) {
      // Data from an unverified/unauthenticated peer — drop.
      debugPrint('[consult] data DROPPED from $endpointId (no session)');
      Profiler.count('mesh.consult.data.dropped', 1);
      return;
    }
    try {
      final (type, payload) = await session.openTyped(typeByte, sealed);
      onDataReceived?.call(endpointId, type, payload);
      notifyListeners();
    } on ConsultProtocolException {
      // Tampered or replayed frame — tear the session down rather than
      // risk accepting anything from a broken channel.
      Profiler.count('mesh.consult.data.rejected', 1);
      closeSession(endpointId);
    }
  }

  @override
  void dispose() {
    _sessions.clear();
    _verifiedPeers.clear();
    _pendingHandshakes.clear();
    _pendingResponderHandshakes.clear();
    super.dispose();
  }
}
