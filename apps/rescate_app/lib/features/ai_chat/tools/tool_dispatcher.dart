// Executes the three Rescate tools.
//
// Tools that need UI (consent dialog, navigator) live in the app layer per
// CLAUDE.md's package-boundary rule. The dispatcher is injected into
// LlmService at boot via LlmService.attachToolRegistry.

import 'dart:async';

import 'package:ai_inference/ai_inference.dart';
import 'package:biometric_estimators/biometric_estimators.dart';
import 'package:bluetooth_mesh/bluetooth_mesh.dart';
import 'package:flutter/material.dart';
import 'package:offline_data/offline_data.dart';
import 'package:sensor_availability/sensor_availability.dart';

import '../../../core/theme/app_colors.dart';

/// Signal raised by [_showCprTutorial]. Read and drained by [LlmState] when
/// finalizing the assistant message so the chat screen can render an inline
/// "Open CPR Tutorial" button below the bubble.
class PendingInlineWidget {
  const PendingInlineWidget(this.type);
  final InlineWidgetSignal type;
}

enum InlineWidgetSignal { cprTutorialButton }

class RescateToolDispatcher {
  RescateToolDispatcher({
    required this.navKey,
    required this.measurementStore,
  });

  final GlobalKey<NavigatorState> navKey;
  final MeasurementStore measurementStore;

  /// Drained by LlmState after each turn — see PendingInlineWidget docs.
  final List<PendingInlineWidget> pendingInlineWidgets =
      <PendingInlineWidget>[];

  /// Maps the model-facing metric name to the BiometricId we'll capture.
  static const Map<String, BiometricId> _metricToId = <String, BiometricId>{
    'heart_rate': BiometricId.ppgCardiovascular,
    'respiration': BiometricId.acousticRespiration,
    'spo2': BiometricId.pulseOximetry,
    'temperature': BiometricId.coreBodyTemperature,
    'pupillometry': BiometricId.pupillometry,
  };

  Future<Map<String, Object?>> dispatch(ToolCall call) async {
    switch (call.name) {
      case 'get_biometric':
        final metric = call.args['metric'] as String?;
        if (metric == null) {
          return <String, Object?>{'error': 'missing_metric'};
        }
        return _getBiometric(metric);
      case 'request_help_nearby':
        final summary = (call.args['case_summary'] as String?) ?? '';
        final urgency = (call.args['urgency'] as String?) ?? 'urgent';
        return _requestHelpNearby(summary, urgency);
      case 'show_cpr_tutorial':
        return _showCprTutorial();
      default:
        return <String, Object?>{'error': 'unknown_tool', 'name': call.name};
    }
  }

  // ── get_biometric ──────────────────────────────────────────────────────────

  Future<Map<String, Object?>> _getBiometric(String metric) async {
    final id = _metricToId[metric];
    if (id == null) {
      return <String, Object?>{'available': false, 'reason': 'unknown_metric'};
    }
    final estimator = BiometricEstimatorRegistry.instance.forId(id);
    final ctx = navKey.currentContext;
    if (ctx == null) {
      return <String, Object?>{'error': 'no_navigator'};
    }
    // StubEstimator (used for hardware-unsupported metrics like spo2 /
    // temperature on commodity phones) returns false from isSupportedBy.
    if (!estimator.isSupportedBy(SensorAvailabilityService.instance)) {
      return <String, Object?>{'available': false, 'metric': metric};
    }

    final consented = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Take a measurement?'),
        content: Text(
          'The AI wants to read your ${_humanMetric(metric)} to give better advice. '
          'This will take about ${estimator.suggestedDuration.inSeconds}s. Proceed?',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('No'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryRed,
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );

    if (consented != true) {
      return <String, Object?>{'declined': true, 'metric': metric};
    }

    final session = CaptureSession();
    final progressNotifier = ValueNotifier<double>(0);
    final progressSub = session.progress.listen((v) {
      progressNotifier.value = v;
    });

    // Non-blocking progress sheet — closed in finally.
    final progressCtx = navKey.currentContext;
    // ignore: use_build_context_synchronously
    if (progressCtx != null && progressCtx.mounted) {
      unawaited(showModalBottomSheet<void>(
        // ignore: use_build_context_synchronously
        context: progressCtx,
        isDismissible: false,
        enableDrag: false,
        builder: (sheetCtx) => _CaptureProgressSheet(
          metric: metric,
          progress: progressNotifier,
          onCancel: () {
            session.cancel();
            Navigator.of(sheetCtx).pop();
          },
        ),
      ));
    }

    try {
      final measurement = await estimator
          .capture(session)
          .timeout(const Duration(seconds: 30));
      if (measurement.status == MeasurementStatus.failed) {
        return <String, Object?>{'error': 'capture_failed', 'metric': metric};
      }
      await measurementStore.insert(measurement);
      final primary = measurement.primary;
      return <String, Object?>{
        'metric': metric,
        'value': primary?.value,
        'unit': primary?.unit,
        'confidence':
            double.parse(measurement.confidence.toStringAsFixed(2)),
        'captured_at': measurement.capturedAt.toIso8601String(),
      };
    } on TimeoutException {
      session.cancel();
      return <String, Object?>{'error': 'timeout', 'metric': metric};
    } catch (e) {
      return <String, Object?>{'error': 'capture_failed', 'detail': e.toString()};
    } finally {
      await progressSub.cancel();
      await session.close();
      progressNotifier.dispose();
      final dismissCtx = navKey.currentContext;
      // ignore: use_build_context_synchronously
      if (dismissCtx != null && dismissCtx.mounted) {
        // ignore: use_build_context_synchronously
        final nav = Navigator.of(dismissCtx);
        if (nav.canPop()) nav.pop();
      }
    }
  }

  String _humanMetric(String metric) {
    switch (metric) {
      case 'heart_rate':
        return 'heart rate';
      case 'spo2':
        return 'blood-oxygen level';
      case 'temperature':
        return 'temperature';
      case 'respiration':
        return 'breathing rate';
      case 'pupillometry':
        return 'pupil response';
      default:
        return metric;
    }
  }

  // ── request_help_nearby ────────────────────────────────────────────────────

  Future<Map<String, Object?>> _requestHelpNearby(
    String summary,
    String urgency,
  ) async {
    // CLAUDE.md: mesh packets must stay under 100 bytes. The framing
    // "[Rescate Help · urgency=critical] " is ~33 chars, leaving 67 for
    // summary; truncate to 70 to keep total close to (or under) 100.
    final cleanSummary = summary.replaceAll('\n', ' ').trim();
    final truncated = cleanSummary.length > 70
        ? '${cleanSummary.substring(0, 67)}...'
        : cleanSummary;
    final body = '[Rescate Help · $urgency] $truncated';

    final svc = NearbyService();
    final peers = svc.connectedDevices.keys.toList(growable: false);
    if (peers.isEmpty) {
      return <String, Object?>{'peers_messaged': 0};
    }
    for (final id in peers) {
      await svc.sendMessage(id, body);
    }
    return <String, Object?>{
      'peers_messaged': peers.length,
      'urgency': urgency,
    };
  }

  // ── show_cpr_tutorial ──────────────────────────────────────────────────────

  Future<Map<String, Object?>> _showCprTutorial() async {
    pendingInlineWidgets
        .add(const PendingInlineWidget(InlineWidgetSignal.cprTutorialButton));
    return <String, Object?>{'acknowledged': true};
  }
}

// ── Progress sheet ─────────────────────────────────────────────────────────

class _CaptureProgressSheet extends StatelessWidget {
  const _CaptureProgressSheet({
    required this.metric,
    required this.progress,
    required this.onCancel,
  });

  final String metric;
  final ValueNotifier<double> progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Measuring ${_describe(metric)}…',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            ValueListenableBuilder<double>(
              valueListenable: progress,
              builder: (_, v, __) => LinearProgressIndicator(
                value: v.clamp(0.0, 1.0),
                color: AppColors.primaryRed,
              ),
            ),
            const SizedBox(height: 16),
            TextButton(onPressed: onCancel, child: const Text('Cancel')),
          ],
        ),
      ),
    );
  }

  static String _describe(String metric) {
    switch (metric) {
      case 'heart_rate':
        return 'heart rate';
      case 'respiration':
        return 'breathing rate';
      case 'spo2':
        return 'blood-oxygen';
      case 'temperature':
        return 'temperature';
      case 'pupillometry':
        return 'pupil response';
      default:
        return metric;
    }
  }
}
