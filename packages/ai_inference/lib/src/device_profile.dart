// packages/ai_inference/lib/src/device_profile.dart

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:dev_profiler/dev_profiler.dart';

/// Per-device hardware/runtime profile used to derive llama.cpp parameters
/// at runtime.
///
/// Use [DeviceProfile.detect] in app startup to populate
/// `LlmDefaults.activeProfile`. On any failure (host VM, iOS without the
/// channel, missing platform implementation) [detect] returns
/// [DeviceProfile.fallback] instead of throwing.
class DeviceProfile {
  const DeviceProfile({
    required this.cores,
    required this.bigCores,
    required this.recommendedThreads,
    required this.recommendedBatchThreads,
    required this.totalRamMb,
    required this.availRamMb,
    required this.isLowRam,
    required this.recommendedGpuLayers,
    required this.recommendedContextSize,
    required this.recommendedBatchSize,
    required this.recommendedMicroBatchSize,
    required this.cacheTypeK,
    required this.cacheTypeV,
    required this.socModel,
  });

  /// Number of logical CPU cores reported by the Dart VM.
  final int cores;

  /// Number of "big" CPU cores detected by reading
  /// `/sys/devices/system/cpu/cpuN/cpufreq/cpuinfo_max_freq` on Android (via
  /// the `dev.rescate/device_profile` MethodChannel). `0` when the channel
  /// is missing or sysfs reads fail (host VM, iOS, web). Big.LITTLE ARM SoCs
  /// only produce good llama.cpp decode throughput when threads are pinned
  /// to big cores; scheduling decode threads onto LITTLE cores causes cache
  /// thrash and often makes decode slower than single-threaded.
  final int bigCores;

  /// llama.cpp `n_threads` for decode (token generation).
  final int recommendedThreads;

  /// llama.cpp `n_threads_batch` for prompt processing (prefill).
  /// Prompt eval is highly parallel and benefits from more threads than decode,
  /// even when some are LITTLE cores on big.LITTLE SoCs.
  final int recommendedBatchThreads;

  /// Total device RAM in MiB. `0` when unknown.
  final int totalRamMb;

  /// Available device RAM in MiB at detection time. `0` when unknown.
  final int availRamMb;

  /// `true` when the device is RAM-constrained (< 4 GB total).
  final bool isLowRam;

  /// Number of model layers to offload to GPU. `999` means "all".
  final int recommendedGpuLayers;

  /// llama.cpp `n_ctx`.
  final int recommendedContextSize;

  /// llama.cpp `n_batch`.
  final int recommendedBatchSize;

  /// llama.cpp `n_ubatch`.
  final int recommendedMicroBatchSize;

  /// KV cache K type, `'f16'` or `'q8_0'`.
  final String cacheTypeK;

  /// KV cache V type, `'f16'` or `'q8_0'`.
  final String cacheTypeV;

  /// `Build.SOC_MODEL` from Android (API 31+). Empty when unavailable.
  final String socModel;

  static const MethodChannel _channel =
      MethodChannel('dev.rescate/device_profile');

  /// Detects the device profile. Never throws; falls back to safe defaults.
  static Future<DeviceProfile> detect() async {
    final int cores = Platform.numberOfProcessors;

    int totalRamMb = 0;
    int availRamMb = 0;
    bool platformLowRam = false;
    String socModel = '';
    int bigCores = 0;

    try {
      final Map<Object?, Object?>? info =
          await _channel.invokeMapMethod<Object?, Object?>('getInfo');
      if (info != null) {
        totalRamMb = _asInt(info['totalRamMb']);
        availRamMb = _asInt(info['availRamMb']);
        platformLowRam = info['isLowRamDevice'] == true;
        final Object? soc = info['socModel'];
        if (soc is String) socModel = soc;
        bigCores = _asInt(info['bigCoreCount']);
      }
    } catch (_) {
      // Channel missing or method failed — keep safe defaults.
    }

    final bool isLowRam =
        platformLowRam || (totalRamMb > 0 && totalRamMb < 4096);

    final int contextSize = isLowRam ? 2048 : 4096;
    final String cacheType = isLowRam ? 'q8_0' : 'f16';

    // Thread count: prefer big-core count on big.LITTLE ARM (capped 1-4).
    // Falling back to the legacy `min(cores-1, 6)` heuristic when big-core
    // detection returned 0 (host VM, iOS, channel missing). The legacy
    // heuristic overcounts threads on modern 8-core ARM (4 LITTLE + 4 big)
    // and ends up scheduling decode work onto LITTLE cores, which measurably
    // slows llama.cpp decode vs using only the 4 big cores.
    final int recommendedThreads = _resolveThreads(cores, bigCores);

    // Emit a one-shot device event so future profiler reports contain the
    // resolved hardware context — useful for diagnosing per-device
    // regressions without re-deploying a debug build.
    Profiler.event(
      'llm.device',
      data: <String, Object?>{
        'cores': cores,
        'bigCores': bigCores,
        'recommendedThreads': recommendedThreads,
        'recommendedBatchThreads': _resolveBatchThreads(cores),
        'totalRamMb': totalRamMb,
        'availRamMb': availRamMb,
        'isLowRam': isLowRam,
        'socModel': socModel,
        'contextSize': contextSize,
      },
    );

    // Batch threads (prefill) are resolved separately from decode threads.
    //
    // Decode is memory-bandwidth bound and gets no benefit from LITTLE cores —
    // it stays pinned to big cores via [_resolveThreads]. Prefill is a batched
    // matmul that is compute bound and scales across ALL cores, LITTLE
    // included. Tying the two together (the previous behaviour) capped prefill
    // at 2 threads on this 2-big/6-LITTLE SoC and left 6 cores idle through
    // the single most expensive phase of a turn.
    final int recommendedBatchThreads = _resolveBatchThreads(cores);

    return DeviceProfile(
      cores: cores,
      bigCores: bigCores,
      recommendedThreads: recommendedThreads,
      recommendedBatchThreads: recommendedBatchThreads,
      totalRamMb: totalRamMb,
      availRamMb: availRamMb,
      isLowRam: isLowRam,
      recommendedGpuLayers: 999,
      recommendedContextSize: contextSize,
      recommendedBatchSize: 256,
      recommendedMicroBatchSize: 128,
      cacheTypeK: cacheType,
      cacheTypeV: cacheType,
      socModel: socModel,
    );
  }

  /// Conservative fallback used when detection cannot run (host VM, web).
  static DeviceProfile get fallback {
    final int cores = math.max(2, Platform.numberOfProcessors);
    final int threads = _resolveThreads(cores, 0);
    return DeviceProfile(
      cores: cores,
      bigCores: 0,
      recommendedThreads: threads,
      recommendedBatchThreads: _resolveBatchThreads(cores),
      totalRamMb: 0,
      availRamMb: 0,
      isLowRam: false,
      recommendedGpuLayers: 999,
      recommendedContextSize: 2048,
      recommendedBatchSize: 256,
      recommendedMicroBatchSize: 128,
      cacheTypeK: 'f16',
      cacheTypeV: 'f16',
      socModel: '',
    );
  }

  /// JSON-friendly snapshot of the profile.
  Map<String, Object?> toJson() => <String, Object?>{
        'cores': cores,
        'bigCores': bigCores,
        'recommendedThreads': recommendedThreads,
        'recommendedBatchThreads': recommendedBatchThreads,
        'totalRamMb': totalRamMb,
        'availRamMb': availRamMb,
        'isLowRam': isLowRam,
        'recommendedGpuLayers': recommendedGpuLayers,
        'recommendedContextSize': recommendedContextSize,
        'recommendedBatchSize': recommendedBatchSize,
        'recommendedMicroBatchSize': recommendedMicroBatchSize,
        'cacheTypeK': cacheTypeK,
        'cacheTypeV': cacheTypeV,
        'socModel': socModel,
      };

  /// Threads for prompt processing (`n_threads_batch`).
  ///
  /// Unlike decode, prefill is compute bound and scales across LITTLE cores
  /// too, so this deliberately does NOT restrict itself to big cores. One core
  /// is left for the UI isolate and platform work; capped at 6 to avoid
  /// oversubscription on high-core-count SoCs.
  static int _resolveBatchThreads(int cores) {
    return math.max(2, math.min(cores - 1, 6));
  }

  static int _resolveThreads(int cores, int bigCores) {
    if (bigCores > 0) {
      // Use only big cores, capped 1-4. Capping at 4 avoids oversubscription
      // even on hypothetical 5+ big-core SoCs (snapdragon 8 gen 4 has 2P+6E
      // — only 2 "big"). When more than 4 big cores are detected, llama.cpp's
      // allocator already handles pinning.
      return bigCores.clamp(1, 4);
    }
    // Legacy fallback: at least 2 threads, no more than cores-1, capped at 6.
    return math.max(2, math.min(cores - 1, 6));
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}
