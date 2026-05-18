// apps/rescate_app/lib/core/providers/demo_state.dart
//
// Frontend-only demo/mock state.  No backend or package changes needed.

import 'dart:math';

import 'package:flutter/foundation.dart';

/// A single mock vital reading for UI testing without real sensors.
class MockVitalReading {
  MockVitalReading({
    required this.name,
    required this.value,
    required this.unit,
    required this.confidence,
    required this.capturedAt,
    this.category = 'General',
  });

  final String name;
  final String category;
  final double value;
  final String unit;
  final double confidence;
  final DateTime capturedAt;

  String get formattedValue => value.toStringAsFixed(1);
  String get summary => '$name: $formattedValue $unit';
}

/// Global demo-mode state.  Singleton so every screen can check [isDemoMode].
class DemoState extends ChangeNotifier {
  DemoState._();
  static final DemoState instance = DemoState._();

  bool _enabled = true; // start in demo mode for easy testing
  bool get isDemoMode => _enabled;

  final List<MockVitalReading> _readings = [];
  List<MockVitalReading> get readings => List.unmodifiable(_readings);

  void toggle() {
    _enabled = !_enabled;
    notifyListeners();
  }

  void setEnabled(bool v) {
    if (_enabled != v) {
      _enabled = v;
      notifyListeners();
    }
  }

  // ── Mock vital readings ───────────────────────────────────────────────────

  void generateMockReadings() {
    final r = Random();
    final now = DateTime.now();
    _readings.insertAll(0, [
      MockVitalReading(
        name: 'Heart Rate',
        category: 'Cardiovascular',
        value: 68 + r.nextDouble() * 22,
        unit: 'bpm',
        confidence: .85 + r.nextDouble() * .15,
        capturedAt: now.subtract(Duration(minutes: r.nextInt(20))),
      ),
      MockVitalReading(
        name: 'Blood Pressure (Sys)',
        category: 'Cardiovascular',
        value: 110 + r.nextDouble() * 30,
        unit: 'mmHg',
        confidence: .78 + r.nextDouble() * .15,
        capturedAt: now.subtract(Duration(minutes: r.nextInt(20))),
      ),
      MockVitalReading(
        name: 'Blood Pressure (Dia)',
        category: 'Cardiovascular',
        value: 65 + r.nextDouble() * 20,
        unit: 'mmHg',
        confidence: .78 + r.nextDouble() * .15,
        capturedAt: now.subtract(Duration(minutes: r.nextInt(20))),
      ),
      MockVitalReading(
        name: 'SpO₂',
        category: 'Respiratory',
        value: 95 + r.nextDouble() * 4,
        unit: '%',
        confidence: .90 + r.nextDouble() * .10,
        capturedAt: now.subtract(Duration(minutes: r.nextInt(20))),
      ),
      MockVitalReading(
        name: 'Respiratory Rate',
        category: 'Respiratory',
        value: 14 + r.nextDouble() * 6,
        unit: 'breaths/min',
        confidence: .82 + r.nextDouble() * .12,
        capturedAt: now.subtract(Duration(minutes: r.nextInt(20))),
      ),
      MockVitalReading(
        name: 'Body Temperature',
        category: 'General',
        value: 36.2 + r.nextDouble() * 1.3,
        unit: '°C',
        confidence: .88 + r.nextDouble() * .12,
        capturedAt: now.subtract(Duration(minutes: r.nextInt(20))),
      ),
      MockVitalReading(
        name: 'Stress Index',
        category: 'Neurological',
        value: 20 + r.nextDouble() * 50,
        unit: 'units',
        confidence: .70 + r.nextDouble() * .20,
        capturedAt: now.subtract(Duration(minutes: r.nextInt(20))),
      ),
    ]);
    notifyListeners();
  }

  void clearReadings() {
    _readings.clear();
    notifyListeners();
  }

  /// Formats selected (or all) readings into a chat-friendly string.
  String formatReadingsForChat([List<MockVitalReading>? subset]) {
    final list = subset ?? _readings;
    if (list.isEmpty) return '';
    final buf = StringBuffer('📊 My Recent Vitals:\n');
    for (final m in list.take(7)) {
      buf.writeln(
        '• ${m.name}: ${m.formattedValue} ${m.unit} '
        '(${(m.confidence * 100).toInt()}% conf.)',
      );
    }
    return buf.toString().trim();
  }

  // ── Mock AI responses ─────────────────────────────────────────────────────

  static const _responses = [
    "Based on the vital signs you've shared, your readings appear to be within normal ranges. Your heart rate is well within the healthy range of 60-100 bpm. I recommend continuing regular monitoring.\n\nHere are a few tips:\n• Stay hydrated throughout the day\n• Aim for 7-8 hours of sleep\n• Continue moderate exercise",
    "Looking at your recent measurements, your SpO₂ levels are good — above 95% indicates healthy oxygen saturation. Combined with your respiratory rate, this suggests stable pulmonary function.\n\nIf you experience any shortness of breath or persistent cough, please consult a healthcare professional immediately.",
    "Your blood pressure reading falls within the normal-to-prehypertension range. While this isn't immediately concerning, here's what I recommend:\n\n• Reduce sodium intake to under 2,300mg/day\n• Increase potassium-rich foods (bananas, spinach)\n• Monitor BP at the same time each day for consistency",
    "Your body temperature is within the normal range (36.1°C – 37.2°C). Combined with your other stable vitals, this indicates your body is maintaining good homeostasis.\n\nRemember: body temperature naturally fluctuates throughout the day, being lowest in the morning and highest in the late afternoon.",
    "I've analyzed your vital signs collectively. Everything looks stable! Your cardiovascular metrics (heart rate, blood pressure) and respiratory metrics (SpO₂, respiratory rate) are all within expected ranges.\n\nFor a more comprehensive assessment, I'd recommend scheduling a routine check-up with your healthcare provider.",
  ];

  static const _voiceResponses = [
    "Your vitals look good. Heart rate and blood pressure are within normal limits. Keep up the regular monitoring!",
    "Everything appears stable. Your oxygen saturation is healthy and your respiratory rate is normal. Stay active and hydrated.",
    "Based on your readings, I'd say you're in good shape. Just remember to take your measurements at consistent times for the best tracking.",
    "Your recent vitals show a healthy pattern. No immediate concerns. Would you like me to explain any specific reading in more detail?",
    "All your vital signs are within the expected ranges. Great job staying on top of your health monitoring!",
  ];

  String getRandomResponse() =>
      _responses[Random().nextInt(_responses.length)];

  String getRandomVoiceResponse() =>
      _voiceResponses[Random().nextInt(_voiceResponses.length)];
}
