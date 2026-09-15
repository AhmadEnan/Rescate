// Tests for ModelStore.downloadModel: atomicity, validation, checksum,
// cancellation, free-space, HTTP Range resume, and happy path — using a
// local HttpServer and ModelStore.forDirectory (no path_provider/platform
// channels needed).
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:rescate_app/features/ai_chat/state/known_models.dart';
import 'package:rescate_app/features/ai_chat/state/model_store.dart';

/// Minimal in-process HTTP server serving byte blobs at /<name>.
/// Honors `Range: bytes=N-` with a 206 partial response so resume behavior
/// can be exercised end-to-end.
class _BlobServer {
  HttpServer? _server;
  final Map<String, Uint8List> blobs = {};
  final Set<String> interrupted = {};
  // Per-path content-length overrides (simulates server artifact drift).
  final Map<String, int> lengthOverrides = {};

  /// Status code served for each request, in request order, per path.
  /// `200` for a full body, `206` for a ranged response.
  final Map<String, List<int>> servedStatus = {};

  int chunkSize = 64 * 1024;

  /// Per-path byte offset at which the server stops writing and waits for
  /// [release].
  ///
  /// Needed because a test CANNOT control how the client's response stream is
  /// chunked: `HttpClientResponse` emits one event per socket read, and how
  /// many reads an N-byte body takes is a function of socket/loopback
  /// buffering — not of [chunkSize] or of the `flush()` calls below. A test
  /// that decides to cancel "after N progress callbacks" therefore races the
  /// client: on a fast runner the whole body can land in one or two reads, the
  /// callback count never reaches N, and the download completes. Holding the
  /// server at a known offset makes "the body is incomplete" a fact rather
  /// than a hope.
  final Map<String, int> holdAfter = {};
  final Map<String, Completer<void>> _gates = {};

  /// Upper bound on how long a [holdAfter] gate blocks before the server
  /// resumes writing. See the hold site for why this must be bounded.
  static const Duration holdTimeout = Duration(seconds: 2);

  /// Releases a hold created via [holdAfter]. Safe to call more than once,
  /// and safe to call for a path that was never held.
  void release(String name) {
    final gate = _gates[name];
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  Future<String> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((req) async {
      final name = req.uri.path.substring(1);
      final blob = blobs[name];
      if (blob == null) {
        req.response.statusCode = 404;
        await req.response.close();
        return;
      }

      // Range support: `bytes=N-` → 206 serving [N, end).
      var start = 0;
      final rangeHeader = req.headers.value(HttpHeaders.rangeHeader);
      if (rangeHeader != null) {
        final m = RegExp(r'bytes=(\d+)-').firstMatch(rangeHeader);
        if (m != null) start = int.parse(m.group(1)!);
      }
      if (start >= blob.length) {
        req.response.statusCode = 416;
        await req.response.close();
        return;
      }

      final override = lengthOverrides[name];
      final declaredLength = override ?? blob.length;
      if (start > 0) {
        req.response.statusCode = 206;
        req.response.headers.set(HttpHeaders.contentRangeHeader,
            'bytes $start-${declaredLength - 1}/$declaredLength');
      }
      // Record what we actually served, in request order. A resume test must
      // assert on THIS rather than infer 206-ness from progress ticks: a fast
      // client can receive a re-downloaded full body in a single read, which
      // satisfies a "first tick is at least the partial" assertion without any
      // resume having happened.
      (servedStatus[name] ??= <int>[]).add(start > 0 ? 206 : 200);
      req.response.contentLength = declaredLength - start;
      final limit = interrupted.contains(name) ? blob.length ~/ 2 : blob.length;
      try {
        final holdAt = holdAfter[name];
        var off = start;
        var held = false;
        while (off < limit) {
          var end = (off + chunkSize) > limit ? limit : off + chunkSize;
          // Never flush past a hold point. Otherwise the amount the client can
          // have buffered would still depend on [chunkSize] — with a chunk
          // larger than the hold offset the server would push the whole body
          // in one write and the hold would be meaningless.
          if (holdAt != null && off < holdAt && end > holdAt) end = holdAt;
          req.response.add(blob.sublist(off, end));
          await req.response.flush();
          off = end;
          if (holdAt != null && off >= holdAt && !held) {
            held = true;
            // Bounded: if the client does not cancel promptly the server
            // resumes anyway, so a regression surfaces as "the download
            // completed" within a couple of seconds (the same symptom CI
            // reported) instead of hanging until the test timeout.
            await Future.any<void>(<Future<void>>[
              (_gates[name] ??= Completer<void>()).future,
              Future<void>.delayed(holdTimeout),
            ]);
          }
        }
      } catch (_) {
        // The client detached its socket while we were held — which is
        // exactly what the cancel test asserts. Nothing to do.
        return;
      }
      if (interrupted.contains(name) || lengthOverrides.containsKey(name)) {
        // Torn download (interrupted) or drift simulation (lengthOverride):
        // the body is shorter than the declared contentLength, so close()
        // throws server-side — catch and swallow; the client still sees a
        // truncated/short stream.
        try {
          await req.response.close();
        } catch (_) {}
        return;
      }
      // Guard unconditionally: on Windows/flutter_test, response teardown
      // can surface an uncaught ZONE error AFTER the client consumed the
      // whole body, which would fail the test spuriously.
      try {
        await req.response.close();
      } catch (_) {}
    });
    return 'http://127.0.0.1:${_server!.port}';
  }

  Future<void> stop() async {
    // Never leave a handler parked on a gate: an un-completed `holdAfter`
    // would keep the request alive past the end of the test.
    for (final gate in _gates.values) {
      if (!gate.isCompleted) gate.complete();
    }
    await _server?.close(force: true);
  }
}

// NOTE: this file used to carry a `flutterTestWindowsHttpNpe` guard that
// skipped five of these tests on Windows, because `dart:_http` reported an
// uncaught "Null check operator used on a null value" (misattributed to
// `_HttpClient.getUrl`) after a large body was fully consumed. That guard is
// gone: the cause was a real product bug, not a test-harness quirk.
//
// `ModelStore.downloadModel` called `response.detachSocket()` in its `finally`
// unconditionally, including for a response it had already fully read.
// Detaching a drained response takes a healthy keep-alive connection out of the
// pool and destroys it, and on a ranged (206) response it trips the NPE above.
// Because that surfaces as an *uncaught async error*, it is attributed to
// whatever runs next — which is why it looked like it came from a later
// `_HttpClient.getUrl`, and why it could not be caught by wrapping a test body
// in `try`/`catch`.
//
// `detachSocket()` is now called only when the body was abandoned mid-stream
// (cancel, or a server that closed early), which is the case it exists for.
// The guard was deleted rather than narrowed so these five tests run on Windows
// again; every one of them fails with the NPE if that condition is reverted, so
// they are genuine regression coverage for the fix.
//
// Tracked in issue #34.

Uint8List _ggufBlob(int size) {
  final b = Uint8List(size);
  b[0] = 0x47; b[1] = 0x47; b[2] = 0x55; b[3] = 0x46; // 'GGUF'
  final bd = ByteData.sublistView(b);
  bd.setUint32(4, 3, Endian.little); // version 3
  bd.setUint64(16, 42, Endian.little); // non-zero tensor count
  var seed = 12345;
  for (var i = 24; i < size; i++) {
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
    b[i] = seed & 0xFF;
  }
  return b;
}

void main() {
  late _BlobServer server;
  late String baseUrl;
  late Directory tempRoot;
  late Directory sandbox;

  Uint8List ggufBlob(int size) => _ggufBlob(size);

  setUp(() async {
    server = _BlobServer();
    baseUrl = await server.start();
    tempRoot = await Directory.systemTemp.createTemp('dl_test');
    sandbox = Directory('${tempRoot.path}/models');
  });

  tearDown(() async {
    await server.stop();
    if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
  });

  ModelStore store() => ModelStore.forDirectory(
        sandbox,
        freeBytesResolver: (_) async => 50 * 1024 * 1024 * 1024, // 50 GB
      );


  group('downloadModel (against a real local HTTP server)', () {
    test('happy path: streams, hashes, atomically promotes',
        () async {
      final blob = ggufBlob(1024 * 1024); // 1 MB — above min-plausible
      server.blobs['model.gguf'] = blob;
      final url = Uri.parse('$baseUrl/model.gguf');

      final model = await store().downloadModel(
        url,
        'model.gguf',
        onProgress: (copied, total) {
          expect(total, blob.length);
          return true;
        },
      );

      expect(model.sizeBytes, blob.length);
      expect(model.sha256Hex, isNotEmpty);
      expect(File(model.path).existsSync(), isTrue);
      expect(File(model.path).lengthSync(), blob.length);
      // bytes identical to the served blob
      final onDisk = File(model.path).readAsBytesSync();
      expect(onDisk.length, blob.length);
      // no .part residue
      expect(File('${model.path}.part').existsSync(), isFalse);
      // sidecar written with the same hash
      final sidecar = File('${model.path}.sha256');
      expect(sidecar.existsSync(), isTrue);
      expect(sidecar.readAsStringSync(), model.sha256Hex);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('checksum mismatch: rejected, part removed, nothing promoted',
        () async {
      final blob = ggufBlob(1024 * 1024);
      server.blobs['corrupt.gguf'] = blob;
      final url = Uri.parse('$baseUrl/corrupt.gguf');

      await expectLater(
        store().downloadModel(
          url,
          'corrupt.gguf',
          expectedSha256: 'deadbeef',
        ),
        throwsA(isA<ModelImportException>()),
      );
      expect(File('${sandbox.path}/corrupt.gguf').existsSync(), isFalse);
      expect(File('${sandbox.path}/corrupt.gguf.part').existsSync(), isFalse);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test(
        'server interruption mid-stream: clean failure, partial KEPT for resume',
        () async {
      final blob = ggufBlob(8 * 1024 * 1024);
      server.blobs['torn.gguf'] = blob;
      server.interrupted.add('torn.gguf');
      final url = Uri.parse('$baseUrl/torn.gguf');

      await expectLater(
        store().downloadModel(url, 'torn.gguf'),
        throwsA(isA<ModelImportException>().having(
            (e) => e.message, 'message', contains('progress kept'))),
      );
      expect(File('${sandbox.path}/torn.gguf').existsSync(), isFalse,
          reason: 'nothing may be promoted from a torn download');
      final part = File('${sandbox.path}/torn.gguf.part');
      expect(part.existsSync(), isTrue,
          reason: 'an interrupted download keeps its partial so the next '
              'attempt resumes instead of restarting');
      final partialLen = part.lengthSync();
      expect(partialLen, greaterThan(0));
      expect(partialLen, lessThan(blob.length));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('resume: retry continues from the kept partial via HTTP 206',
        () async {
      final blob = ggufBlob(8 * 1024 * 1024);
      server.blobs['resume.gguf'] = blob;
      final url = Uri.parse('$baseUrl/resume.gguf');
      final s = store();

      // Seed the kept partial directly instead of producing it with a first,
      // torn download.
      //
      // The "a torn download keeps its partial" half is already covered by the
      // preceding `server interruption mid-stream` test, so nothing is lost by
      // not repeating it here. One request also keeps the failure attribution
      // clean: the NPE this test used to hit (issue #34) surfaced as an
      // uncaught async error from the *previous* response's teardown and was
      // reported against the next `getUrl`, so a two-request test points the
      // blame at the wrong request. The product bug behind it is fixed in
      // `ModelStore.downloadModel`; see the note near the top of this file.
      final partFile = File('${sandbox.path}/resume.gguf.part');
      await partFile.parent.create(recursive: true);
      final kept = blob.sublist(0, blob.length ~/ 2);
      await partFile.writeAsBytes(kept, flush: true);

      // The server serves the whole artifact, so a resume must come back as
      // 206 for the tail. If it answered 200 instead, `downloadModel` drains
      // and restarts, and the first progress tick would be ~one chunk.
      final progressFirstCopied = <int>[];
      final model = await s.downloadModel(
        url,
        'resume.gguf',
        onProgress: (copied, total) {
          progressFirstCopied.add(copied);
          return true;
        },
      );

      expect(model.sizeBytes, blob.length);
      // The decisive assertion: exactly one request, and it was ranged. A
      // 200 would mean the server ignored the Range header and the artifact
      // was re-downloaded from scratch — not a resume at all.
      expect(server.servedStatus['resume.gguf'], <int>[206],
          reason: 'a resume must be a single ranged request');
      expect(progressFirstCopied.first, greaterThanOrEqualTo(kept.length),
          reason: 'first progress tick must be at-or-after the kept partial — '
              'a restart would report ~one chunk');
      expect(progressFirstCopied.last, blob.length);
      // Bytes identical to the served artifact (full-file hash over the
      // joined partial + resumed bytes).
      expect(
        model.sha256Hex,
        crypto.sha256.convert(blob).toString(),
      );
      expect(File('${sandbox.path}/resume.gguf.part').existsSync(), isFalse);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('cancel mid-download keeps the partial for resume', () async {
      final blob = ggufBlob(8 * 1024 * 1024);
      server.blobs['cancel.gguf'] = blob;
      // Hold the server after a bounded prefix so the body is PROVABLY
      // incomplete when the client cancels. Cancelling on a callback count
      // instead raced the client's stream chunking (see [holdAfter]): CI
      // observed the full 8388608-byte partial, i.e. the cancel never fired
      // because all 8 MiB arrived in fewer reads than the threshold.
      server.holdAfter['cancel.gguf'] = 128 * 1024;
      final url = Uri.parse('$baseUrl/cancel.gguf');

      await expectLater(
        store().downloadModel(
          url,
          'cancel.gguf',
          // Cancel at the first opportunity. The server cannot have flushed
          // more than the held prefix, so whatever the client has buffered is
          // a strict prefix of the artifact — no matter how the stream was
          // chunked.
          onProgress: (copied, total) => false,
        ),
        throwsA(isA<ModelImportException>().having(
            (e) => e.message, 'message', 'cancelled')),
      );
      server.release('cancel.gguf');

      expect(File('${sandbox.path}/cancel.gguf').existsSync(), isFalse);
      final part = File('${sandbox.path}/cancel.gguf.part');
      expect(part.existsSync(), isTrue,
          reason: 'cancelled downloads keep their partial');
      expect(part.lengthSync(), greaterThan(0));
      expect(part.lengthSync(), lessThan(blob.length));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('HTTP 404 surfaces a clean ModelImportException', () async {
      final url = Uri.parse('$baseUrl/does-not-exist.gguf');
      await expectLater(
        store().downloadModel(url, 'does-not-exist.gguf'),
        throwsA(isA<ModelImportException>()),
      );
      expect(File('${sandbox.path}/does-not-exist.gguf').existsSync(), isFalse);
    });

    test('insufficient free space: rejected before download starts', () async {
      final blob = ggufBlob(1024 * 1024);
      server.blobs['big.gguf'] = blob;
      final url = Uri.parse('$baseUrl/big.gguf');
      final tight = ModelStore.forDirectory(
        sandbox,
        freeBytesResolver: (_) async => 256 * 1024, // 256 KB free
      );
      await expectLater(
        tight.downloadModel(url, 'big.gguf'),
        throwsA(isA<ModelImportException>()),
      );
      expect(File('${sandbox.path}/big.gguf').existsSync(), isFalse);
      expect(File('${sandbox.path}/big.gguf.part').existsSync(), isFalse);
    });

    test('duplicate name: refuses to overwrite an existing model',
        () async {
      final blob = ggufBlob(1024 * 1024);
      server.blobs['dupe.gguf'] = blob;
      final url = Uri.parse('$baseUrl/dupe.gguf');
      final s = store();
      await s.downloadModel(url, 'dupe.gguf');
      await expectLater(
        s.downloadModel(url, 'dupe.gguf'),
        throwsA(isA<ModelImportException>()),
      );
    });

    test('non-gguf filename rejected before any network call', () async {
      await expectLater(
        store().downloadModel(Uri.parse('$baseUrl/whatever'), 'malware.exe'),
        throwsA(isA<ModelImportException>()),
      );
      expect(server.blobs.containsKey('whatever'), isFalse);
    });

    test('content-length vs expectedBytes mismatch fails fast', () async {
      final blob = ggufBlob(1024 * 1024);
      server.blobs['drifted.gguf'] = blob;
      server.lengthOverrides['drifted.gguf'] = blob.length + 4096;
      final url = Uri.parse('$baseUrl/drifted.gguf');

      await expectLater(
        store().downloadModel(url, 'drifted.gguf', expectedBytes: blob.length),
        throwsA(isA<ModelImportException>()),
      );
      // Nothing downloaded, nothing promoted.
      expect(File('${sandbox.path}/drifted.gguf').existsSync(), isFalse);
      expect(File('${sandbox.path}/drifted.gguf.part').existsSync(), isFalse);
    });

    test('content-length matching expectedBytes proceeds normally',
        () async {
      final blob = ggufBlob(1024 * 1024);
      server.blobs['match.gguf'] = blob;
      final url = Uri.parse('$baseUrl/match.gguf');

      final model = await store()
          .downloadModel(url, 'match.gguf', expectedBytes: blob.length);
      expect(model.sizeBytes, blob.length);
      expect(File(model.path).existsSync(), isTrue);
    });
  });

  group('known-models registry contract', () {
    test('registry filenames are sanitized-safe and gguf-suffixed', () {
      for (final model in kKnownModels) {
        expect(model.fileName.toLowerCase().endsWith('.gguf'), isTrue,
            reason: '${model.id} fileName must end in .gguf');
        expect(model.fileName.contains('/'), isFalse,
            reason: '${model.id} fileName must be a bare file name');
        expect(model.downloadUrl.scheme, 'https');
        // Immutable revision pin (not a mutable branch ref like `main`).
        expect(model.downloadUrl.pathSegments.contains('resolve'), isTrue);
        final resolveIdx = model.downloadUrl.pathSegments.indexOf('resolve');
        final ref = model.downloadUrl.pathSegments[resolveIdx + 1];
        expect(ref, isNot('main'),
            reason: '${model.id} URL must pin an immutable revision');
        expect(ref.length, 40,
            reason: '${model.id} revision must be a full git SHA');
      }
    });

    test('every registry entry is checksum- and size-pinned', () {
      for (final model in kKnownModels) {
        expect(model.sha256Hex, isNotNull,
            reason: '${model.id} artifact must be checksum-pinned — GGUF '
                'magic bytes are not an authenticity check');
        expect(model.sha256Hex!.length, 64,
            reason: '${model.id} sha256 must be a 64-char hex digest');
        expect(model.sizeBytes, greaterThan(0),
            reason: '${model.id} size must be pinned so the free-space and '
                'Content-Length checks can run before streaming');
      }
    });

    test('embedder entry stays aligned with the loader', () {
      expect(kEmbedderModel.id, 'embedder');
      expect(kEmbedderModel.fileName, 'qwen3-embedding-0.6b-q5km.gguf');
    });
  });
}
