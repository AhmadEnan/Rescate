import 'package:sensor_availability/sensor_availability.dart';

class CaptureProtocol {
  const CaptureProtocol({
    required this.preparation,
    required this.steps,
    required this.qualityTips,
  });

  final String preparation;
  final List<String> steps;
  final List<String> qualityTips;
}

CaptureProtocol captureProtocolFor(BiometricId id) {
  switch (id) {
    case BiometricId.ppgCardiovascular:
      return const CaptureProtocol(
        preparation:
            'Sit down, rest your hand on a table, and warm the fingertip if it is cold.',
        steps: <String>[
          'Use the rear camera.',
          'Cover both the camera lens and flash fully with the pad of one fingertip.',
          'Press lightly enough that the fingertip stays pink, not white.',
          'Keep the phone and finger still until capture finishes.',
        ],
        qualityTips: <String>[
          'Remove thick cases if they prevent the finger from sealing around the flash.',
          'Avoid moving, talking, or changing pressure during the first 10 seconds.',
          'Retry after 30 seconds of rest if the signal is weak.',
        ],
      );
    case BiometricId.seismocardiography:
      return const CaptureProtocol(
        preparation: 'Lie down or recline. Remove the phone case if it slips.',
        steps: <String>[
          'Place the phone flat on the center-left chest with the screen facing up.',
          'Rest both arms and breathe normally.',
          'Do not hold the phone in your hand during capture.',
        ],
        qualityTips: <String>[
          'A folded shirt or strap can reduce sliding.',
          'Pause if you cough, speak, or shift posture.',
        ],
      );
    case BiometricId.gyrocardiography:
      return const CaptureProtocol(
        preparation: 'Lie down or recline in a quiet position.',
        steps: <String>[
          'Place the long edge of the phone along the chest.',
          'Keep the phone still and avoid touching it after capture starts.',
          'Breathe normally and do not speak.',
        ],
        qualityTips: <String>[
          'Use the same phone orientation on repeated captures.',
          'Retry if the phone rocks or slides.',
        ],
      );
    case BiometricId.acousticRespiration:
      return const CaptureProtocol(
        preparation:
            'Move to a quiet room and silence fans, music, and speech.',
        steps: <String>[
          'Hold the phone 10-20 cm from your mouth or upper chest.',
          'Breathe normally through the nose or mouth.',
          'Keep the microphone opening uncovered.',
        ],
        qualityTips: <String>[
          'Do not rub the phone or clothing during capture.',
          'If the room is noisy, hold the microphone closer to the mouth.',
        ],
      );
    case BiometricId.flickerDosimetry:
      return const CaptureProtocol(
        preparation: 'Point the phone toward the light source being measured.',
        steps: <String>[
          'Use a steady grip or rest the phone on a surface.',
          'Keep the light source in view for the full capture.',
          'Do not point at the sun or an unsafe bright source.',
        ],
        qualityTips: <String>[
          'Avoid mixed lighting when possible.',
          'Measure one lamp or screen at a time.',
        ],
      );
    case BiometricId.gripStrength:
      return const CaptureProtocol(
        preparation: 'Hold the phone securely in one hand with no loose case.',
        steps: <String>[
          'Start relaxed.',
          'Squeeze hard and steadily for the capture window.',
          'Do not shake the phone intentionally.',
        ],
        qualityTips: <String>[
          'Use the same hand and grip position for repeated captures.',
          'Stop if squeezing causes pain.',
        ],
      );
    case BiometricId.spirometry:
      return const CaptureProtocol(
        preparation:
            'Stand or sit upright. This is an uncalibrated research proxy.',
        steps: <String>[
          'Hold the phone near the mouth, away from direct spit.',
          'Take a full breath in.',
          'Exhale forcefully and continuously for the capture window.',
        ],
        qualityTips: <String>[
          'Do not seal lips onto the phone.',
          'Repeat only after resting if you feel lightheaded.',
        ],
      );
    case BiometricId.pupillometry:
      return const CaptureProtocol(
        preparation:
            'Use steady indoor lighting. This is an uncalibrated proxy.',
        steps: <String>[
          'Hold the front camera at eye level.',
          'Keep the face still and eyes open.',
          'Avoid reflections on glasses if possible.',
        ],
        qualityTips: <String>[
          'Use the same lighting for repeated captures.',
          'Do not switch lights on or off during capture.',
        ],
      );
    case BiometricId.infraredRespiration:
    case BiometricId.ultrasonicRespiration:
      return const CaptureProtocol(
        preparation:
            'Most phones expose only near/far proximity, not raw distance.',
        steps: <String>[
          'If raw proximity is unavailable, this metric records a stub only.',
          'If raw proximity becomes available, hold the sensor near chest motion.',
        ],
        qualityTips: <String>[
          'Do not interpret a stub as a clinical measurement.',
        ],
      );
    case BiometricId.magneticBiomarkerAssay:
    case BiometricId.scleralBilirubin:
    case BiometricId.ocularImaging:
    case BiometricId.wound3dMorphometry:
    case BiometricId.gaitAnalysis:
    case BiometricId.radarCardiopulmonary:
    case BiometricId.dermatoglyphics:
    case BiometricId.arterialStiffness:
    case BiometricId.pulseOximetry:
    case BiometricId.coreBodyTemperature:
      return const CaptureProtocol(
        preparation:
            'This metric is not implemented on commodity phone hardware yet.',
        steps: <String>[
          'The app records a stub instead of a biometric reading.',
        ],
        qualityTips: <String>[
          'Use an external validated device for this measurement.',
        ],
      );
  }
}
