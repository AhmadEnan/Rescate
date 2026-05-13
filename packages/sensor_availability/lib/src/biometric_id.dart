enum BiometricId {
  seismocardiography,
  gyrocardiography,
  magneticBiomarkerAssay,
  spirometry,
  acousticRespiration,
  ultrasonicRespiration,
  infraredRespiration,
  pupillometry,
  scleralBilirubin,
  flickerDosimetry,
  ocularImaging,
  wound3dMorphometry,
  gaitAnalysis,
  radarCardiopulmonary,
  dermatoglyphics,
  arterialStiffness,
  ppgCardiovascular,
  pulseOximetry,
  coreBodyTemperature,
  gripStrength,
}

enum BiometricStatus {
  /// At least one source sensor is `available`.
  available,

  /// No source sensor is `available`, but at least one is `unknown` or
  /// `needsPermission` — the biometric *might* be measurable.
  potentiallyAvailable,

  /// Every source sensor is `unavailable`.
  unavailable,
}
