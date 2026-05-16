/// Rescate Bluetooth mesh networking — offline peer discovery,
/// connection, and message exchange via Google Nearby Connections.
///
/// `NearbyService` is a singleton: any feature can call
/// `NearbyService()` and receive the same instance. Lifecycle
/// (advertising/discovery) is currently owned by the Community
/// feature; other features can call [NearbyService.sendMessage]
/// freely once peers are connected.
library bluetooth_mesh;

export 'src/bt_message.dart';
export 'src/nearby_service.dart';
