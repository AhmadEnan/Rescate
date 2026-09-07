/// Rescate Bluetooth mesh networking — offline peer discovery,
/// connection, and message exchange via Google Nearby Connections.
///
/// `NearbyService` is a singleton: any feature can call
/// `NearbyService()` and receive the same instance. Lifecycle
/// (advertising/discovery) is currently owned by the Community
/// feature; other features can call [NearbyService.sendMessage]
/// freely once peers are connected.
///
/// For authenticated consultations (issue #17), [ConsultService] runs the
/// badge-verified handshake and encrypted sessions on top of the same
/// transport.
library bluetooth_mesh;

export 'src/bt_message.dart';
export 'src/consult_frame.dart';
export 'src/consult_service.dart';
export 'src/nearby_service.dart';
