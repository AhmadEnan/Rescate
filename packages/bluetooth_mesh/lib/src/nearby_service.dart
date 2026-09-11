// SECURITY-NOTE(security): Nearby connections still run in legacy plaintext
// mode with auto-accept strategy. Wire Ed25519 ephemeral identity per
// CONTRIBUTING.md (12h rotation) + E2EE before any production exposure.
// Tracked so this is not forgotten - the prior inline comment was dropped
// accidentally during the lint sweep.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:dev_profiler/dev_profiler.dart';
import 'package:flutter/foundation.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:device_info_plus/device_info_plus.dart';

import 'consult_frame.dart';
import 'consult_service.dart';

/// Wraps the Google Nearby Connections API for Bluetooth/Wi-Fi P2P messaging.
///
/// Singleton — every screen shares the same instance so connection state
/// survives navigation. Also implements [ConsultTransport] so
/// [ConsultService] can send authenticated consult frames over the same
/// connection.
class NearbyService extends ChangeNotifier implements ConsultTransport {
  // ── Singleton ──────────────────────────────────────────────
  static final NearbyService _instance = NearbyService._internal();
  factory NearbyService() => _instance;
  NearbyService._internal();

  // ── State ──────────────────────────────────────────────────
  final Nearby _nearby = Nearby();
  String _userName = '';
  String get userName => _userName;

  bool _isAdvertising = false;
  bool get isAdvertising => _isAdvertising;

  bool _isDiscovering = false;
  bool get isDiscovering => _isDiscovering;

  /// Discovered devices: endpointId → endpointName
  final Map<String, String> _discoveredDevices = {};
  Map<String, String> get discoveredDevices =>
      Map.unmodifiable(_discoveredDevices);

  /// Currently connected endpoints
  final Map<String, String> _connectedDevices = {};
  Map<String, String> get connectedDevices =>
      Map.unmodifiable(_connectedDevices);

  /// Pending connection requests (endpoint → name)
  final Map<String, String> _pendingConnections = {};
  Map<String, String> get pendingConnections =>
      Map.unmodifiable(_pendingConnections);

  /// Last radio error (permissions denied, adapter off, plugin failure).
  /// Surfaced in the UI — discovery failing silently is undebuggable.
  String? _lastError;
  String? get lastError => _lastError;

  /// Incoming message callback — set by chat screen
  void Function(String endpointId, String message)? onMessageReceived;

  /// Incoming binary consult frame callback — wired by [ConsultService].
  void Function(String endpointId, Uint8List bytes)? onBytesReceived;

  @override
  set onBytes(void Function(String endpointId, Uint8List bytes)? callback) =>
      onBytesReceived = callback;

  /// Transport-loss callback — wired by [ConsultService] so it can tear down
  /// the crypto session when the radio link drops (issue #17 review).
  void Function(String endpointId)? onPeerDisconnected;

  @override
  set onDisconnected(void Function(String endpointId)? callback) =>
      onPeerDisconnected = callback;

  /// Connection-state callback — set by screens
  void Function(String endpointId, String endpointName, bool connected)?
      onConnectionChanged;

  // Service ID shared by every instance of this app
  static const String _serviceId = 'com.rescate.bluetooth_messenger';

  // ── Initialise ─────────────────────────────────────────────
  Future<void> init() async {
    if (_userName.isNotEmpty) return;
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      _userName = androidInfo.model;
    } catch (_) {
      _userName = 'User_${Random().nextInt(9999)}';
    }
  }

  void setUserName(String name) {
    _userName = name;
    notifyListeners();
  }

  // ── Advertise (make yourself visible) ──────────────────────
  Future<void> startAdvertising() async {
    if (_isAdvertising) return;
    try {
      await Profiler.span('mesh.startAdvertising', () async {
        await _nearby.startAdvertising(
          _userName,
          Strategy.P2P_CLUSTER,
          serviceId: _serviceId,
          onConnectionInitiated: _onConnectionInit,
          onConnectionResult: _onConnectionResult,
          onDisconnected: _onDisconnected,
        );
      });
      _isAdvertising = true;
      _lastError = null;
      notifyListeners();
    } catch (e) {
      _lastError = 'Advertising failed: $e';
      debugPrint('Advertising error: $e');
      notifyListeners();
    }
  }

  Future<void> stopAdvertising() async {
    try {
      await Profiler.span('mesh.stopAdvertising', () async {
        await _nearby.stopAdvertising();
      });
    } catch (_) {}
    _isAdvertising = false;
    notifyListeners();
  }

  // ── Discover (find nearby users) ───────────────────────────
  Future<void> startDiscovery() async {
    if (_isDiscovering) return;
    try {
      await Profiler.span('mesh.startDiscovery', () async {
        await _nearby.startDiscovery(
          _userName,
          Strategy.P2P_CLUSTER,
          serviceId: _serviceId,
          onEndpointFound: (String id, String name, String serviceId) {
            // The plugin re-reports endpoints right after they connect;
            // never list a connected device as nearby again.
            if (_connectedDevices.containsKey(id)) return;
            _discoveredDevices[id] = name;
            Profiler.count('mesh.endpoints.found', 1);
            notifyListeners();
          },
          onEndpointLost: (String? id) {
            if (id != null) {
              _discoveredDevices.remove(id);
              notifyListeners();
            }
          },
        );
      });
      _isDiscovering = true;
      _lastError = null;
      notifyListeners();
    } catch (e) {
      _lastError =
          'Scanning failed: $e — check Bluetooth and location permissions';
      debugPrint('Discovery error: $e');
      notifyListeners();
    }
  }

  Future<void> stopDiscovery() async {
    try {
      await Profiler.span('mesh.stopDiscovery', () async {
        await _nearby.stopDiscovery();
      });
    } catch (_) {}
    _isDiscovering = false;
    notifyListeners();
  }

  // ── Connect to a discovered endpoint ───────────────────────
  Future<void> requestConnection(String endpointId) async {
    try {
      await _nearby.requestConnection(
        _userName,
        endpointId,
        onConnectionInitiated: _onConnectionInit,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );
    } catch (e) {
      debugPrint('Request connection error: $e');
    }
  }

  // ── Send a text message ────────────────────────────────────
  Future<void> sendMessage(String endpointId, String text) async {
    try {
      await Profiler.span('mesh.sendMessage', () async {
        Profiler.count('mesh.bytes.sent', text.length);
        await _nearby.sendBytesPayload(
          endpointId,
          Uint8List.fromList(utf8.encode(text)),
        );
      });
    } catch (e) {
      debugPrint('Send error: $e');
    }
  }

  /// Raw frame transport for [ConsultService].
  ///
  /// Failures propagate: [ConsultService.sendPayload] has to know a frame
  /// never left the device, otherwise a patient is told their case was sent
  /// when it was not (issue #17 review).
  @override
  Future<void> sendBytes(String endpointId, Uint8List bytes) async {
    try {
      await _nearby.sendBytesPayload(endpointId, bytes);
    } catch (e) {
      debugPrint('Send bytes error: $e');
      rethrow;
    }
  }

  // ── Disconnect ─────────────────────────────────────────────
  void disconnect(String endpointId) {
    _nearby.disconnectFromEndpoint(endpointId);
    final name = _connectedDevices.remove(endpointId);
    notifyListeners();
    onPeerDisconnected?.call(endpointId);
    onConnectionChanged?.call(endpointId, name ?? '', false);
  }

  Future<void> stopAll() async {
    await stopAdvertising();
    await stopDiscovery();
    _nearby.stopAllEndpoints();
    final dropped = _connectedDevices.keys.toList(growable: false);
    _connectedDevices.clear();
    _discoveredDevices.clear();
    _pendingConnections.clear();
    for (final id in dropped) {
      onPeerDisconnected?.call(id);
    }
    notifyListeners();
  }

  // ── Internal callbacks ─────────────────────────────────────
  void _onConnectionInit(String id, ConnectionInfo info) {
    debugPrint('Connection initiated: $id  ${info.endpointName}');
    // Auto-accept all incoming connections
    _pendingConnections[id] = info.endpointName;
    notifyListeners();
    _nearby.acceptConnection(
      id,
      onPayLoadRecieved: (String endpointId, Payload payload) {
        if (payload.type == PayloadType.BYTES && payload.bytes != null) {
          final bytes = payload.bytes!;
          // Consult frames start with the 'RS' magic; everything else is
          // legacy plain-text chat.
          if (bytes.length >= ConsultFrame.headerLength &&
              bytes[0] == ConsultFrame.magic0 &&
              bytes[1] == ConsultFrame.magic1) {
            onBytesReceived?.call(endpointId, bytes);
          } else {
            onMessageReceived?.call(endpointId, utf8.decode(bytes));
          }
        }
      },
    );
  }

  void _onConnectionResult(String id, Status status) {
    _pendingConnections.remove(id);
    if (status == Status.CONNECTED) {
      // Move from discovered → connected
      final name = _discoveredDevices.remove(id) ?? 'Unknown';
      _connectedDevices[id] = name;
      onConnectionChanged?.call(id, name, true);
    }
    notifyListeners();
  }

  void _onDisconnected(String id) {
    final name = _connectedDevices.remove(id);
    notifyListeners();
    // Tell the consult layer first: a session whose transport is gone must
    // not keep reporting itself verified, or the peer can never re-handshake
    // when it comes back.
    onPeerDisconnected?.call(id);
    onConnectionChanged?.call(id, name ?? '', false);
  }
}
