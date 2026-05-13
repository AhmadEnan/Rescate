import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart' as sensors;

class Vector3 {
  const Vector3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  double get magnitude => math.sqrt((x * x) + (y * y) + (z * z));
}

class ImuSource {
  ImuSource() : _accelerometer = null, _gyroscope = null, _barometer = null;

  ImuSource.forTesting({
    Stream<Vector3>? accelerometer,
    Stream<Vector3>? gyroscope,
    Stream<double>? barometer,
  }) : _accelerometer = accelerometer,
       _gyroscope = gyroscope,
       _barometer = barometer;

  final Stream<Vector3>? _accelerometer;
  final Stream<Vector3>? _gyroscope;
  final Stream<double>? _barometer;

  Stream<Vector3> accelerometer({required Duration windowSamplePeriod}) {
    final Stream<Vector3>? injected = _accelerometer;
    if (injected != null) {
      return injected;
    }
    return sensors
        .accelerometerEventStream(samplingPeriod: windowSamplePeriod)
        .map((sensors.AccelerometerEvent e) => Vector3(e.x, e.y, e.z));
  }

  Stream<Vector3> gyroscope({required Duration windowSamplePeriod}) {
    final Stream<Vector3>? injected = _gyroscope;
    if (injected != null) {
      return injected;
    }
    return sensors
        .gyroscopeEventStream(samplingPeriod: windowSamplePeriod)
        .map((sensors.GyroscopeEvent e) => Vector3(e.x, e.y, e.z));
  }

  Stream<double> barometerHpa() {
    final Stream<double>? injected = _barometer;
    if (injected != null) {
      return injected;
    }
    return sensors.barometerEventStream().map(
      (sensors.BarometerEvent e) => e.pressure,
    );
  }
}
