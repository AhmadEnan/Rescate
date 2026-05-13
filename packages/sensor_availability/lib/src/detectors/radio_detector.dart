import '../sensor_id.dart';
import '../sensor_report.dart';
import '../sensor_status.dart';
import 'native_probe.dart';

List<SensorReport> detectRadio(NativeProbe probe) {
  if (!probe.platformSupported || probe.uwbRadar == null) {
    return const <SensorReport>[
      SensorReport(
        id: SensorId.radar,
        status: SensorStatus.unknown,
        method: 'fallback',
        detail: 'Native radio query unavailable',
      ),
      SensorReport(
        id: SensorId.uwb,
        status: SensorStatus.unknown,
        method: 'fallback',
        detail: 'Native radio query unavailable',
      ),
    ];
  }
  return <SensorReport>[
    SensorReport(
      id: SensorId.radar,
      status: probe.uwbRadar!.radar
          ? SensorStatus.available
          : SensorStatus.unavailable,
      method: 'PackageManager features + known-device list',
    ),
    SensorReport(
      id: SensorId.uwb,
      status: probe.uwbRadar!.uwb
          ? SensorStatus.available
          : SensorStatus.unavailable,
      method: 'UwbManager / NISession.isSupported',
    ),
  ];
}
