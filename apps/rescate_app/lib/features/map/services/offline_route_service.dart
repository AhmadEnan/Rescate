import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

class OfflineDangerZone {
  final LatLng center;
  final double radius;

  const OfflineDangerZone({
    required this.center,
    required this.radius,
  });
}

class OfflineRouteService {
  static const MethodChannel _channel = MethodChannel('rescate/offline_routing');

  Future<OfflineRouteResult> findRoute({
    required LatLng start,
    required LatLng destination,
    required List<OfflineDangerZone> dangerZones,
  }) async {
    try {
      final response = await _channel.invokeMethod<List<dynamic>>(
        'findRoute',
        {
          'start': {'lat': start.latitude, 'lng': start.longitude},
          'destination': {
            'lat': destination.latitude,
            'lng': destination.longitude,
          },
          'dangerZones': dangerZones
              .map(
                (zone) => {
                  'lat': zone.center.latitude,
                  'lng': zone.center.longitude,
                  'radius': zone.radius,
                },
              )
              .toList(),
        },
      );

      if (response == null || response.isEmpty) {
        return const OfflineRouteResult.unavailable();
      }

      final points = response.map((item) {
        final point = Map<String, dynamic>.from(item as Map);
        return LatLng(
          (point['lat'] as num).toDouble(),
          (point['lng'] as num).toDouble(),
        );
      }).toList();

      return OfflineRouteResult.available(points);
    } on MissingPluginException {
      return const OfflineRouteResult.unavailable();
    } on PlatformException {
      return const OfflineRouteResult.unavailable();
    }
  }
}

class OfflineRouteResult {
  final List<LatLng> points;
  final bool isAvailable;

  const OfflineRouteResult.available(this.points) : isAvailable = true;

  const OfflineRouteResult.unavailable()
      : points = const [],
        isAvailable = false;
}
