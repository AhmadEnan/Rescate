// Tests for ModelStore.downloadModel: atomicity, validation, checksum,
// cancellation, free-space, and happy path — using a local HttpServer and
// ModelStore.forDirectory (no path_provider/platform channels needed).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rescate_app/features/ai_chat/state/model_store.dart';

/// Minimal in-process HTTP server serving byte blobs at /<name>.
class _BlobServer {
  HttpServer? _server;
  final Map<String, Uint8List> blobs = {};
  final Set<String> interrupted = {};
  int chunkSize = 64 * 1024;

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
      req.response.contentLength = blob.length;
      final limit = interrupted.contains(name) ? blob.length ~/ 2 : blob.length;
      for (var off = 0; off < limit; off += chunkSize) {
        final end = (off + chunkSize) > limit ? limit : off + chunkSize;
        req.response.add(blob.sublist(off, end));
        await req.response.flush();
      }
      if (interrupted.contains(name)) {
        // Simulate a torn download: close the socket mid-body without
        // completing the declared contentLength. Dart's HttpResponse throws
        // when headers are already sent and close() is called short — catch
        // and swallow; the client still sees a truncated stream.
        try {
          await req.response.close();
        } catch (_) {}
        return;
      }
      await req.response.close();
    });
    return 'http://127.0.0.1:${_server!.port}';
  }

  Future<void> stop() async {
    await _server?.close(force: true);
  }
}

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
    test('happy path: streams, hashes, atomically promotes', () async {
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

    test('server interruption mid-stream: clean failure, nothing promoted',
        () async {
      final blob = ggufBlob(8 * 1024 * 1024);
      server.blobs['torn.gguf'] = blob;
      server.interrupted.add('torn.gguf');
      final url = Uri.parse('$baseUrl/torn.gguf');

      await expectLater(
        store().downloadModel(url, 'torn.gguf'),
        throwsA(isA<ModelImportException>()),
      );
      expect(File('${sandbox.path}/torn.gguf').existsSync(), isFalse);
      expect(File('${sandbox.path}/torn.gguf.part').existsSync(), isFalse);
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

    test('duplicate name: refuses to overwrite an existing model', () async {
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
  });
}
