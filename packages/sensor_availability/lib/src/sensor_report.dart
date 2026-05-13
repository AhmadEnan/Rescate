import 'sensor_id.dart';
import 'sensor_status.dart';

class SensorReport {
  const SensorReport({
    required this.id,
    required this.status,
    required this.method,
    this.detail = '',
  });

  final SensorId id;
  final SensorStatus status;

  /// Short tag describing how the result was obtained
  /// (e.g. "android.sensor.TYPE_ACCELEROMETER", "ARKit", "fallback").
  final String method;

  /// Human-readable explanation, especially for `unknown` / `needsPermission`.
  final String detail;

  SensorReport copyWith({
    SensorStatus? status,
    String? method,
    String? detail,
  }) {
    return SensorReport(
      id: id,
      status: status ?? this.status,
      method: method ?? this.method,
      detail: detail ?? this.detail,
    );
  }
}
