// packages/ai_inference/lib/src/llm_load_diagnostics.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Result of a cheap pre-flight check on a GGUF file. All fields are populated
/// even on failure so the caller can log a complete picture.
class GgufFileCheck {
  const GgufFileCheck({
    required this.exists,
    required this.sizeBytes,
    required this.magicOk,
    this.error,
  });

  final bool exists;
  final int sizeBytes;
  final bool magicOk;
  final String? error;

  bool get isValid => exists && magicOk && error == null;

  @override
  String toString() =>
      'GgufFileCheck(exists=$exists, sizeBytes=$sizeBytes, magicOk=$magicOk, error=$error)';
}

/// Sticky marker written to disk *before* every native load attempt and cleared
/// after success. If the marker is still present on the next launch, the last
/// load attempt died (typically SIGSEGV inside libllama / libggml during
/// tensor allocation) and the loader must skip that rung.
@immutable
class LoadAttempt {
  const LoadAttempt({
    required this.rung,
    required this.modelPath,
    required this.timestampMs,
    this.note,
    this.backend,
  });

  final int rung;
  final String modelPath;
  final int timestampMs;
  final String? note;

  /// Name of the GpuBackend used by this attempt (e.g. `'vulkan'`, `'cpu'`).
  /// `null` for markers written by older builds.
  final String? backend;

  /// The rung the loader should start from after a crash on this attempt.
  /// Default is one past the crashed rung. When the crashed attempt used a
  /// GPU backend, callers should additionally clamp the result up to the
  /// first CPU rung — observed crashes on Mali-G57 / MT6789 hit every Vulkan
  /// rung in the same allocator code path, so retrying any of them just
  /// burns another cold start.
  int get nextRungAfterCrash => rung + 1;

  /// `true` when this attempt used a non-CPU backend and therefore implies
  /// every other GPU rung should also be skipped on the next launch.
  bool get crashedOnGpuBackend {
    final String? b = backend;
    if (b == null) return false;
    return b != 'cpu';
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'rung': rung,
        'modelPath': modelPath,
        'timestampMs': timestampMs,
        if (note != null) 'note': note,
        if (backend != null) 'backend': backend,
      };

  static LoadAttempt? fromJson(Map<String, Object?> json) {
    final int? rung = (json['rung'] as num?)?.toInt();
    final String? modelPath = json['modelPath'] as String?;
    final int? timestampMs = (json['timestampMs'] as num?)?.toInt();
    if (rung == null || modelPath == null || timestampMs == null) return null;
    return LoadAttempt(
      rung: rung,
      modelPath: modelPath,
      timestampMs: timestampMs,
      note: json['note'] as String?,
      backend: json['backend'] as String?,
    );
  }

  @override
  String toString() =>
      'LoadAttempt(rung=$rung, path=$modelPath, ts=$timestampMs, backend=$backend, note=$note)';
}

/// On-disk diagnostics for the LLM model load.
///
/// All operations are best-effort and never throw — diagnostics must not be
/// the thing that breaks the loader. The log file is rolled at ~256 KB.
///
/// File layout (all under `<appDocs>/ai_chat/`):
/// - `logs/llm_load.log`        — current rolling log
/// - `logs/llm_load.log.1`      — previous roll
/// - `llm_load_attempt.json`    — sticky marker for crash-loop fallback
class LlmLoadDiagnostics {
  const LlmLoadDiagnostics._();

  static const int _maxLogBytes = 256 * 1024;
  static const String _logRelDir = 'ai_chat/logs';
  static const String _logFileName = 'llm_load.log';
  static const String _attemptRelPath = 'ai_chat/llm_load_attempt.json';

  /// Free-RAM lookup channel. Matches the existing `dev.rescate/device_profile`
  /// channel; the Kotlin handler adds a `getFreeRam` method that returns
  /// `ActivityManager.MemoryInfo.availMem` in MiB.
  static const MethodChannel _channel = MethodChannel('dev.rescate/device_profile');

  // ── File-system helpers ────────────────────────────────────────────────────

  static Directory? _cachedRoot;

  static Future<Directory?> _appDocsDir() async {
    if (_cachedRoot != null) return _cachedRoot;
    try {
      _cachedRoot = await getApplicationDocumentsDirectory();
    } catch (_) {
      _cachedRoot = null;
    }
    return _cachedRoot;
  }

  /// Returns the absolute path of the current log file, creating parent dirs
  /// if needed. Returns `null` on host VM / failure.
  static Future<String?> logFilePath() async {
    final Directory? root = await _appDocsDir();
    if (root == null) return null;
    try {
      final Directory dir = Directory('${root.path}/$_logRelDir');
      if (!await dir.exists()) await dir.create(recursive: true);
      return '${dir.path}/$_logFileName';
    } catch (_) {
      return null;
    }
  }

  static Future<File?> _attemptFile() async {
    final Directory? root = await _appDocsDir();
    if (root == null) return null;
    try {
      final File file = File('${root.path}/$_attemptRelPath');
      final Directory parent = file.parent;
      if (!await parent.exists()) await parent.create(recursive: true);
      return file;
    } catch (_) {
      return null;
    }
  }

  // ── Logging ────────────────────────────────────────────────────────────────

  /// Appends a timestamped line to the log file, rolling when over the cap.
  /// Also forwards to [debugPrint] so console captures still see it.
  static Future<void> appendLog(String line) async {
    final String stamped = '${DateTime.now().toIso8601String()} $line';
    debugPrint('[LlmLoad] $stamped');
    final String? path = await logFilePath();
    if (path == null) return;
    try {
      final File file = File(path);
      if (await file.exists() && (await file.length()) > _maxLogBytes) {
        await _rotate(file);
      }
      await file.writeAsString('$stamped\n', mode: FileMode.append, flush: false);
    } catch (_) {
      // Never let logging break loading.
    }
  }

  static Future<void> _rotate(File current) async {
    try {
      final File rolled = File('${current.path}.1');
      if (await rolled.exists()) await rolled.delete();
      await current.rename(rolled.path);
    } catch (_) {}
  }

  /// Reads up to [maxBytes] tail of the current log file for sharing. Returns
  /// an empty string if the log is absent.
  static Future<String> readLogTail({int maxBytes = 32 * 1024}) async {
    final String? path = await logFilePath();
    if (path == null) return '';
    try {
      final File file = File(path);
      if (!await file.exists()) return '';
      final int len = await file.length();
      if (len <= maxBytes) return file.readAsString();
      final RandomAccessFile raf = await file.open();
      try {
        await raf.setPosition(len - maxBytes);
        final List<int> bytes = await raf.read(maxBytes);
        return utf8.decode(bytes, allowMalformed: true);
      } finally {
        await raf.close();
      }
    } catch (_) {
      return '';
    }
  }

  // ── GGUF preflight ─────────────────────────────────────────────────────────

  /// Cheap structural check: does the file exist, is it non-empty, does it
  /// begin with the magic bytes "GGUF"? Catches truncated downloads and
  /// SAF-virtual paths that exist in the FS view but don't actually
  /// resolve.
  static Future<GgufFileCheck> validateGgufFile(String path) async {
    if (path.isEmpty) {
      return const GgufFileCheck(
        exists: false,
        sizeBytes: 0,
        magicOk: false,
        error: 'empty path',
      );
    }
    final File file = File(path);
    bool exists;
    int size = 0;
    try {
      exists = await file.exists();
    } catch (e) {
      return GgufFileCheck(
        exists: false,
        sizeBytes: 0,
        magicOk: false,
        error: 'exists() threw: $e',
      );
    }
    if (!exists) {
      return const GgufFileCheck(
        exists: false,
        sizeBytes: 0,
        magicOk: false,
        error: 'file not found',
      );
    }
    try {
      size = await file.length();
    } catch (e) {
      return GgufFileCheck(
        exists: true,
        sizeBytes: 0,
        magicOk: false,
        error: 'length() threw: $e',
      );
    }
    if (size < 16) {
      return GgufFileCheck(
        exists: true,
        sizeBytes: size,
        magicOk: false,
        error: 'file too small ($size bytes)',
      );
    }
    try {
      final RandomAccessFile raf = await file.open();
      try {
        final List<int> head = await raf.read(4);
        final bool magicOk = head.length == 4 &&
            head[0] == 0x47 && // G
            head[1] == 0x47 && // G
            head[2] == 0x55 && // U
            head[3] == 0x46; // F
        return GgufFileCheck(
          exists: true,
          sizeBytes: size,
          magicOk: magicOk,
          error: magicOk ? null : 'bad magic bytes: $head',
        );
      } finally {
        await raf.close();
      }
    } catch (e) {
      return GgufFileCheck(
        exists: true,
        sizeBytes: size,
        magicOk: false,
        error: 'read() threw: $e',
      );
    }
  }

  // ── Free RAM ───────────────────────────────────────────────────────────────

  /// Fetches the current available RAM in MiB from the platform side. Returns
  /// `0` when the host can't report it (desktop tests, channel missing).
  static Future<int> readFreeRamMb() async {
    try {
      final Object? result = await _channel.invokeMethod<Object?>('getFreeRam');
      if (result is int) return result;
      if (result is num) return result.toInt();
      return 0;
    } catch (_) {
      return 0;
    }
  }

  // ── LoadAttempt persistence ────────────────────────────────────────────────

  /// Reads the sticky load-attempt marker if present.
  static Future<LoadAttempt?> readAttempt() async {
    final File? file = await _attemptFile();
    if (file == null) return null;
    try {
      if (!await file.exists()) return null;
      final String contents = await file.readAsString();
      if (contents.isEmpty) return null;
      final Object? decoded = jsonDecode(contents);
      if (decoded is! Map<String, Object?>) return null;
      return LoadAttempt.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  /// Writes the sticky load-attempt marker. Called before each native load
  /// attempt so we can detect SIGSEGVs that killed the process mid-attempt.
  static Future<void> writeAttempt(LoadAttempt attempt) async {
    final File? file = await _attemptFile();
    if (file == null) return;
    try {
      await file.writeAsString(jsonEncode(attempt.toJson()), flush: true);
    } catch (_) {}
  }

  /// Clears the sticky load-attempt marker. Called after a successful load.
  static Future<void> clearAttempt() async {
    final File? file = await _attemptFile();
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
