// Central state hub for authenticated consultations (issue #17).
//
// Bridges the package-level ConsultService (handshake + encrypted sessions)
// with the app UI: responder mode, badge import, verified peers, the
// responder inbox, and the secure per-peer chat history. Follows the app's
// singleton-ChangeNotifier pattern (see LlmState).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bluetooth_mesh/bluetooth_mesh.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:security_crypto/security_crypto.dart';

import '../../../core/providers/demo_state.dart';
import '../models/case_payload.dart';

class ConsultState extends ChangeNotifier {
  ConsultState._();
  static final ConsultState instance = ConsultState._();

  ConsultService? _service;
  ConsultKeyStore? _keyStore;
  bool _initialized = false;

  static const String _responderNameSuffix = ' •MD';

  // Verified-peer changes and inbox are exposed via getters.
  final List<ConsultRequest> _inbox = <ConsultRequest>[];
  final Map<String, List<ConsultChatEntry>> _secureHistory =
      <String, List<ConsultChatEntry>>{};

  bool get isInitialized => _initialized;

  ConsultService? get service => _service;

  /// True when this device is operating as a verified medical responder.
  bool get isResponderMode => _service?.isResponderMode ?? false;

  ResponderCredential? get credential {
    if (!isResponderMode) return null;
    return _service?.credential;
  }

  /// Peers with a verified badge (patient side). On a responder device the
  /// connected peer is a patient — no badge exists, so the map stays empty
  /// even though sessions are live.
  Map<String, ResponderCredential> get verifiedPeers {
    final service = _service;
    if (service == null) return const {};
    return <String, ResponderCredential>{
      for (final id in service.verifiedEndpoints)
        if (service.verifiedCredential(id) case final ResponderCredential cred)
          id: cred,
    };
  }

  /// Endpoint IDs with a verified, encrypted session.
  Iterable<String> get verifiedEndpoints =>
      _service?.verifiedEndpoints ?? const <String>[];

  /// Raw authenticated-data send (used by the AI help-request tool).
  Future<bool> sendPayload(
    String endpointId,
    ConsultPayloadType type,
    List<int> payload,
  ) async =>
      _service?.sendPayload(endpointId, type, payload) ?? false;

  List<ConsultRequest> get inbox => List.unmodifiable(_inbox);

  List<ConsultChatEntry> historyFor(String endpointId) =>
      List.unmodifiable(_secureHistory[endpointId] ?? const []);

  /// Wires the consult service onto the shared NearbyService. Call once at
  /// app bootstrap; [keyStoreDir] is the app-support directory.
  Future<void> init({required String keyStoreDir}) async {
    if (_initialized) return;
    _keyStore = ConsultKeyStore(keyStoreDir);
    final service = ConsultService(transport: NearbyService());
    _service = service;

    service.onPeerVerified = (endpointId, credential) {
      _secureHistory.putIfAbsent(endpointId, () => []).add(ConsultChatEntry(
            text:
                '🔒 Verified: ${credential.name} — ${credential.role.title}'
                '${credential.specialty.isEmpty ? '' : ', ${credential.specialty}'}'
                '. Messages are now encrypted end-to-end.',
            isSent: false,
            isSystem: true,
            timestamp: DateTime.now(),
          ));
      notifyListeners();
    };
    service.onHandshakeResult = (endpointId, result, reason) {
      if (result != ConsultHandshakeResult.verified) {
        _verifyFailures[endpointId] = reason;
        _secureHistory.putIfAbsent(endpointId, () => []).add(
              ConsultChatEntry(
                text: result == ConsultHandshakeResult.rejected
                    ? '⚠️ Could not verify this device as a medical responder'
                        ' ($reason). Patient data sharing is disabled.'
                    : '⚠️ Consultation handshake failed ($reason).',
                isSent: false,
                isSystem: true,
                timestamp: DateTime.now(),
              ),
            );
      } else {
        _verifyFailures.remove(endpointId);
      }
      notifyListeners();
    };
    service.onPeerClosed = (endpointId) => notifyListeners();
    service.onDataReceived = _onDataReceived;

    // Restore a stored responder badge, if any.
    try {
      final keys = await _keyStore!.loadResponderKeys();
      final badge = await _keyStore!.loadCredential();
      if (keys != null && badge != null) {
        await service.enableResponderMode(keys, badge);
      }
    } catch (e) {
      debugPrint('ConsultState badge restore failed: $e');
    }
    _initialized = true;
    notifyListeners();
  }

  // ── Responder mode ─────────────────────────────────────────

  /// Creates the responder key pairs and writes a badge request file for
  /// the authority to sign. Returns the path to share with the coordinator.
  Future<String> createBadgeRequest({required String displayName}) async {
    final keys = await ResponderKeys.generate();
    await _keyStore!.saveResponderKeys(keys);
    final request = BadgeRequest(
      identityPublicKey: await keys.identityPublicBytes(),
      keyExchangePublicKey: await keys.keyExchangePublicBytes(),
      displayName: displayName,
      deviceName: Platform.localHostname,
      createdAt: DateTime.now().toUtc(),
    );
    final path = await _exportableFilePath('rescate_badge_request.json');
    await File(path).writeAsString(request.encode());
    return path;
  }

  /// Imports and verifies a signed badge. On success the device switches to
  /// responder mode. Returns an error string, or null on success.
  Future<String?> importBadge(String badgeFilePath) async {
    try {
      final badge = ResponderCredential.decode(
        await File(badgeFilePath).readAsString(),
      );
      final keys = await _keyStore!.loadResponderKeys();
      if (keys == null) {
        return 'no_local_keys';
      }
      final reason = await badge.verify(
        authorityPublicKey: ConsultAuthority.defaultPublicKey().bytes,
        identityPublicKey: await keys.identityPublicBytes(),
        keyExchangePublicKey: await keys.keyExchangePublicBytes(),
      );
      if (reason != null) return reason;
      await _keyStore!.saveCredential(badge);
      await _service?.enableResponderMode(keys, badge);
      NearbyService().setUserName(
        _stripSuffix(NearbyService().userName) + _responderNameSuffix,
      );
      notifyListeners();
      return null;
    } on FormatException {
      return 'bad_badge_file';
    } catch (e) {
      return e.toString();
    }
  }

  void disableResponderMode() {
    _service?.disableResponderMode();
    unawaited(_keyStore?.clearResponder());
    NearbyService().setUserName(_stripSuffix(NearbyService().userName));
    notifyListeners();
  }

  // ── Patient / shared session helpers ───────────────────────

  // Auto-verify engine: while the patient is online, connect to and verify
  // every discovered device in the background so the Consult tab can show a
  // "Verified doctors" section backed by real badges.
  Timer? _autoVerifyTimer;
  final Set<String> _verifyAttempted = <String>{};
  final Map<String, DateTime> _handshakeStartedAt = <String, DateTime>{};
  final Map<String, DateTime> _verifyStartedAt = <String, DateTime>{};
  final Map<String, String> _verifyFailures = <String, String>{};
  String _autoVerifyStatus = '';

  bool get autoVerifyActive => _autoVerifyTimer != null;

  /// Human-readable progress for the searching UI ("Found 2 devices —
  /// connecting…", "Verifying 1 connection…").
  String get autoVerifyStatus => _autoVerifyStatus;

  /// Devices verification gave up on (id → reason). The Consult tab offers
  /// these behind a manual "tap to connect" escape hatch instead of
  /// leaving the patient on an endless spinner.
  Map<String, String> get verifyFailures => Map.unmodifiable(_verifyFailures);

  void startAutoVerify() {
    if (_autoVerifyTimer != null || isResponderMode) return;
    _autoVerifyStatus = '';
    _verifyFailures.clear();
    NearbyService().addListener(_autoVerifyTick);
    _autoVerifyTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _autoVerifyTick(),
    );
    _autoVerifyTick();
    notifyListeners();
  }

  void stopAutoVerify() {
    _autoVerifyTimer?.cancel();
    _autoVerifyTimer = null;
    NearbyService().removeListener(_autoVerifyTick);
    _verifyAttempted.clear();
    _handshakeStartedAt.clear();
    _verifyStartedAt.clear();
    _verifyFailures.clear();
    _autoVerifyStatus = '';
    notifyListeners();
  }

  void _autoVerifyTick() {
    final service = _service;
    if (service == null || isResponderMode || DemoState.instance.isDemoMode) {
      return;
    }
    final nearby = NearbyService();

    // Forget attempts for endpoints that disappeared.
    _verifyAttempted.removeWhere((id) =>
        !nearby.discoveredDevices.containsKey(id) &&
        !nearby.connectedDevices.containsKey(id));

    // Connect to newly discovered devices (responders auto-accept). Devices
    // that already timed out are left for the manual escape hatch.
    for (final id in nearby.discoveredDevices.keys) {
      if (_verifyAttempted.contains(id) ||
          _verifyFailures.containsKey(id) ||
          service.isVerified(id) ||
          nearby.connectedDevices.containsKey(id)) {
        continue;
      }
      _verifyAttempted.add(id);
      _verifyStartedAt[id] = DateTime.now();
      nearby.requestConnection(id);
    }

    // Handshake with connected devices — retry every ~20 s. If a connection
    // stays unverified for 45 s total, give up on it: disconnect (release
    // the connection slot) and surface it as a manual-connect candidate.
    var status = '';
    for (final id in nearby.connectedDevices.keys) {
      if (service.isVerified(id)) {
        _handshakeStartedAt.remove(id);
        _verifyStartedAt.remove(id);
        _verifyFailures.remove(id);
        continue;
      }
      final started = _verifyStartedAt.putIfAbsent(id, () => DateTime.now());
      if (DateTime.now().difference(started) >
          const Duration(seconds: 45)) {
        if (!_verifyFailures.containsKey(id)) {
          _verifyFailures[id] = 'no_verified_response';
          debugPrint('[consult] verify TIMEOUT $id — manual fallback');
          nearby.disconnect(id);
        }
        continue;
      }
      final last = _handshakeStartedAt[id];
      if (last != null &&
          DateTime.now().difference(last) < const Duration(seconds: 20)) {
        continue;
      }
      _handshakeStartedAt[id] = DateTime.now();
      beginHandshake(id);
    }
    if (nearby.connectedDevices.isNotEmpty) {
      final unverified = nearby.connectedDevices.keys
          .where((id) => !service.isVerified(id) && !_verifyFailures.containsKey(id))
          .length;
      status = unverified == 0
          ? ''
          : (unverified == 1
              ? 'Verifying 1 nearby device…'
              : 'Verifying $unverified nearby devices…');
    } else if (nearby.discoveredDevices.isNotEmpty) {
      final n = nearby.discoveredDevices.length;
      status = n == 1
          ? 'Found 1 device — connecting…'
          : 'Found $n devices — connecting…';
    } else if (_verifyFailures.isNotEmpty) {
      status = '';
    } else {
      status = 'Scanning for nearby devices…';
    }
    if (status != _autoVerifyStatus) {
      _autoVerifyStatus = status;
      notifyListeners();
    }
  }

  void beginHandshake(String endpointId) =>
      _service?.beginHandshake(endpointId);

  bool isVerified(String endpointId) =>
      _service?.isVerified(endpointId) ?? false;

  /// Display name of a connected peer (device model by default).
  String? serviceName(String endpointId) =>
      NearbyService().connectedDevices[endpointId];

  Future<bool> sendSecureText(String endpointId, String text) async {
    final ok = await _service?.sendText(endpointId, text) ?? false;
    if (ok) {
      _secureHistory.putIfAbsent(endpointId, () => []).add(
            ConsultChatEntry(
              text: text,
              isSent: true,
              timestamp: DateTime.now(),
            ),
          );
      notifyListeners();
    }
    return ok;
  }

  /// Sends a case payload — refused unless the peer is badge-verified.
  Future<bool> sendCasePayload(
    String endpointId,
    CasePayload payload,
  ) async {
    final ok = await _service?.sendPayload(
          endpointId,
          ConsultPayloadType.casePayload,
          utf8.encode(payload.encode()),
        ) ??
        false;
    if (ok) {
      _secureHistory.putIfAbsent(endpointId, () => []).add(
            ConsultChatEntry(
              text:
                  '📋 Consult request sent — ${payload.symptoms.join(', ')}'
                  '${payload.note.isEmpty ? '' : '\n${payload.note}'}',
              isSent: true,
              isSystem: true,
              timestamp: DateTime.now(),
            ),
          );
      notifyListeners();
    }
    return ok;
  }

  /// Responder accepts/declines a consult request.
  Future<void> answerRequest(
    ConsultRequest request,
    bool accept, {
    String replyText = '',
  }) async {
    final index = _inbox.indexOf(request);
    if (index != -1) {
      _inbox[index] = request.withStatus(
        accept ? ConsultRequestStatus.accepted : ConsultRequestStatus.declined,
      );
    }
    await _service?.sendPayload(
      request.endpointId,
      ConsultPayloadType.status,
      utf8.encode(accept ? 'accepted' : 'declined'),
    );
    if (replyText.isNotEmpty && accept) {
      await sendSecureText(request.endpointId, replyText);
    }
    notifyListeners();
  }

  void sendPlainChat(String endpointId, String text) {
    // Unverified legacy chat — never carries patient data.
    NearbyService().sendMessage(endpointId, text);
  }

  // ── Internal ───────────────────────────────────────────────

  void _onDataReceived(
    String endpointId,
    ConsultPayloadType type,
    List<int> payload,
  ) {
    switch (type) {
      case ConsultPayloadType.text:
        _secureHistory.putIfAbsent(endpointId, () => []).add(
              ConsultChatEntry(
                text: utf8.decode(payload),
                isSent: false,
                timestamp: DateTime.now(),
              ),
            );
      case ConsultPayloadType.casePayload:
        try {
          final parsed = CasePayload.decode(utf8.decode(payload));
          _inbox.add(ConsultRequest(
            endpointId: endpointId,
            payload: parsed,
            receivedAt: DateTime.now(),
          ));
        } catch (_) {
          debugPrint('Malformed case payload dropped');
        }
      case ConsultPayloadType.status:
        _secureHistory.putIfAbsent(endpointId, () => []).add(
              ConsultChatEntry(
                text: utf8.decode(payload) == 'accepted'
                    ? '✅ The responder accepted your consult request.'
                    : '❌ The responder declined your consult request.',
                isSent: false,
                isSystem: true,
                timestamp: DateTime.now(),
              ),
            );
      case ConsultPayloadType.close:
        _service?.closeSession(endpointId, notifyPeer: false);
    }
    notifyListeners();
  }

  /// Badge request files go to Downloads when shared storage is actually
  /// writable, otherwise to the app's own directory (always writable, no
  /// permission required). Some OEMs/Android versions deny Downloads even
  /// with MANAGE_EXTERNAL_STORAGE declared — so probe first and never fail.
  Future<String> _exportableFilePath(String fileName) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        if (!await Permission.manageExternalStorage.isGranted) {
          await Permission.manageExternalStorage.request();
        }
      } catch (_) {
        // Some devices don't expose the permission — the probe below
        // decides anyway.
      }
    }
    const download = '/storage/emulated/0/Download';
    try {
      final probe = File('$download/.rescate_write_test');
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      return '$download/$fileName';
    } catch (_) {
      return '${_keyStore!.basePath}/$fileName';
    }
  }

  static String _stripSuffix(String name) =>
      name.endsWith(_responderNameSuffix)
          ? name.substring(0, name.length - _responderNameSuffix.length)
          : name;
}
