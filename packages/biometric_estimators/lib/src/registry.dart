import 'package:sensor_availability/sensor_availability.dart';

import 'core/biometric_estimator.dart';
import 'estimators/acoustic_respiration.dart';
import 'estimators/flicker_dosimetry.dart';
import 'estimators/grip_strength.dart';
import 'estimators/gyrocardiography.dart';
import 'estimators/ppg_cardiovascular.dart';
import 'estimators/proximity_respiration.dart';
import 'estimators/pupillometry.dart';
import 'estimators/seismocardiography.dart';
import 'estimators/spirometry.dart';
import 'estimators/stubs.dart';

class BiometricEstimatorRegistry {
  BiometricEstimatorRegistry._();

  static final BiometricEstimatorRegistry instance =
      BiometricEstimatorRegistry._();

  late final Map<BiometricId, BiometricEstimator>
  _byId = <BiometricId, BiometricEstimator>{
    BiometricId.ppgCardiovascular: PpgCardiovascularEstimator(),
    BiometricId.seismocardiography: SeismocardiographyEstimator(),
    BiometricId.gyrocardiography: GyrocardiographyEstimator(),
    BiometricId.acousticRespiration: AcousticRespirationEstimator(),
    BiometricId.flickerDosimetry: FlickerDosimetryEstimator(),
    BiometricId.gripStrength: GripStrengthEstimator(),
    BiometricId.spirometry: SpirometryEstimator(),
    BiometricId.pupillometry: PupillometryEstimator(),
    BiometricId.infraredRespiration: const ProximityRespirationEstimator(
      BiometricId.infraredRespiration,
    ),
    BiometricId.ultrasonicRespiration: const ProximityRespirationEstimator(
      BiometricId.ultrasonicRespiration,
    ),
    BiometricId.magneticBiomarkerAssay: const StubEstimator(
      BiometricId.magneticBiomarkerAssay,
    ),
    BiometricId.scleralBilirubin: const StubEstimator(
      BiometricId.scleralBilirubin,
    ),
    BiometricId.ocularImaging: const StubEstimator(BiometricId.ocularImaging),
    BiometricId.wound3dMorphometry: const StubEstimator(
      BiometricId.wound3dMorphometry,
    ),
    BiometricId.gaitAnalysis: const StubEstimator(BiometricId.gaitAnalysis),
    BiometricId.radarCardiopulmonary: const StubEstimator(
      BiometricId.radarCardiopulmonary,
    ),
    BiometricId.dermatoglyphics: const StubEstimator(
      BiometricId.dermatoglyphics,
    ),
    BiometricId.arterialStiffness: const StubEstimator(
      BiometricId.arterialStiffness,
    ),
    BiometricId.pulseOximetry: const StubEstimator(BiometricId.pulseOximetry),
    BiometricId.coreBodyTemperature: const StubEstimator(
      BiometricId.coreBodyTemperature,
    ),
  };

  BiometricEstimator forId(BiometricId id) {
    return _byId[id]!;
  }

  List<BiometricEstimator> get all {
    return List<BiometricEstimator>.unmodifiable(_byId.values);
  }
}
