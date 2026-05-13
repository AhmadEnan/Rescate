import '../platform/native_sensor_channel.dart';

export '../platform/native_sensor_channel.dart'
    show
        BiometryAvailability,
        DepthAvailability,
        MotionAvailability,
        NativeSensorEntry,
        UwbRadarAvailability;

/// Snapshot of every native query made during a single `detectAll()` run.
/// Detectors read from this and never call the channel themselves — that keeps
/// detection pure and makes mocking in tests straightforward.
class NativeProbe {
  const NativeProbe({
    required this.platformSupported,
    required this.sensors,
    required this.motion,
    required this.depth,
    required this.uwbRadar,
    required this.biometry,
    required this.thermistor,
    required this.microphone,
    required this.cameraIds,
    required this.featureFingerprint,
    required this.featureFace,
    required this.featureIris,
    required this.featureMicrophone,
  });

  /// True when running on Android or iOS. Other platforms produce
  /// all-`unknown` reports.
  final bool platformSupported;

  /// Android only — full list of registered sensors (empty on iOS / unsupported).
  final List<NativeSensorEntry> sensors;

  final MotionAvailability? motion;
  final DepthAvailability? depth;
  final UwbRadarAvailability? uwbRadar;
  final BiometryAvailability? biometry;
  final bool? thermistor;
  final bool? microphone;
  final List<String> cameraIds;

  final bool? featureFingerprint;
  final bool? featureFace;
  final bool? featureIris;
  final bool? featureMicrophone;

  /// True if any registered Android sensor name or vendor string contains
  /// [needle] (case-insensitive).
  bool sensorNameContains(String needle) {
    final String lower = needle.toLowerCase();
    return sensors.any(
      (NativeSensorEntry s) =>
          s.name.toLowerCase().contains(lower) ||
          s.vendor.toLowerCase().contains(lower),
    );
  }

  /// Android Sensor TYPE_* constant lookup. See
  /// https://developer.android.com/reference/android/hardware/Sensor
  bool hasAndroidSensorType(int type) =>
      sensors.any((NativeSensorEntry s) => s.type == type);
}

/// Android `Sensor.TYPE_*` constants we care about. Kept here so detectors can
/// reference them by name.
abstract class AndroidSensorType {
  static const int accelerometer = 1;
  static const int magneticField = 2;
  static const int gyroscope = 4;
  static const int light = 5;
  static const int pressure = 6;
  static const int proximity = 8;
  static const int ambientTemperature = 13;
  static const int heartRate = 21;
  static const int hingeAngle = 36;
  static const int heartBeat = 31;
}
