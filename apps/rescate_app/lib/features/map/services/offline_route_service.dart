import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

class OfflineDangerZone {
  final LatLng center;
  final double radius;

  const OfflineDangerZone({required this.center, required this.radius});
}

class OfflineRouteService {
  static const MethodChannel _channel = MethodChannel(
    'rescate/offline_routing',
  );
  final Distance _distance = const Distance();

  Future<bool> prepareRoadGraph({
    required LatLng center,
    required double radiusKm,
  }) async {
    final latDelta = radiusKm / 111.32;
    final lngDelta =
        radiusKm / (111.32 * math.cos(center.latitude * math.pi / 180)).abs();

    try {
      final result = await _channel.invokeMethod<bool>('prepareRoadGraph', {
        'south': center.latitude - latDelta,
        'west': center.longitude - lngDelta,
        'north': center.latitude + latDelta,
        'east': center.longitude + lngDelta,
      });
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<OfflineRouteResult> findRoute({
    required LatLng start,
    required LatLng destination,
    required List<OfflineDangerZone> dangerZones,
  }) async {
    try {
      final response = await _channel.invokeMethod<List<dynamic>>('findRoute', {
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
      });

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

      if (_routeTouchesAnyDanger(points, dangerZones)) {
        return const OfflineRouteResult.unavailable();
      }

      return OfflineRouteResult.available(points);
    } on MissingPluginException {
      return const OfflineRouteResult.unavailable();
    } on PlatformException {
      return const OfflineRouteResult.unavailable();
    }
  }

  bool _routeTouchesAnyDanger(
    List<LatLng> route,
    List<OfflineDangerZone> dangerZones,
  ) {
    for (var index = 0; index < route.length - 1; index++) {
      for (final zone in dangerZones) {
        if (_segmentDistanceMeters(
              route[index],
              route[index + 1],
              zone.center,
            ) <=
            zone.radius) {
          return true;
        }
      }
    }
    return false;
  }

  double _segmentDistanceMeters(LatLng start, LatLng end, LatLng point) {
    const metersPerLatDegree = 111320.0;
    final metersPerLngDegree =
        metersPerLatDegree * math.cos(point.latitude * math.pi / 180);
    final ax = start.longitude * metersPerLngDegree;
    final ay = start.latitude * metersPerLatDegree;
    final bx = end.longitude * metersPerLngDegree;
    final by = end.latitude * metersPerLatDegree;
    final px = point.longitude * metersPerLngDegree;
    final py = point.latitude * metersPerLatDegree;
    final dx = bx - ax;
    final dy = by - ay;
    final lengthSquared = dx * dx + dy * dy;
    if (lengthSquared == 0) return _distance.as(LengthUnit.Meter, start, point);
    final t = (((px - ax) * dx) + ((py - ay) * dy)) / lengthSquared;
    final clamped = t.clamp(0.0, 1.0);
    final nearestX = ax + dx * clamped;
    final nearestY = ay + dy * clamped;
    return math.sqrt(
      math.pow(px - nearestX, 2).toDouble() +
          math.pow(py - nearestY, 2).toDouble(),
    );
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
