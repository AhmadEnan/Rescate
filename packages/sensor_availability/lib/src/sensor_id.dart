enum SensorCategory {
  motionAndOrientation,
  environment,
  proximityAndDepth,
  radio,
  biometric,
  vitals,
  system,
  audioVisual,
}

extension SensorCategoryDisplay on SensorCategory {
  String get displayName {
    switch (this) {
      case SensorCategory.motionAndOrientation:
        return 'Motion & Orientation';
      case SensorCategory.environment:
        return 'Environment';
      case SensorCategory.proximityAndDepth:
        return 'Proximity & Depth';
      case SensorCategory.radio:
        return 'Radio';
      case SensorCategory.biometric:
        return 'Biometric';
      case SensorCategory.vitals:
        return 'Vitals';
      case SensorCategory.system:
        return 'System';
      case SensorCategory.audioVisual:
        return 'Audio / Visual';
    }
  }
}

enum SensorId {
  accelerometer,
  gyroscope,
  magnetometer,
  barometer,
  ambientLight,
  colorTemperature,
  flicker,
  proximityIr,
  proximityUltrasonic,
  timeOfFlight,
  lidar,
  radar,
  uwb,
  hallEffect,
  fingerprintCapacitive,
  fingerprintOptical,
  fingerprintUltrasonic,
  structuredLightFace,
  iris,
  heartRatePpg,
  pulseOximeter,
  skinTemperatureThermopile,
  internalThermistor,
  strainGauge,
  memsMicrophone,
  cmosImageSensor,
}
