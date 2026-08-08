import 'package:ai_inference/ai_inference.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fixed benchmark prompt set is stable and covers both languages', () {
    expect(fixedLlmBenchmarkCases, hasLength(4));
    expect(
      fixedLlmBenchmarkCases.map((item) => item.id).toSet(),
      hasLength(4),
    );
    expect(fixedLlmBenchmarkCases.any((item) => item.isArabic), isTrue);
    expect(fixedLlmBenchmarkCases.any((item) => !item.isArabic), isTrue);
  });

  test('measurement extracts runtime and native counters from a trace', () {
    final measurement = LlmBenchmarkMeasurement.fromTrace(
      <String, Object?>{
        'wall_ms': 207600,
        'data': <String, Object?>{
          'runtime': <String, Object?>{
            'backend': 'cpu',
            'gpuLayers': 0,
            'cpuVariant': 'android_armv8.6_1',
            'threads': 2,
            'threadsBatch': 6,
            'batchSize': 256,
            'microBatchSize': 128,
          },
          'native': <String, Object?>{
            'prompt_eval_ms': 153100,
            'prompt_eval_tokens': 701,
            'eval_ms': 53900,
            'eval_tokens': 95,
          },
        },
        'steps': <Object?>[
          <String, Object?>{
            'name': 'llm.decode',
            'data': <String, Object?>{'ttft_ms': 157800},
          },
        ],
      },
      caseId: 'burn',
    );

    expect(measurement.caseId, 'burn');
    expect(measurement.totalMs, 207600);
    expect(measurement.backend, 'cpu');
    expect(measurement.gpuLayers, 0);
    expect(measurement.cpuVariant, 'android_armv8.6_1');
    expect(measurement.threads, 2);
    expect(measurement.threadsBatch, 6);
    expect(measurement.batchSize, 256);
    expect(measurement.microBatchSize, 128);
    expect(measurement.promptTokens, 701);
    expect(measurement.promptTokensPerSecond, 5);
    expect(measurement.decodeTokensPerSecond, 2);
    expect(measurement.timeToFirstTokenMs, 157800);
  });

  test('report converts llm.turn traces and preserves schema fields', () {
    final report = LlmBenchmarkReport.fromProfilerSnapshot(
      <String, Object?>{
        'session': <String, Object?>{
          'ended_at': '2026-08-08T00:00:00.000Z',
          'build_mode': 'profile',
          'profiler_enabled': true,
        },
        'traces': <Object?>[
          <String, Object?>{
            'name': 'chat.turn',
            'wall_ms': 10,
            'data': <String, Object?>{'benchmark_case': 'burn'},
            'steps': <Object?>[],
          },
          <String, Object?>{
            'name': 'other',
            'wall_ms': 20,
          },
        ],
      },
    );

    expect(report.buildMode, 'profile');
    expect(report.measurements, hasLength(1));
    final json = report.toJson();
    expect(json['formatVersion'], LlmBenchmarkReport.formatVersion);
    expect(json['fixedCases'], hasLength(4));
    expect(json['measurements'], hasLength(1));
  });
}
