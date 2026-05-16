// packages/ai_inference/lib/src/kv_cache_store.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// On-disk store for llama.cpp KV-cache state files saved via
/// [LlamaEngine.stateSaveFile]. Files are keyed by a hash of
/// `(modelPath | modelSize | isArabic | prompt)` so prompt edits or
/// model swaps invalidate the cache automatically.
///
/// All methods log via [debugPrint] and swallow filesystem errors —
/// the KV cache is a best-effort accelerator, never a correctness
/// requirement.
class KvCacheStore {
  KvCacheStore._();

  /// Singleton instance.
  static final KvCacheStore instance = KvCacheStore._();

  static const String _kSubdir = 'llm_kv';
  static const String _kExtension = '.kv';

  Directory? _cachedDir;

  Future<Directory> _dir() async {
    final cached = _cachedDir;
    if (cached != null) return cached;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$_kSubdir');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cachedDir = dir;
    return dir;
  }

  /// Computes a stable key. Uses SHA-256 of
  /// `modelPath|modelSize|isArabic|prompt` truncated to 16 hex chars.
  Future<String> keyFor({
    required String modelPath,
    required bool isArabic,
    required String promptText,
  }) async {
    int size = 0;
    try {
      final f = File(modelPath);
      if (await f.exists()) {
        size = await f.length();
      }
    } catch (e) {
      debugPrint('[KvCache] keyFor stat failed: $e');
    }
    final input = '$modelPath|$size|$isArabic|$promptText';
    final digest = sha256.convert(utf8.encode(input));
    return digest.toString().substring(0, 16);
  }

  /// Returns the cache file if it exists, else null.
  Future<File?> findCached(String key) async {
    try {
      final dir = await _dir();
      final f = File('${dir.path}/$key$_kExtension');
      if (await f.exists()) {
        final len = await f.length();
        debugPrint('[KvCache] hit $key (${len ~/ 1024} KiB)');
        return f;
      }
      debugPrint('[KvCache] miss $key');
      return null;
    } catch (e) {
      debugPrint('[KvCache] findCached failed: $e');
      return null;
    }
  }

  /// Returns the destination [File] where the engine should
  /// [LlamaEngine.stateSaveFile] to. Creates parent directory if needed.
  /// Does NOT write — caller owns the llamadart save call.
  Future<File> destinationFor(String key) async {
    final dir = await _dir();
    return File('${dir.path}/$key$_kExtension');
  }

  /// Deletes any KV files in the cache dir whose stem does NOT match
  /// [keepKey]. Logs but never throws.
  Future<void> evictStale({required String keepKey}) async {
    try {
      final dir = await _dir();
      if (!await dir.exists()) return;
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (!name.endsWith(_kExtension)) continue;
        final stem = name.substring(0, name.length - _kExtension.length);
        if (stem == keepKey) continue;
        try {
          await entity.delete();
          debugPrint('[KvCache] evicted $name');
        } catch (e) {
          debugPrint('[KvCache] evict failed for $name: $e');
        }
      }
    } catch (e) {
      debugPrint('[KvCache] evictStale failed: $e');
    }
  }

  /// Total bytes used by KV cache files. For logging.
  Future<int> cacheBytes() async {
    try {
      final dir = await _dir();
      if (!await dir.exists()) return 0;
      var total = 0;
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith(_kExtension)) {
          try {
            total += await entity.length();
          } catch (_) {}
        }
      }
      return total;
    } catch (e) {
      debugPrint('[KvCache] cacheBytes failed: $e');
      return 0;
    }
  }
}
