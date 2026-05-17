// Module 7 — Device Sensor Availability.
//
// Public surface: import 'package:sensor_availability/sensor_availability.dart'
// and call SensorAvailabilityService.instance.detectAll() once at startup.

export 'src/biometric_catalog.dart'
    show biometricCatalog, biometricDescriptorFor;
export 'src/biometric_descriptor.dart';
export 'src/biometric_id.dart';
export 'src/biometric_report.dart';
export 'src/biometric_resolver.dart' show resolveBiometrics;
export 'src/sensor_availability_service.dart';
export 'src/sensor_catalog.dart' show sensorCatalog, descriptorFor;
export 'src/sensor_descriptor.dart';
export 'src/sensor_id.dart';
export 'src/sensor_report.dart';
export 'src/sensor_status.dart';
export 'src/widgets/biometric_availability_screen.dart';
export 'src/widgets/sensor_availability_screen.dart';
