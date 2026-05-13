import '../sensor_id.dart';
import '../sensor_report.dart';
import '../sensor_status.dart';
import 'native_probe.dart';

List<SensorReport> detectMotion(NativeProbe probe) {
  if (!probe.platformSupported) {
    return _allUnknown();
  }
  final MotionAvailability? m = probe.motion;
  if (m == null) {
    return _allUnknown();
  }
  return <SensorReport>[
    SensorReport(
      id: SensorId.accelerometer,
      status: m.accelerometer
          ? SensorStatus.available
          : SensorStatus.unavailable,
      method: 'CMMotionManager / TYPE_ACCELEROMETER',
    ),
    SensorReport(
      id: SensorId.gyroscope,
      status: m.gyroscope ? SensorStatus.available : SensorStatus.unavailable,
      method: 'CMMotionManager / TYPE_GYROSCOPE',
    ),
    SensorReport(
      id: SensorId.magnetometer,
      status: m.magnetometer
          ? SensorStatus.available
          : SensorStatus.unavailable,
      method: 'CMMotionManager / TYPE_MAGNETIC_FIELD',
    ),
    SensorReport(
      id: SensorId.barometer,
      status: m.barometer ? SensorStatus.available : SensorStatus.unavailable,
      method: 'CMAltimeter / TYPE_PRESSURE',
    ),
  ];
}

List<SensorReport> _allUnknown() {
  const String reason = 'Native motion query unavailable';
  return const <SensorReport>[
    SensorReport(
      id: SensorId.accelerometer,
      status: SensorStatus.unknown,
      method: 'fallback',
      detail: reason,
    ),
    SensorReport(
      id: SensorId.gyroscope,
      status: SensorStatus.unknown,
      method: 'fallback',
      detail: reason,
    ),
    SensorReport(
      id: SensorId.magnetometer,
      status: SensorStatus.unknown,
      method: 'fallback',
      detail: reason,
    ),
    SensorReport(
      id: SensorId.barometer,
      status: SensorStatus.unknown,
      method: 'fallback',
      detail: reason,
    ),
  ];
}
