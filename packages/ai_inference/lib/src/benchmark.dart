/// Fixed, repeatable prompts and the JSON shape used for device benchmarks.
///
/// The prompts intentionally cover the emergency-answer path without relying
/// on a particular model's wording. A device run should execute each case
/// once as warm-up, then several measured times, exporting the profiler report
/// after every measured turn.
class LlmBenchmarkCase {
  const LlmBenchmarkCase({
    required this.id,
    required this.prompt,
    required this.isArabic,
  });

  final String id;
  final String prompt;
  final bool isArabic;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'prompt': prompt,
        'isArabic': isArabic,
      };
}

/// Stable prompt set used for comparisons between optimization commits.
const List<LlmBenchmarkCase> fixedLlmBenchmarkCases = <LlmBenchmarkCase>[
  LlmBenchmarkCase(
    id: 'burn',
    prompt: 'A person has a severe burn. What should I do in the first five '
        'minutes?',
    isArabic: false,
  ),
  LlmBenchmarkCase(
    id: 'unconscious_breathing',
    prompt: 'Someone is unconscious but breathing normally. What position '
        'and checks should I use?',
    isArabic: false,
  ),
  LlmBenchmarkCase(
    id: 'bleach_ingestion',
    prompt: 'A child may have swallowed bleach. What immediate steps are safe '
        'and what must I avoid?',
    isArabic: false,
  ),
  LlmBenchmarkCase(
    id: 'arabic_burn',
    prompt: 'شخص لديه حرق شديد. ماذا أفعل في الدقائق الخمس الأولى؟',
    isArabic: true,
  ),
];

/// One measured turn extracted from a profiler trace.
class LlmBenchmarkMeasurement {
  const LlmBenchmarkMeasurement({
    required this.caseId,
    required this.totalMs,
    this.timeToFirstTokenMs,
    this.backend,
    this.gpuLayers,
    this.cpuVariant,
    this.threads,
    this.threadsBatch,
    this.batchSize,
    this.microBatchSize,
    this.promptTokens,
    this.promptEvalMs,
    this.decodeTokens,
    this.decodeMs,
    this.promptTokensPerSecond,
    this.decodeTokensPerSecond,
  });

  final String caseId;
  final int totalMs;
  final int? timeToFirstTokenMs;
  final String? backend;
  final int? gpuLayers;
  final String? cpuVariant;
  final int? threads;
  final int? threadsBatch;
  final int? batchSize;
  final int? microBatchSize;
  final int? promptTokens;
  final int? promptEvalMs;
  final int? decodeTokens;
  final int? decodeMs;
  final int? promptTokensPerSecond;
  final int? decodeTokensPerSecond;

  Map<String, Object?> toJson() => <String, Object?>{
        'caseId': caseId,
        'totalMs': totalMs,
        if (timeToFirstTokenMs != null)
          'timeToFirstTokenMs': timeToFirstTokenMs,
        if (backend != null) 'backend': backend,
        if (gpuLayers != null) 'gpuLayers': gpuLayers,
        if (cpuVariant != null) 'cpuVariant': cpuVariant,
        if (threads != null) 'threads': threads,
        if (threadsBatch != null) 'threadsBatch': threadsBatch,
        if (batchSize != null) 'batchSize': batchSize,
        if (microBatchSize != null) 'microBatchSize': microBatchSize,
        if (promptTokens != null) 'promptTokens': promptTokens,
        if (promptEvalMs != null) 'promptEvalMs': promptEvalMs,
        if (decodeTokens != null) 'decodeTokens': decodeTokens,
        if (decodeMs != null) 'decodeMs': decodeMs,
        if (promptTokensPerSecond != null)
          'promptTokensPerSecond': promptTokensPerSecond,
        if (decodeTokensPerSecond != null)
          'decodeTokensPerSecond': decodeTokensPerSecond,
      };

  /// Parses the stable subset of an `llm.turn` or `chat.turn` trace.
  factory LlmBenchmarkMeasurement.fromTrace(
    Map<String, Object?> trace, {
    required String caseId,
  }) {
    final native = _asMap(trace['data'])?['native'];
    final nativeData = _asMap(native);
    final runtime = _asMap(trace['data'])?['runtime'];
    final runtimeData = _asMap(runtime);
    final decode = _findStep(trace['steps'], 'llm.decode');
    final decodeData = _asMap(decode?['data']);
    final totalMs = _asInt(trace['wall_ms']) ?? 0;
    final promptTokens = _asInt(nativeData?['prompt_eval_tokens']);
    final promptEvalMs = _asInt(nativeData?['prompt_eval_ms']);
    final decodeTokens = _asInt(nativeData?['eval_tokens']);
    final decodeMs = _asInt(nativeData?['eval_ms']);
    return LlmBenchmarkMeasurement(
      caseId: caseId,
      totalMs: totalMs,
      timeToFirstTokenMs: _asInt(decodeData?['ttft_ms']),
      backend: runtimeData?['backend'] as String?,
      gpuLayers: _asInt(runtimeData?['gpuLayers']),
      cpuVariant: runtimeData?['cpuVariant'] as String?,
      threads: _asInt(runtimeData?['threads']),
      threadsBatch: _asInt(runtimeData?['threadsBatch']),
      batchSize: _asInt(runtimeData?['batchSize']),
      microBatchSize: _asInt(runtimeData?['microBatchSize']),
      promptTokens: promptTokens,
      promptEvalMs: promptEvalMs,
      decodeTokens: decodeTokens,
      decodeMs: decodeMs,
      promptTokensPerSecond: _rate(promptTokens, promptEvalMs),
      decodeTokensPerSecond: _rate(decodeTokens, decodeMs),
    );
  }

  static Map<String, Object?>? _asMap(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return null;
  }

  static Map<String, Object?>? _findStep(Object? value, String name) {
    if (value is! List) return null;
    for (final item in value) {
      final step = _asMap(item);
      if (step?['name'] == name) return step;
      final nested = _findStep(step?['children'], name);
      if (nested != null) return nested;
    }
    return null;
  }

  static int? _rate(int? tokens, int? milliseconds) {
    if (tokens == null || milliseconds == null || milliseconds <= 0) {
      return null;
    }
    return (tokens * 1000 / milliseconds).round();
  }
}

/// Versioned report envelope for benchmark artifacts.
class LlmBenchmarkReport {
  const LlmBenchmarkReport({
    required this.capturedAt,
    required this.buildMode,
    required this.measurements,
    this.metadata = const <String, Object?>{},
  });

  static const int formatVersion = 1;

  final DateTime capturedAt;
  final String buildMode;
  final Map<String, Object?> metadata;
  final List<LlmBenchmarkMeasurement> measurements;

  Map<String, Object?> toJson() => <String, Object?>{
        'formatVersion': formatVersion,
        'capturedAt': capturedAt.toUtc().toIso8601String(),
        'buildMode': buildMode,
        'metadata': metadata,
        'fixedCases': fixedLlmBenchmarkCases.map((c) => c.toJson()).toList(),
        'measurements': measurements.map((m) => m.toJson()).toList(),
      };

  /// Converts the profiler snapshot into a compact benchmark artifact.
  ///
  /// Traces without a `benchmark_case` field receive deterministic IDs in
  /// encounter order (`turn-1`, `turn-2`, ...), which keeps ad-hoc device
  /// captures useful while the fixed runner can provide explicit IDs.
  factory LlmBenchmarkReport.fromProfilerSnapshot(
    Map<String, Object?> snapshot,
  ) {
    final session = LlmBenchmarkMeasurement._asMap(snapshot['session']);
    final traces = snapshot['traces'];
    final measurements = <LlmBenchmarkMeasurement>[];
    if (traces is List) {
      var index = 0;
      for (final rawTrace in traces) {
        final trace = LlmBenchmarkMeasurement._asMap(rawTrace);
        final traceName = trace?['name'];
        if (trace == null ||
            (traceName != 'llm.turn' && traceName != 'chat.turn')) {
          continue;
        }
        index++;
        final traceData = LlmBenchmarkMeasurement._asMap(trace['data']);
        final caseId = traceData?['benchmark_case'] as String? ?? 'turn-$index';
        measurements.add(
          LlmBenchmarkMeasurement.fromTrace(trace, caseId: caseId),
        );
      }
    }
    return LlmBenchmarkReport(
      capturedAt: DateTime.tryParse(session?['ended_at'] as String? ?? '') ??
          DateTime.now().toUtc(),
      buildMode: session?['build_mode'] as String? ?? 'unknown',
      metadata: <String, Object?>{
        'profilerEnabled': session?['profiler_enabled'],
      },
      measurements: measurements,
    );
  }
}
