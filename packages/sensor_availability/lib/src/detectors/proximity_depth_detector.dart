import '../sensor_id.dart';
import '../sensor_report.dart';
import '../sensor_status.dart';
import 'native_probe.dart';

List<SensorReport> detectProximityAndDepth(NativeProbe probe) {
  return <SensorReport>[
    _detectProximityIr(probe),
    _detectProximityUltrasonic(probe),
    _detectToF(probe),
    _detectLidar(probe),
  ];
}

SensorReport _detectProximityIr(NativeProbe probe) {
  if (!probe.platformSupported) {
    return const SensorReport(
      id: SensorId.proximityIr,
      status: SensorStatus.unknown,
      method: 'fallback',
      detail: 'Platform not supported',
    );
  }
  if (probe.sensors.isNotEmpty) {
    final bool present = probe.hasAndroidSensorType(
      AndroidSensorType.proximity,
    );
    return SensorReport(
      id: SensorId.proximityIr,
      status: present ? SensorStatus.available : SensorStatus.unavailable,
      method: 'TYPE_PROXIMITY',
    );
  }
  return const SensorReport(
    id: SensorId.proximityIr,
    status: SensorStatus.unknown,
    method: 'iOS',
    detail:
        'iOS exposes UIDevice.isProximityMonitoringEnabled but not sensor presence',
  );
}

SensorReport _detectProximityUltrasonic(NativeProbe probe) {
  return const SensorReport(
    id: SensorId.proximityUltrasonic,
    status: SensorStatus.unknown,
    method: 'no public API',
    detail: 'Ultrasonic proximity is not exposed as a standard sensor type',
  );
}

SensorReport _detectToF(NativeProbe probe) {
  if (!probe.platformSupported || probe.depth == null) {
    return const SensorReport(
      id: SensorId.timeOfFlight,
      status: SensorStatus.unknown,
      method: 'fallback',
      detail: 'Native depth query unavailable',
    );
  }
  final bool present = probe.depth!.hasToF || probe.depth!.hasDepthOutputCamera;
  return SensorReport(
    id: SensorId.timeOfFlight,
    status: present ? SensorStatus.available : SensorStatus.unavailable,
    method: 'Camera2 DEPTH_OUTPUT / ARKit sceneDepth',
  );
}

SensorReport _detectLidar(NativeProbe probe) {
  if (!probe.platformSupported || probe.depth == null) {
    return const SensorReport(
      id: SensorId.lidar,
      status: SensorStatus.unknown,
      method: 'fallback',
      detail: 'Native depth query unavailable',
    );
  }
  return SensorReport(
    id: SensorId.lidar,
    status: probe.depth!.hasLidar
        ? SensorStatus.available
        : SensorStatus.unavailable,
    method: 'ARKit sceneReconstruction(.mesh)',
  );
}
