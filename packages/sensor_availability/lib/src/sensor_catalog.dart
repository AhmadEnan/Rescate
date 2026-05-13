import 'sensor_descriptor.dart';
import 'sensor_id.dart';

/// Stable, ordered catalog of all 26 sensors detected by this package.
/// The order here is the order shown on the report screen.
const List<SensorDescriptor> sensorCatalog = <SensorDescriptor>[
  SensorDescriptor(
    id: SensorId.accelerometer,
    displayName: 'Accelerometer',
    category: SensorCategory.motionAndOrientation,
    description:
        'Measures proper acceleration and changes in velocity along three axes (X, Y, Z) via a MEMS microscopic mass.',
  ),
  SensorDescriptor(
    id: SensorId.gyroscope,
    displayName: 'Gyroscope',
    category: SensorCategory.motionAndOrientation,
    description:
        'Measures angular velocity and rotation across three axes via the Coriolis effect on a vibrating mass.',
  ),
  SensorDescriptor(
    id: SensorId.magnetometer,
    displayName: 'Magnetometer (Compass)',
    category: SensorCategory.motionAndOrientation,
    description:
        'Measures the strength and direction of ambient magnetic fields, especially Earth\'s magnetic north.',
  ),
  SensorDescriptor(
    id: SensorId.barometer,
    displayName: 'Barometer',
    category: SensorCategory.motionAndOrientation,
    description:
        'Measures absolute atmospheric pressure via a piezoresistive element deformed by air weight.',
  ),
  SensorDescriptor(
    id: SensorId.ambientLight,
    displayName: 'Ambient Light Sensor',
    category: SensorCategory.environment,
    description:
        'Measures illuminance of visible ambient light via a photodiode generating a proportional current.',
  ),
  SensorDescriptor(
    id: SensorId.colorTemperature,
    displayName: 'Color Temperature / Spectral Sensor',
    category: SensorCategory.environment,
    description:
        'Measures spectral composition and color temperature of ambient light by separating it into RGB (and sometimes IR or clear) channels.',
  ),
  SensorDescriptor(
    id: SensorId.flicker,
    displayName: 'Flicker Sensor',
    category: SensorCategory.environment,
    description:
        'Measures high-frequency intensity modulations of artificial lighting at very high polling rates.',
  ),
  SensorDescriptor(
    id: SensorId.proximityIr,
    displayName: 'Proximity Sensor (Infrared)',
    category: SensorCategory.proximityAndDepth,
    description:
        'Detects nearby objects by emitting an invisible IR beam and measuring reflected light at a photodiode.',
  ),
  SensorDescriptor(
    id: SensorId.proximityUltrasonic,
    displayName: 'Proximity Sensor (Ultrasonic)',
    category: SensorCategory.proximityAndDepth,
    description:
        'Detects nearby objects by emitting inaudible high-frequency sound waves and timing the echo.',
  ),
  SensorDescriptor(
    id: SensorId.timeOfFlight,
    displayName: 'Time-of-Flight Camera',
    category: SensorCategory.proximityAndDepth,
    description:
        'Measures distance to objects by illuminating the scene with modulated IR pulses and computing phase shift / travel time.',
  ),
  SensorDescriptor(
    id: SensorId.lidar,
    displayName: 'LiDAR Scanner',
    category: SensorCategory.proximityAndDepth,
    description:
        'Measures precise distances and depth maps by firing arrays of laser pulses and timing nanosecond reflections.',
  ),
  SensorDescriptor(
    id: SensorId.radar,
    displayName: 'Miniature Radar (Soli)',
    category: SensorCategory.radio,
    description:
        'Measures sub-millimeter distance, motion, and velocity using continuous RF waves and Doppler shift analysis.',
  ),
  SensorDescriptor(
    id: SensorId.uwb,
    displayName: 'Ultra-Wideband (UWB) Transceiver',
    category: SensorCategory.radio,
    description:
        'Measures precise spatial location, distance, and direction of other UWB nodes via short-pulse RF signals.',
  ),
  SensorDescriptor(
    id: SensorId.hallEffect,
    displayName: 'Hall Effect Sensor',
    category: SensorCategory.system,
    description:
        'Detects magnetic field magnitude to track moving parts (e.g. foldable hinges, magnetic cases) via voltage changes.',
  ),
  SensorDescriptor(
    id: SensorId.fingerprintCapacitive,
    displayName: 'Capacitive Fingerprint Sensor',
    category: SensorCategory.biometric,
    description:
        'Measures microscopic electrical capacitance differences between fingerprint ridges and valleys.',
  ),
  SensorDescriptor(
    id: SensorId.fingerprintOptical,
    displayName: 'Optical Fingerprint Sensor',
    category: SensorCategory.biometric,
    description:
        'Captures a 2D visual representation of the fingerprint via under-display micro-camera reflection.',
  ),
  SensorDescriptor(
    id: SensorId.fingerprintUltrasonic,
    displayName: 'Ultrasonic Fingerprint Sensor',
    category: SensorCategory.biometric,
    description:
        'Maps the 3D topography of fingerprint ridges and pores via ultrasonic pulses and acoustic impedance.',
  ),
  SensorDescriptor(
    id: SensorId.structuredLightFace,
    displayName: 'Structured Light 3D Scanner',
    category: SensorCategory.biometric,
    description:
        'Maps facial topography by projecting thousands of invisible IR dots and measuring geometric distortion.',
  ),
  SensorDescriptor(
    id: SensorId.iris,
    displayName: 'Iris Scanner',
    category: SensorCategory.biometric,
    description:
        'Captures unique iris patterns under near-infrared illumination for high-contrast biometric matching.',
  ),
  SensorDescriptor(
    id: SensorId.heartRatePpg,
    displayName: 'PPG / Heart Rate Sensor',
    category: SensorCategory.vitals,
    description:
        'Measures volumetric blood circulation variations via green/red light absorption (photoplethysmography).',
  ),
  SensorDescriptor(
    id: SensorId.pulseOximeter,
    displayName: 'Pulse Oximeter (SpO2)',
    category: SensorCategory.vitals,
    description:
        'Measures blood oxygen saturation by comparing red and IR light absorption ratios through tissue.',
  ),
  SensorDescriptor(
    id: SensorId.skinTemperatureThermopile,
    displayName: 'Skin / Object Temperature (Thermopile)',
    category: SensorCategory.vitals,
    description:
        'Measures emitted IR thermal radiation to compute non-contact surface temperature.',
  ),
  SensorDescriptor(
    id: SensorId.internalThermistor,
    displayName: 'Internal Thermistor',
    category: SensorCategory.system,
    description:
        'Measures internal thermal output of CPU/battery components via temperature-dependent resistors.',
  ),
  SensorDescriptor(
    id: SensorId.strainGauge,
    displayName: 'Strain Gauge / Squeeze Sensor',
    category: SensorCategory.system,
    description:
        'Detects mechanical strain on the chassis via resistance changes when pressure is applied.',
  ),
  SensorDescriptor(
    id: SensorId.memsMicrophone,
    displayName: 'MEMS Microphone',
    category: SensorCategory.audioVisual,
    description:
        'Measures acoustic sound waves via diaphragm displacement responding to air-pressure variations.',
  ),
  SensorDescriptor(
    id: SensorId.cmosImageSensor,
    displayName: 'CMOS Image Sensor',
    category: SensorCategory.audioVisual,
    description:
        'Measures intensity and wavelength of incoming photons via millions of microscopic photosites.',
  ),
];

SensorDescriptor descriptorFor(SensorId id) {
  return sensorCatalog.firstWhere((SensorDescriptor d) => d.id == id);
}
