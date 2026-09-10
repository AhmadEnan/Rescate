// apps/rescate_app/lib/features/ai_chat/state/model_store.dart
//
// Sandboxed model storage manager (issue #9).
//
// Models live inside the app-private support directory, so no storage
// permission is ever needed to read them back at inference time. Imports
// arrive from the system file picker (SAF): the picker gives us a temporary
// copy, ModelStore streams it into the sandbox as `<name>.gguf.part` while
// hashing it, then atomically renames it into place and writes a `.sha256`
// sidecar. Anything that goes wrong — invalid GGUF header, disk full,
// cancellation, crash — leaves at most a `.part` file, which is cleaned on
// the next interaction with the store.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path_provider/path_provider.dart';

/// Thrown when an import cannot be completed. The message is user-safe.
class ModelImportException implements Exception {
  final String message;
  ModelImportException(this.message);

  @override
  String toString() => message;
}

/// A model file that lives inside the sandbox `models` directory.
class ImportedModel {
  final String path;
  final String fileName;
  final int sizeBytes;
  final String? sha256Hex;

  const ImportedModel({
    required this.path,
    required this.fileName,
    required this.sizeBytes,
    this.sha256Hex,
  });
}

/// Result of a GGUF header sanity check.
class GgufHeaderCheck {
  final bool ok;
  final String? problem;
  const GgufHeaderCheck.ok()
      : ok = true,
        problem = null;
  const GgufHeaderCheck.fail(String this.problem) : ok = false;
}

/// Manages the sandboxed `models` directory for on-device GGUF models.
class ModelStore {
  final Future<Directory> Function() _resolveBaseDir;
  final Future<int?> Function(String path) _resolveFreeBytes;

  ModelStore._()
      : _resolveBaseDir = _defaultBaseDir,
        _resolveFreeBytes = _freeBytesViaDf;

  /// Testable constructor: inject the sandbox root and a free-space oracle.
  ModelStore.forDirectory(Directory baseDir,
      {Future<int?> Function(String path)? freeBytesResolver})
      : _resolveBaseDir = (() async => baseDir),
        _resolveFreeBytes = freeBytesResolver ?? _freeBytesViaDf;

  static final ModelStore instance = ModelStore._();

  static Future<Directory> _defaultBaseDir() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}/models');
  }

  /// The sandbox `models` directory, created on first use.
  Future<Directory> modelsDirectory() async {
    final dir = await _resolveBaseDir();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Auto-detects valid models at startup. Partial imports (`.part`) are
  /// cleaned here; files that fail the GGUF sanity gate are not listed.
  Future<List<ImportedModel>> detectModels() async {
    final dir = await modelsDirectory();
    _cleanupPartialFiles(dir);
    final models = <ImportedModel>[];
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      if (!entity.path.toLowerCase().endsWith('.gguf')) continue;
      final model = _describeValidFile(entity);
      if (model != null) models.add(model);
    }
    models.sort((a, b) => a.fileName.compareTo(b.fileName));
    return models;
  }

  /// Validates an existing sandbox file (header + length) without importing.
  ImportedModel? _describeValidFile(File file) {
    try {
      final check = validateGgufHeader(file.path);
      if (!check.ok) return null;
      final length = file.lengthSync();
      if (length <= _kMinPlausibleGgufBytes) return null;
      // Checksum contract: a model WITHOUT a valid sidecar is still listed
      // (imports from the picker legitimately have none until written) but
      // `sha256Hex` stays null — callers can distinguish "verified" models
      // from "unverified" ones and surface a verify/repair prompt.
      final digest = _readSidecarDigest(file.path);
      final verified = digest != null && File('${file.path}.sha256').existsSync();
      return ImportedModel(
        path: file.path,
        fileName: _basename(file.path),
        sizeBytes: length,
        sha256Hex: verified ? digest : null,
      );
    } catch (_) {
      return null;
    }
  }

  /// Imports a model from a temporary file (the system picker's cached copy)
  /// into the sandbox. The copy is streaming and single-pass: bytes flow from
  /// source to the `.part` file while a SHA-256 digest is computed, then the
  /// file is atomically renamed and the sidecar written.
  ///
  /// [onProgress] receives (bytesCopiedSoFar, totalBytes). Return `false`
  /// from it to cancel; the partial file is removed and
  /// [ModelImportException]('cancelled') is thrown.
  ///
  /// [deleteSource] removes the (typically picker-cached) source file after a
  /// successful import.
  Future<ImportedModel> importFromTemp(
    String sourcePath, {
    String? originalName,
    bool Function(int copiedBytes, int totalBytes)? onProgress,
    bool deleteSource = true,
  }) async {
    final source = File(sourcePath);
    if (!source.existsSync()) {
      throw ModelImportException('Selected model file disappeared before import.');
    }

    final name = _sanitizeName(originalName ?? _basename(sourcePath));
    if (!name.toLowerCase().endsWith('.gguf')) {
      throw ModelImportException('Selected file must be a .gguf model.');
    }

    final dir = await modelsDirectory();
    _cleanupPartialFiles(dir);

    final totalBytes = source.lengthSync();
    if (totalBytes <= _kMinPlausibleGgufBytes) {
      throw ModelImportException('File is too small to be a GGUF model.');
    }

    final headerCheck = validateGgufHeader(sourcePath);
    if (!headerCheck.ok) {
      throw ModelImportException('Not a valid GGUF model: ${headerCheck.problem}');
    }

    final available = await _resolveFreeBytes(dir.path);
    if (available != null && available < totalBytes + _kFreeSpaceHeadroomBytes) {
      throw ModelImportException(
        'Not enough free space. The model needs '
        '${(totalBytes / (1024 * 1024)).toStringAsFixed(0)} MB plus working '
        'headroom; ${(available / (1024 * 1024)).toStringAsFixed(0)} MB available.',
      );
    }

    final target = File('${dir.path}/$name');
    final partFile = File('${target.path}.part');
    if (partFile.existsSync()) partFile.deleteSync();
    if (target.existsSync()) {
      throw ModelImportException(
        'A model named "$name" is already stored. Remove it first or rename the new file.',
      );
    }

    final digestSink = _StreamingSha256();
    final rafSource = source.openSync();
    try {
      final rafPart = partFile.openSync(mode: FileMode.write);
      try {
        var copied = 0;
        // Sequential read without seeks: file_picker cache copies (and some
        // content-provider fds) reject setPositionSync with EINVAL (errno 22)
        // even for valid offsets, while sequential reads always work. Since
        // import is strictly front-to-back, the position is implicit.
        while (copied < totalBytes) {
          final chunkSize = copied + _kCopyChunkBytes > totalBytes
              ? totalBytes - copied
              : _kCopyChunkBytes;
          final chunk = rafSource.readSync(chunkSize);
          if (chunk.isEmpty) break;
          rafPart.writeFromSync(chunk);
          digestSink.add(chunk);
          copied += chunk.length;
          if (onProgress != null) {
            final keepGoing = onProgress(copied, totalBytes);
            if (!keepGoing) {
              // Cancelled: bail out and leave nothing behind.
              throw ModelImportException('cancelled');
            }
          }
        }
        rafPart.flushSync();
      } finally {
        rafPart.closeSync();
      }

      // Post-copy validation on the part file: length must match and the
      // header must still parse from the sandbox copy itself.
      final copiedCheck = validateGgufHeader(partFile.path);
      if (!copiedCheck.ok) {
        throw ModelImportException('Imported copy failed GGUF validation: ${copiedCheck.problem}');
      }
      if (partFile.lengthSync() != totalBytes) {
        throw ModelImportException('Import was interrupted: copied size mismatch.');
      }

      // Atomic promotion + sidecar. Rollback contract: if anything after the
      // rename fails (sidecar write, etc.), remove the promoted model AND its
      // sidecar so no half-documented model survives a failed import.
      partFile.renameSync(target.path);
      try {
        File('${target.path}.sha256').writeAsStringSync(
          '${digestSink.hex}\n$totalBytes\n',
          flush: true,
        );
      } catch (_) {
        _deleteQuietly(target);
        _deleteQuietly(File('${target.path}.sha256'));
        rethrow;
      }
    } on ModelImportException {
      _deleteQuietly(partFile);
      rethrow;
    } catch (e) {
      _deleteQuietly(partFile);
      throw ModelImportException('Import failed: $e');
    } finally {
      rafSource.closeSync();
    }

    if (deleteSource) _deleteQuietly(source);

    return ImportedModel(
      path: target.path,
      fileName: name,
      sizeBytes: totalBytes,
      sha256Hex: digestSink.hex,
    );
  }

  /// Imports from a plain filesystem path — used for migrating models that
  /// were previously picked through the old Downloads-browser flow.
  Future<ImportedModel> importFromPath(
    String externalPath, {
    bool Function(int copiedBytes, int totalBytes)? onProgress,
  }) {
    return importFromTemp(
      externalPath,
      originalName: _basename(externalPath),
      onProgress: onProgress,
      deleteSource: false, // never delete a user file from their own storage
    );
  }

  /// Downloads a model over HTTP directly into the sandbox with the same
  /// atomicity guarantees as file import:
  ///   stream -> `<name>.gguf.part` (hashing chunk-wise)
  ///   -> GGUF header re-validation on the sandbox copy
  ///   -> atomic rename -> `.sha256` sidecar.
  ///
  /// Share-friendly flow: a user who received the app from someone else can
  /// fetch models in-app without any file transfer or SAF picker.
  ///
  /// [expectedSha256] (optional): aborts if the downloaded file's hash does
  /// not match. [expectedBytes] (optional): sanity check against truncation
  /// before downloading (server content-length is authoritative otherwise).
  Future<ImportedModel> downloadModel(
    Uri url,
    String fileName, {
    String? expectedSha256,
    int? expectedBytes,
    bool Function(int copiedBytes, int? totalBytes)? onProgress,
    HttpClient? client,
  }) async {
    final name = _sanitizeName(fileName);
    if (!name.toLowerCase().endsWith('.gguf')) {
      throw ModelImportException('Downloaded file must be a .gguf model.');
    }

    final dir = await modelsDirectory();
    _cleanupPartialFiles(dir);

    final target = File('${dir.path}/$name');
    final partFile = File('${target.path}.part');
    if (target.existsSync()) {
      throw ModelImportException(
        'A model named "$name" is already stored. Remove it first or rename the new file.',
      );
    }
    if (partFile.existsSync()) partFile.deleteSync();

    final http = client ?? HttpClient();
    try {
      http.connectionTimeout = const Duration(seconds: 30);
      final request = await http.getUrl(url);
      final response = await request.close();
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw ModelImportException(
          'Download failed: HTTP ${response.statusCode} for $name.',
        );
      }

      // Total size: prefer server content-length; fall back to caller hint.
      // API contract: when BOTH the server length and expectedBytes are
      // known and disagree, the server artifact has drifted from what the
      // caller pinned — fail fast before streaming 400MB to nowhere.
      final contentLength = response.contentLength; // -1 when unknown
      if (contentLength > 0 &&
          expectedBytes != null &&
          expectedBytes > 0 &&
          contentLength != expectedBytes) {
        await response.drain<void>();
        throw ModelImportException(
          'Server artifact size mismatch: expected $expectedBytes bytes '
          '(pinned), server reports $contentLength. The artifact at this '
          'URL changed; update the known-models registry.',
        );
      }
      final totalBytes =
          contentLength > 0 ? contentLength : (expectedBytes ?? -1);

      // Free-space pre-check when we know the size (same headroom as import).
      if (totalBytes > 0) {
        final available = await _resolveFreeBytes(dir.path);
        if (available != null &&
            available < totalBytes + _kFreeSpaceHeadroomBytes) {
          throw ModelImportException(
            'Not enough free space. The model needs '
            '${(totalBytes / (1024 * 1024)).toStringAsFixed(0)} MB plus '
            'working headroom; ${(available / (1024 * 1024)).toStringAsFixed(0)} MB available.',
          );
        }
      }

      final digestSink = _StreamingSha256();
      var copied = 0;
      final rafPart = partFile.openSync(mode: FileMode.write);
      try {
        await for (final chunk in response) {
          rafPart.writeFromSync(chunk);
          digestSink.add(chunk);
          copied += chunk.length;
          if (onProgress != null) {
            final keepGoing =
                onProgress(copied, totalBytes > 0 ? totalBytes : null);
            if (!keepGoing) {
              throw ModelImportException('cancelled');
            }
          }
        }
        rafPart.flushSync();
      } catch (e) {
        rethrow;
      } finally {
        rafPart.closeSync();
        response.detachSocket().then((_) {}).catchError((_) {});
      }

      if (copied <= _kMinPlausibleGgufBytes) {
        throw ModelImportException('Downloaded file is too small to be a GGUF model.');
      }
      if (totalBytes > 0 && copied != totalBytes) {
        throw ModelImportException(
          'Download was interrupted: expected $totalBytes bytes, got $copied.',
        );
      }

      // Validate on the sandbox copy before promotion.
      final check = validateGgufHeader(partFile.path);
      if (!check.ok) {
        throw ModelImportException(
          'Downloaded file failed GGUF validation: ${check.problem}',
        );
      }

      final actualSha = await _hashFile(partFile.path);
      if (expectedSha256 != null &&
          actualSha.toLowerCase() != expectedSha256.toLowerCase()) {
        throw ModelImportException(
          'Checksum mismatch: the download is corrupt or was tampered with. '
          'Expected $expectedSha256, got $actualSha.',
        );
      }

      // Atomic promotion + sidecar.
      partFile.renameSync(target.path);
      File('${target.path}.sha256').writeAsStringSync(actualSha);

      return ImportedModel(
        path: target.path,
        fileName: name,
        sizeBytes: copied,
        sha256Hex: actualSha,
      );
    } on ModelImportException {
      _deleteQuietly(partFile);
      rethrow;
    } catch (e) {
      _deleteQuietly(partFile);
      throw ModelImportException('Download failed: $e');
    } finally {
      if (client == null) http.close();
    }
  }

  /// Re-verifies a stored model against its sidecar checksum. Expensive
  /// (reads the whole file); offered for explicit integrity checks.
  ///
  /// Integrity contract (see README): the sidecar + hash protect against
  /// ACCIDENTAL corruption (truncated copy, bit rot). They are NOT an
  /// authenticity proof — GGUF magic bytes are trivially forgeable.
  /// Authenticity comes from pinning `expectedSha256` at download time
  /// (see [downloadModel]).
  Future<bool> verifyChecksum(String modelPath) async {
    final sidecar = File('$modelPath.sha256');
    if (!sidecar.existsSync()) return false;
    final expected = _readSidecarDigest(modelPath);
    if (expected == null) return false;
    final digest = await _hashFile(modelPath);
    return digest == expected;
  }

  Future<void> deleteModel(String modelPath) async {
    final dir = await modelsDirectory();
    if (!_isInsideSandbox(modelPath, dir)) {
      // Refuse to delete anything outside the sandbox. Canonical-path
      // containment: sibling-prefix paths (`/models-evil/`) and any `..`
      // segments are rejected, not just string-prefix mismatches.
      return;
    }
    _deleteQuietly(File(modelPath));
    _deleteQuietly(File('$modelPath.sha256'));
  }

  /// True when [candidate] resolves to an actual child of [dir].
  ///
  /// Canonicalizes both paths (resolving symlinks where the target exists)
  /// and requires [candidate] to be a direct descendant via path-separator
  /// boundary — so `/support/models-evil/x.gguf` and `/support/models/../x`
  /// cannot pass a naive prefix check.
  static bool _isInsideSandbox(String candidate, Directory dir) {
    String canonical(String p) {
      try {
        return File(p).resolveSymbolicLinksSync();
      } catch (_) {
        // Target may not exist yet; fall back to normalized absolute path.
        final abs = File(p).absolute.path;
        final parts = abs.split(Platform.pathSeparator);
        final out = <String>[];
        for (final part in parts) {
          if (part.isEmpty || part == '.') continue;
          if (part == '..') {
            if (out.isNotEmpty) out.removeLast();
            continue;
          }
          out.add(part);
        }
        return out.join(Platform.pathSeparator);
      }
    }

    final dirPath = canonical(dir.absolute.path);
    final targetPath = canonical(candidate);
    final sep = Platform.pathSeparator;
    return targetPath.startsWith('$dirPath$sep');
  }

  // ---- GGUF validation -----------------------------------------------------

  /// GGUF header sanity check: magic bytes `GGUF`, a known version, and a
  /// non-zero tensor count. Cheap (reads 24 bytes) and catches wrong/truncated
  /// files before any copy happens.
  static GgufHeaderCheck validateGgufHeader(String path) {
    RandomAccessFile raf;
    try {
      raf = File(path).openSync();
    } catch (_) {
      return const GgufHeaderCheck.fail('file cannot be opened');
    }
    try {
      final header = raf.readSync(_kGgufHeaderBytes);
      if (header.length < _kGgufHeaderBytes) {
        return const GgufHeaderCheck.fail('file is truncated');
      }
      final magic = header.sublist(0, 4);
      if (!_listEquals(magic, _kGgufMagic)) {
        return const GgufHeaderCheck.fail('missing GGUF magic bytes');
      }
      final version = header.buffer.asByteData().getUint32(4, Endian.little);
      if (version < 2 || version > 3) {
        return GgufHeaderCheck.fail('unsupported GGUF version $version');
      }
      final tensorCount =
          header.buffer.asByteData().getUint64(16, Endian.little);
      if (tensorCount == 0) {
        return const GgufHeaderCheck.fail('model declares zero tensors');
      }
      return const GgufHeaderCheck.ok();
    } finally {
      raf.closeSync();
    }
  }

  // ---- helpers --------------------------------------------------------------

  void _cleanupPartialFiles(Directory dir) {
    for (final entity in dir.listSync()) {
      if (entity is File && entity.path.endsWith('.part')) {
        _deleteQuietly(entity);
      }
    }
  }

  String? _readSidecarDigest(String modelPath) {
    final sidecar = File('$modelPath.sha256');
    if (!sidecar.existsSync()) return null;
    final first = sidecar.readAsStringSync().split('\n').first.trim();
    return RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(first) ? first : null;
  }

  String _sanitizeName(String name) {
    var base = _basename(name).replaceAll(RegExp(r'[^\w.\- ]'), '_');
    if (base.isEmpty) base = 'model.gguf';
    return base;
  }

  static String _basename(String path) {
    final sep = path.lastIndexOf(RegExp(r'[/\\]'));
    return sep < 0 ? path : path.substring(sep + 1);
  }

  static void _deleteQuietly(File file) {
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (_) {
      // Best effort cleanup must never mask the original failure.
    }
  }

  static Future<String> _hashFile(String path) async {
    final hasher = _StreamingSha256();
    // Sequential read without seeks (same errno-22 consideration as import:
    // content-provider fds may reject setPositionSync).
    final raf = File(path).openSync();
    try {
      final length = raf.lengthSync();
      var remaining = length;
      while (remaining > 0) {
        final chunk = raf.readSync(_kCopyChunkBytes.clamp(0, remaining));
        if (chunk.isEmpty) break;
        hasher.add(chunk);
        remaining -= chunk.length;
      }
      return hasher.hex;
    } finally {
      raf.closeSync();
    }
  }

  /// Best-effort free-space probe by shelling out to `df -k <path>` (works on
  /// Android's toybox and desktop OSes). Returns null when unavailable —
  /// callers then rely on the copy itself failing cleanly.
  static Future<int?> _freeBytesViaDf(String path) async {
    try {
      final result = await Process.run('df', ['-kP', path]);
      if (result.exitCode != 0) return null;
      return parseDfAvailableBytes(result.stdout as String, path);
    } catch (_) {
      return null;
    }
  }

  /// Parses the `Available` (KB) column from `df -kP` output (last row).
  /// Exposed for unit testing.
  /// Parses `df -kP <path>` output into available bytes.
  ///
  /// df prints one row per filesystem: `Filesystem 1024-blocks Used Available
  /// Capacity Mounted-on`. The LAST line is the filesystem actually selected
  /// for [mountPath] — the mount point in that row is the fs root (e.g. `/`
  /// or `/data`), NOT the requested path, so searching rows for [mountPath]
  /// silently returns null on Android and most Linux setups. POSIX `-P`
  /// guarantees exactly 6 columns and no wrapping.
  static int? parseDfAvailableBytes(String dfOutput, String mountPath) {
    final lines = dfOutput
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList(growable: false);
    if (lines.length < 2) return null; // header + at least one fs row
    final columns = lines.last
        .split(RegExp(r'\s+'))
        .where((c) => c.isNotEmpty)
        .toList(growable: false);
    // Filesystem 1024-blocks Used Available Capacity Mounted-on
    if (columns.length < 4) return null;
    final availableKb = int.tryParse(columns[3]);
    if (availableKb == null) return null;
    return availableKb * 1024;
  }

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static const int _kGgufHeaderBytes = 24;
  static const List<int> _kGgufMagic = [0x47, 0x47, 0x55, 0x46]; // "GGUF"
  static const int _kMinPlausibleGgufBytes = 1000;
  static const int _kCopyChunkBytes = 1024 * 512;
  static const int _kFreeSpaceHeadroomBytes = 256 * 1024 * 1024;
}

/// True streaming SHA-256: bytes are hashed chunk-by-chunk with a fixed-size
/// conversion buffer, so memory use is O(chunk), never O(file).
class _StreamingSha256 {
  final _DigestCollector _collector = _DigestCollector();
  late final ByteConversionSink _hashSink =
      crypto.sha256.startChunkedConversion(_collector);

  void add(List<int> chunk) => _hashSink.add(chunk);

  String get hex {
    _hashSink.close();
    return _collector.digest!.toString();
  }
}

/// Receives the finished [crypto.Digest] when the chunked conversion closes.
class _DigestCollector implements Sink<crypto.Digest> {
  crypto.Digest? digest;

  @override
  void add(crypto.Digest data) => digest = data;

  @override
  void close() {}
}
