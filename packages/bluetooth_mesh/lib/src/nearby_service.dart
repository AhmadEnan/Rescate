// TODO(security): wire Ed25519 ephemeral identity per CONTRIBUTING.md
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:device_info_plus/device_info_plus.dart';

/// Wraps the Google Nearby Connections API for Bluetooth/Wi-Fi P2P messaging.
///
/// Singleton — every screen shares the same instance so connection state
/// survives navigation.
class NearbyService extends ChangeNotifier {
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

  /// Incoming message callback — set by chat screen
  void Function(String endpointId, String message)? onMessageReceived;

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
      await _nearby.startAdvertising(
        _userName,
        Strategy.P2P_CLUSTER,
        serviceId: _serviceId,
        onConnectionInitiated: _onConnectionInit,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );
      _isAdvertising = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Advertising error: $e');
    }
  }

  Future<void> stopAdvertising() async {
    try {
      await _nearby.stopAdvertising();
    } catch (_) {}
    _isAdvertising = false;
    notifyListeners();
  }

  // ── Discover (find nearby users) ───────────────────────────
  Future<void> startDiscovery() async {
    if (_isDiscovering) return;
    try {
      await _nearby.startDiscovery(
        _userName,
        Strategy.P2P_CLUSTER,
        serviceId: _serviceId,
        onEndpointFound: (String id, String name, String serviceId) {
          _discoveredDevices[id] = name;
          notifyListeners();
        },
        onEndpointLost: (String? id) {
          if (id != null) {
            _discoveredDevices.remove(id);
            notifyListeners();
          }
        },
      );
      _isDiscovering = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Discovery error: $e');
    }
  }

  Future<void> stopDiscovery() async {
    try {
      await _nearby.stopDiscovery();
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
      await _nearby.sendBytesPayload(
        endpointId,
        Uint8List.fromList(utf8.encode(text)),
      );
    } catch (e) {
      debugPrint('Send error: $e');
    }
  }

  // ── Disconnect ─────────────────────────────────────────────
  void disconnect(String endpointId) {
    _nearby.disconnectFromEndpoint(endpointId);
    final name = _connectedDevices.remove(endpointId);
    notifyListeners();
    onConnectionChanged?.call(endpointId, name ?? '', false);
  }

  Future<void> stopAll() async {
    await stopAdvertising();
    await stopDiscovery();
    _nearby.stopAllEndpoints();
    _connectedDevices.clear();
    _discoveredDevices.clear();
    _pendingConnections.clear();
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
          final message = utf8.decode(payload.bytes!);
          onMessageReceived?.call(endpointId, message);
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
    onConnectionChanged?.call(id, name ?? '', false);
  }
}
