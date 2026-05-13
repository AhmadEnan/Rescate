import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Thin wrapper over the `dev.rescate/sensor_availability` MethodChannel.
///
/// All methods catch `MissingPluginException` / `PlatformException` and return
/// `null` so callers can treat that as `unknown` instead of crashing the app.
class NativeSensorChannel {
  NativeSensorChannel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'dev.rescate/sensor_availability';

  final MethodChannel _channel;

  /// Android-only. Returns one entry per registered Sensor with its TYPE_*
  /// constant, name, and vendor string. iOS / unsupported platforms → empty.
  Future<List<NativeSensorEntry>?> listNativeSensors() async {
    final List<Object?>? raw = await _invoke<List<Object?>>(
      'listNativeSensors',
    );
    if (raw == null) {
      return null;
    }
    return raw
        .whereType<Map<Object?, Object?>>()
        .map(
          (Map<Object?, Object?> e) => NativeSensorEntry(
            type: (e['type'] as int?) ?? -1,
            name: (e['name'] as String?) ?? '',
            vendor: (e['vendor'] as String?) ?? '',
          ),
        )
        .toList(growable: false);
  }

  Future<bool?> hasSystemFeature(String name) {
    return _invoke<bool>('hasSystemFeature', <String, Object?>{'name': name});
  }

  Future<MotionAvailability?> motionAvailability() async {
    final Map<Object?, Object?>? m = await _invoke<Map<Object?, Object?>>(
      'motionAvailability',
    );
    if (m == null) {
      return null;
    }
    return MotionAvailability(
      accelerometer: m['accel'] == true,
      gyroscope: m['gyro'] == true,
      magnetometer: m['mag'] == true,
      barometer: m['baro'] == true,
    );
  }

  Future<DepthAvailability?> cameraDepthCapability() async {
    final Map<Object?, Object?>? m = await _invoke<Map<Object?, Object?>>(
      'cameraDepthCapability',
    );
    if (m == null) {
      return null;
    }
    return DepthAvailability(
      hasLidar: m['hasLidar'] == true,
      hasToF: m['hasToF'] == true,
      hasDepthOutputCamera: m['hasDepthOutputCamera'] == true,
    );
  }

  Future<UwbRadarAvailability?> uwbRadarAvailability() async {
    final Map<Object?, Object?>? m = await _invoke<Map<Object?, Object?>>(
      'uwbRadarAvailability',
    );
    if (m == null) {
      return null;
    }
    return UwbRadarAvailability(
      uwb: m['uwb'] == true,
      radar: m['radar'] == true,
    );
  }

  Future<BiometryAvailability?> biometryAvailability() async {
    final Map<Object?, Object?>? m = await _invoke<Map<Object?, Object?>>(
      'biometryAvailability',
    );
    if (m == null) {
      return null;
    }
    return BiometryAvailability(
      fingerprint: m['fingerprint'] == true,
      face: m['face'] == true,
      iris: m['iris'] == true,
      faceStrongGuarantee: m['faceStrongGuarantee'] == true,
    );
  }

  Future<bool?> thermistorAvailable() async {
    final Map<Object?, Object?>? m = await _invoke<Map<Object?, Object?>>(
      'thermalAvailability',
    );
    if (m == null) {
      return null;
    }
    final Object? v = m['thermistor'];
    if (v is bool) {
      return v;
    }
    return null;
  }

  Future<bool?> microphoneAvailable() async {
    final Map<Object?, Object?>? m = await _invoke<Map<Object?, Object?>>(
      'microphoneAvailability',
    );
    if (m == null) {
      return null;
    }
    return m['available'] == true;
  }

  Future<List<String>?> cameraList() async {
    final List<Object?>? raw = await _invoke<List<Object?>>('cameraList');
    return raw?.map((Object? e) => e?.toString() ?? '').toList(growable: false);
  }

  Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('NativeSensorChannel.$method failed: ${e.code} ${e.message}');
      return null;
    }
  }
}

@immutable
class NativeSensorEntry {
  const NativeSensorEntry({
    required this.type,
    required this.name,
    required this.vendor,
  });

  final int type;
  final String name;
  final String vendor;
}

@immutable
class MotionAvailability {
  const MotionAvailability({
    required this.accelerometer,
    required this.gyroscope,
    required this.magnetometer,
    required this.barometer,
  });

  final bool accelerometer;
  final bool gyroscope;
  final bool magnetometer;
  final bool barometer;
}

@immutable
class DepthAvailability {
  const DepthAvailability({
    required this.hasLidar,
    required this.hasToF,
    required this.hasDepthOutputCamera,
  });

  final bool hasLidar;
  final bool hasToF;
  final bool hasDepthOutputCamera;
}

@immutable
class UwbRadarAvailability {
  const UwbRadarAvailability({required this.uwb, required this.radar});

  final bool uwb;
  final bool radar;
}

@immutable
class BiometryAvailability {
  const BiometryAvailability({
    required this.fingerprint,
    required this.face,
    required this.iris,
    required this.faceStrongGuarantee,
  });

  final bool fingerprint;
  final bool face;
  final bool iris;
  final bool faceStrongGuarantee;
}
