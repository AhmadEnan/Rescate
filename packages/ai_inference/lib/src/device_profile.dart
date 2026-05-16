// packages/ai_inference/lib/src/device_profile.dart

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';

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

  /// llama.cpp `n_threads` for decode.
  final int recommendedThreads;

  /// llama.cpp `n_threads_batch` for prompt processing.
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
    final int recommendedThreads = math.max(2, math.min(cores - 1, 6));

    int totalRamMb = 0;
    int availRamMb = 0;
    bool platformLowRam = false;
    String socModel = '';

    try {
      final Map<Object?, Object?>? info =
          await _channel.invokeMapMethod<Object?, Object?>('getInfo');
      if (info != null) {
        totalRamMb = _asInt(info['totalRamMb']);
        availRamMb = _asInt(info['availRamMb']);
        platformLowRam = info['isLowRamDevice'] == true;
        final Object? soc = info['socModel'];
        if (soc is String) socModel = soc;
      }
    } catch (_) {
      // Channel missing or method failed — keep safe defaults.
    }

    final bool isLowRam =
        platformLowRam || (totalRamMb > 0 && totalRamMb < 4096);

    final int contextSize = isLowRam ? 2048 : 4096;
    final String cacheType = isLowRam ? 'q8_0' : 'f16';

    return DeviceProfile(
      cores: cores,
      recommendedThreads: recommendedThreads,
      recommendedBatchThreads: recommendedThreads,
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
    final int threads = math.max(2, math.min(cores - 1, 6));
    return DeviceProfile(
      cores: cores,
      recommendedThreads: threads,
      recommendedBatchThreads: threads,
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

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}
