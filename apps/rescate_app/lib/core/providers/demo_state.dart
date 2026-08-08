// apps/rescate_app/lib/core/providers/demo_state.dart
//
// Frontend-only demo/mock state.  No backend or package changes needed.

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

  // Demo/mock data is intentionally disabled in the production app. Keeping
  // the state object preserves the vitals attachment API without allowing a
  // fake reading or response to masquerade as a real measurement.
  bool get isDemoMode => false;

  final List<MockVitalReading> _readings = [];
  List<MockVitalReading> get readings => List.unmodifiable(_readings);

  void toggle() {
    // Demo mode is not available in production.
  }

  void setEnabled(bool _) {
    // Demo mode is not available in production.
  }

  // ── Mock vital readings ───────────────────────────────────────────────────

  void generateMockReadings() {
    // Intentionally unavailable in production builds.
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
}
