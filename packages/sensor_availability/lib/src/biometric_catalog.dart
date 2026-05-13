import 'biometric_descriptor.dart';
import 'biometric_id.dart';
import 'sensor_id.dart';

/// Canonical list of biometrics derivable from hardware sensors. Order is the
/// presentation order used by the UI screen.
const List<BiometricDescriptor> biometricCatalog = <BiometricDescriptor>[
  BiometricDescriptor(
    id: BiometricId.seismocardiography,
    displayName: 'Seismocardiography (SCG)',
    biomarker: 'Inter-beat intervals (IBIs), heart rate',
    methodology:
        'Band-pass filtering (0.5–40 Hz), adaptive peak detection of '
        'Aortic Valve Opening (AO).',
    application: 'Cardiac monitoring; automated seizure detection.',
    sourceSensors: <SensorId>[SensorId.accelerometer],
  ),
  BiometricDescriptor(
    id: BiometricId.gyrocardiography,
    displayName: 'Gyrocardiography (GCG)',
    biomarker: 'Cardiac angular momentum, IBIs',
    methodology:
        'High-pass filtering, spatial rotation integration, peak '
        'identification.',
    application: 'Non-invasive cardiac mechanical activity monitoring.',
    sourceSensors: <SensorId>[SensorId.gyroscope],
  ),
  BiometricDescriptor(
    id: BiometricId.magneticBiomarkerAssay,
    displayName: 'Magnetic Biomarker Assay',
    biomarker: 'Magnetic biomarker molarity; proximity signatures',
    methodology:
        'Pre-calibrated regression mapping; linear correlation algorithms.',
    application:
        'At-home biochemical analysis (glucose/pH); epidemiological '
        'contact tracing.',
    sourceSensors: <SensorId>[SensorId.magnetometer],
  ),
  BiometricDescriptor(
    id: BiometricId.spirometry,
    displayName: 'Spirometry',
    biomarker: 'Pulmonary function metrics (FVC, FEV1, PEF)',
    methodology:
        'Bernoulli equation approximations, moving-average filter, '
        'mathematical integration.',
    application:
        'Clinical-grade spirometry (asthma/COPD); altitude sickness '
        'prediction.',
    sourceSensors: <SensorId>[SensorId.barometer],
  ),
  BiometricDescriptor(
    id: BiometricId.acousticRespiration,
    displayName: 'Acoustic Respiration',
    biomarker: 'Fundamental breathing frequency; acoustic wheeze biomarkers',
    methodology:
        'Welch periodogram, autoregressive spectrum, spectrogram spectral '
        'analysis.',
    application:
        'Passive respiratory monitoring; pulmonary obstruction '
        'diagnosis.',
    sourceSensors: <SensorId>[SensorId.memsMicrophone],
  ),
  BiometricDescriptor(
    id: BiometricId.ultrasonicRespiration,
    displayName: 'Ultrasonic Respiration',
    biomarker: 'Mean inter-peak interval (IPI) for respiration',
    methodology:
        'Doppler effect modulation, Butterworth low-pass filtering, '
        'autocorrelation function.',
    application: 'Non-contact respiratory rate tracking.',
    sourceSensors: <SensorId>[SensorId.proximityUltrasonic],
  ),
  BiometricDescriptor(
    id: BiometricId.infraredRespiration,
    displayName: 'Infrared Respiration',
    biomarker: 'Dominant respiratory frequency',
    methodology:
        'Low-pass filtering and Fast Fourier Transform (FFT) '
        'analysis.',
    application: 'Sleep monitoring and apnea detection.',
    sourceSensors: <SensorId>[SensorId.proximityIr],
  ),
  BiometricDescriptor(
    id: BiometricId.pupillometry,
    displayName: 'Pupillometry',
    biomarker: 'Neuro-Pupillary Index (NPx)',
    methodology: 'Machine learning, LASSO regularization, stepwise regression.',
    application: 'High-precision pupillometry for TBI and stroke assessment.',
    sourceSensors: <SensorId>[SensorId.ambientLight],
  ),
  BiometricDescriptor(
    id: BiometricId.scleralBilirubin,
    displayName: 'Scleral-Conjunctival Bilirubin',
    biomarker: 'Scleral-Conjunctival Bilirubin (SCB)',
    methodology:
        'Ambient light subtraction, CIE xy chromaticity normalization, '
        'linear prediction models.',
    application:
        'Non-invasive jaundice screening for hepatic/pancreatic disorders.',
    sourceSensors: <SensorId>[SensorId.colorTemperature],
  ),
  BiometricDescriptor(
    id: BiometricId.flickerDosimetry,
    displayName: 'Flicker Dosimetry',
    biomarker: 'Dominant flicker frequencies and modulation depth',
    methodology:
        'Continuous Fast Fourier Transforms (FFT), machine learning '
        'causality modeling.',
    application:
        'Environmental dosimetry for photosensitive epilepsy and migraines.',
    sourceSensors: <SensorId>[SensorId.flicker],
  ),
  BiometricDescriptor(
    id: BiometricId.ocularImaging,
    displayName: 'Ocular Imaging',
    biomarker: 'Spatial distribution of lens opacities; cup-to-disc ratio',
    methodology:
        'Deep-learning transfer learning (MobileNet/ResNet), SVM with '
        'Gaussian kernels.',
    application: 'Cataract and glaucoma screening.',
    sourceSensors: <SensorId>[SensorId.cmosImageSensor, SensorId.iris],
  ),
  BiometricDescriptor(
    id: BiometricId.wound3dMorphometry,
    displayName: 'Wound 3D Morphometry',
    biomarker: '3D volumetric deficit; tissue granulation percentage',
    methodology:
        'CNN-based segmentation, edge-detection, coordinate mapping onto '
        'point clouds.',
    application: 'Morphometric wound mapping and tissue characterization.',
    sourceSensors: <SensorId>[SensorId.lidar, SensorId.structuredLightFace],
  ),
  BiometricDescriptor(
    id: BiometricId.gaitAnalysis,
    displayName: 'Gait Analysis',
    biomarker: 'Joint angles, stride length, walking velocity',
    methodology: 'Skeletal tracking models based on 3D point clouds.',
    application:
        'Posture recognition and gait analysis for neurodegenerative '
        'disorders.',
    sourceSensors: <SensorId>[SensorId.timeOfFlight],
  ),
  BiometricDescriptor(
    id: BiometricId.radarCardiopulmonary,
    displayName: 'Radar Cardiopulmonary',
    biomarker: 'Micro-displacements of the chest (HR/RR)',
    methodology:
        'Empirical Mode Decomposition (EMD), Continuous Wavelet '
        'Transforms (CWT), Hilbert–Huang Transform.',
    application:
        'Non-contact cardiopulmonary monitoring; sleep apnea '
        'detection.',
    sourceSensors: <SensorId>[SensorId.uwb, SensorId.radar],
  ),
  BiometricDescriptor(
    id: BiometricId.dermatoglyphics,
    displayName: 'Dermatoglyphics',
    biomarker: 'Ridge density and papillary ridge topology',
    methodology: 'Gabor filter convolution, minutiae extraction.',
    application:
        'Dermatoglyphic analysis for genetic abnormalities or ischemia.',
    sourceSensors: <SensorId>[
      SensorId.fingerprintCapacitive,
      SensorId.fingerprintOptical,
    ],
  ),
  BiometricDescriptor(
    id: BiometricId.arterialStiffness,
    displayName: 'Arterial Stiffness',
    biomarker: 'Acoustic impedance wave morphology; systolic rise time',
    methodology: 'Time-series impedance mapping, band-pass filtering.',
    application:
        'Localized cardiovascular hemodynamics and arterial stiffness '
        'monitoring.',
    sourceSensors: <SensorId>[SensorId.fingerprintUltrasonic],
  ),
  BiometricDescriptor(
    id: BiometricId.ppgCardiovascular,
    displayName: 'PPG Cardiovascular',
    biomarker: 'Blood volume waveform; Heart Rate Variability (HRV)',
    methodology:
        'RGB to HSV conversion, adaptive thresholding, peak detection.',
    application: 'Cardiovascular monitoring; blood pressure estimation.',
    sourceSensors: <SensorId>[SensorId.heartRatePpg, SensorId.cmosImageSensor],
  ),
  BiometricDescriptor(
    id: BiometricId.pulseOximetry,
    displayName: 'Pulse Oximetry',
    biomarker: 'Blood oxygen saturation percentage (SpO₂)',
    methodology:
        '"Ratio of ratios" (R) calculation based on AC/DC components of '
        '660 nm / 940 nm light.',
    application: 'Assessment of hypoxemia in pneumonia / COPD.',
    sourceSensors: <SensorId>[SensorId.pulseOximeter],
  ),
  BiometricDescriptor(
    id: BiometricId.coreBodyTemperature,
    displayName: 'Core Body Temperature',
    biomarker: 'Predicted steady-state equilibrium temperature',
    methodology:
        'Epsilon-Support Vector Regression (SVR), PLS Regression, '
        'Extra-Trees Regressors.',
    application: 'Proxy for Core Body Temperature (CBT) and fever screening.',
    sourceSensors: <SensorId>[
      SensorId.internalThermistor,
      SensorId.skinTemperatureThermopile,
    ],
  ),
  BiometricDescriptor(
    id: BiometricId.gripStrength,
    displayName: 'Grip Strength',
    biomarker: 'Vibrometric Force Estimation (VFE); squeeze profile',
    methodology:
        'Wheatstone-bridge voltage processing, FFT of dampened '
        'accelerometer signals, regression analysis.',
    application:
        'Hand grip strength (HGS) assessment for frailty and '
        'neurodegeneration.',
    sourceSensors: <SensorId>[SensorId.strainGauge, SensorId.accelerometer],
  ),
];

BiometricDescriptor biometricDescriptorFor(BiometricId id) {
  return biometricCatalog.firstWhere((BiometricDescriptor d) => d.id == id);
}
