enum SensorStatus { available, unavailable, unknown, needsPermission }

extension SensorStatusDisplay on SensorStatus {
  String get label {
    switch (this) {
      case SensorStatus.available:
        return 'Available';
      case SensorStatus.unavailable:
        return 'Unavailable';
      case SensorStatus.unknown:
        return 'Unknown';
      case SensorStatus.needsPermission:
        return 'Needs Permission';
    }
  }
}
