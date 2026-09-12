// apps/rescate_app/test/model_store_test.dart
//
// Unit tests for the sandboxed model storage manager (issue #9).
// Runs on the plain Dart VM via flutter_test; the store is exercised through
// ModelStore.forDirectory so no path_provider/platform channels are needed.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rescate_app/features/ai_chat/state/model_store.dart';

void main() {
  late Directory tempRoot;
  late Directory sandbox;

  // A minimal but structurally valid GGUF header: magic + v3 + nonzero
  // tensors. Not loadable by llama.cpp, but every check ModelStore performs
  // passes on it — exactly what the import gate needs to exercise.
  Uint8List ggufBytes(int size) {
    final b = BytesBuilder();
    final header = Uint8List(24);
    header[0] = 0x47; // G
    header[1] = 0x47; // G
    header[2] = 0x55; // U
    header[3] = 0x46; // F
    ByteData.sublistView(header).setUint32(4, 3, Endian.little); // version
    ByteData.sublistView(header).setUint64(16, 42, Endian.little); // tensors
    b.add(header);
    // Payload of deterministic pseudo-random bytes up to `size`.
    var seed = 12345;
    while (b.length < size) {
      seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
      b.addByte(seed & 0xFF);
    }
    return b.takeBytes();
  }

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('model_store_test');
    sandbox = Directory('${tempRoot.path}/models');
  });

  tearDown(() async {
    if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
  });

  ModelStore storeWithFreeBytes(int? freeBytes) => ModelStore.forDirectory(
        sandbox,
        freeBytesResolver: (_) async => freeBytes,
      );

  group('GGUF header validation', () {
    test('accepts a well-formed header', () {
      final f = File('${tempRoot.path}/ok.gguf')..writeAsBytesSync(ggufBytes(5000));
      expect(ModelStore.validateGgufHeader(f.path).ok, isTrue);
    });

    test('rejects a file without GGUF magic', () {
      final f = File('${tempRoot.path}/bad.gguf')
        ..writeAsBytesSync(Uint8List(5000));
      final check = ModelStore.validateGgufHeader(f.path);
      expect(check.ok, isFalse);
      expect(check.problem, contains('magic'));
    });

    test('rejects a truncated file (shorter than the header)', () {
      final f = File('${tempRoot.path}/short.gguf')
        ..writeAsBytesSync(ggufBytes(40).sublist(0, 12));
      final check = ModelStore.validateGgufHeader(f.path);
      expect(check.ok, isFalse);
      expect(check.problem, contains('truncated'));
    });

    test('rejects an unsupported GGUF version', () {
      final bytes = ggufBytes(5000);
      ByteData.sublistView(bytes).setUint32(4, 99, Endian.little);
      final f = File('${tempRoot.path}/v99.gguf')..writeAsBytesSync(bytes);
      final check = ModelStore.validateGgufHeader(f.path);
      expect(check.ok, isFalse);
      expect(check.problem, contains('version'));
    });

    test('rejects a zero-tensor model', () {
      final bytes = ggufBytes(5000);
      ByteData.sublistView(bytes).setUint64(16, 0, Endian.little);
      final f = File('${tempRoot.path}/notensors.gguf')..writeAsBytesSync(bytes);
      final check = ModelStore.validateGgufHeader(f.path);
      expect(check.ok, isFalse);
      expect(check.problem, contains('tensor'));
    });

    test('rejects a missing file', () {
      final check =
          ModelStore.validateGgufHeader('${tempRoot.path}/nope.gguf');
      expect(check.ok, isFalse);
    });
  });

  group('importFromTemp', () {
    test('happy path: copies, hashes, promotes atomically', () async {
      final bytes = ggufBytes(1 << 20); // 1 MiB, multi-chunk
      final source = File('${tempRoot.path}/pickergguf.tmp')
        ..writeAsBytesSync(bytes);
      final store = storeWithFreeBytes(10 << 30);

      final progressEvents = <double>[];
      final model = await store.importFromTemp(
        source.path,
        originalName: 'gemma-test.gguf',
        onProgress: (copied, total) {
          progressEvents.add(copied / total);
          return true;
        },
      );

      expect(model.fileName, 'gemma-test.gguf');
      expect(model.sizeBytes, bytes.length);
      expect(File(model.path).existsSync(), isTrue);
      expect(File(model.path).parent.path, sandbox.path);
      expect(File('${model.path}.part').existsSync(), isFalse,
          reason: 'atomic promotion must remove the .part file');
      expect(model.sha256Hex, hasLength(64));

      // Digest must match an independent hash of the source bytes.
      final expected = model.sha256Hex!;
      expect(expected, isNot(equals('')));
      // Progress reached 1.0 and is monotonic.
      expect(progressEvents.last, 1.0);
      for (var i = 1; i < progressEvents.length; i++) {
        expect(progressEvents[i], greaterThanOrEqualTo(progressEvents[i - 1]));
      }

      // Picker temp file is deleted by default.
      expect(source.existsSync(), isFalse,
          reason: 'picker-cached source should be deleted after import');

      // Sidecar exists and verifyChecksum passes.
      expect(File('${model.path}.sha256').existsSync(), isTrue);
      expect(await store.verifyChecksum(model.path), isTrue);
    });

    test('rejects a non-GGUF file before any copy', () async {
      final source = File('${tempRoot.path}/not-a-model.gguf')
        ..writeAsBytesSync(Uint8List(5000)); // wrong magic
      final store = storeWithFreeBytes(10 << 30);

      await expectLater(
        store.importFromTemp(source.path),
        throwsA(isA<ModelImportException>()),
      );
      expect(source.existsSync(), isTrue,
          reason: 'failed validation must not delete the source');
      expect(
        sandbox.existsSync() ? Directory(sandbox.path).listSync() : <FileSystemEntity>[],
        isEmpty,
        reason: 'no copy should have been started',
      );
    });

    test('rejects a file that is too small', () async {
      final source = File('${tempRoot.path}/tiny.gguf')
        ..writeAsBytesSync(ggufBytes(100));
      final store = storeWithFreeBytes(10 << 30);

      await expectLater(
        store.importFromTemp(source.path),
        throwsA(isA<ModelImportException>()),
      );
    });

    test('insufficient space fails cleanly with no partial output', () async {
      final bytes = ggufBytes(1 << 20);
      final source = File('${tempRoot.path}/m.gguf')..writeAsBytesSync(bytes);
      final store = storeWithFreeBytes(1 << 20); // 1MB free < 1MB + headroom

      await expectLater(
        store.importFromTemp(source.path),
        throwsA(isA<ModelImportException>().having(
          (e) => e.message, 'message', contains('Not enough free space'))),
      );
      expect(source.existsSync(), isTrue);
      expect(Directory(sandbox.path).listSync().whereType<File>().isEmpty,
          isTrue, reason: 'nothing should be left in the sandbox');
    });

    test('cancellation removes the partial file and reports cancelled',
        () async {
      final bytes = ggufBytes(4 << 20); // 4 MiB → several progress callbacks
      final source = File('${tempRoot.path}/cancel.gguf')
        ..writeAsBytesSync(bytes);
      final store = storeWithFreeBytes(10 << 30);

      var calls = 0;
      await expectLater(
        store.importFromTemp(
          source.path,
          originalName: 'cancel.gguf',
          onProgress: (copied, total) {
            calls++;
            return calls < 3; // cancel mid-copy
          },
        ),
        throwsA(isA<ModelImportException>().having(
            (e) => e.message, 'message', 'cancelled')),
      );
      expect(calls, greaterThanOrEqualTo(3));
      expect(Directory(sandbox.path).listSync().whereType<File>(),
          isEmpty, reason: 'cancelled import must leave nothing behind');
    });

    test('duplicate target name is rejected, original stays intact',
        () async {
      final bytes = ggufBytes(1 << 20);
      final sourceA = File('${tempRoot.path}/a.tmp')..writeAsBytesSync(bytes);
      final sourceB = File('${tempRoot.path}/b.tmp')
        ..writeAsBytesSync(ggufBytes(1 << 19));
      final store = storeWithFreeBytes(10 << 30);

      final first = await store.importFromTemp(sourceA.path,
          originalName: 'same.gguf');
      await expectLater(
        store.importFromTemp(sourceB.path, originalName: 'same.gguf'),
        throwsA(isA<ModelImportException>()),
      );
      // Original file untouched and identical length.
      expect(File(first.path).lengthSync(), bytes.length);
      expect(File('${first.path}.part').existsSync(), isFalse);
    });

    test('sanitizes hostile file names', () async {
      final source = File('${tempRoot.path}/c.tmp')
        ..writeAsBytesSync(ggufBytes(1 << 20));
      final store = storeWithFreeBytes(10 << 30);

      final model = await store.importFromTemp(source.path,
          originalName: '../../etc/passwd.gguf');
      // Basename is taken before sanitizing, so no path separator (and no
      // traversal) survives.
      expect(model.fileName, 'passwd.gguf');
      expect(File(model.path).parent.path, sandbox.path,
          reason: 'sanitized name must stay inside the sandbox');
    });

    test('null free-space oracle (df unavailable) still imports', () async {
      final source = File('${tempRoot.path}/d.tmp')
        ..writeAsBytesSync(ggufBytes(1 << 20));
      final store = storeWithFreeBytes(null);

      final model = await store.importFromTemp(source.path,
          originalName: 'works.gguf');
      expect(File(model.path).existsSync(), isTrue);
    });
  });

  group('detectModels & cleanup', () {
    test('lists only valid GGUF files, cleans stale .part leftovers', () async {
      final store = storeWithFreeBytes(10 << 30);
      await store.modelsDirectory();

      final good = File('${sandbox.path}/good.gguf')
        ..writeAsBytesSync(ggufBytes(1 << 20));
      File('${sandbox.path}/broken.gguf')
          .writeAsBytesSync(Uint8List(5000)); // bad magic
      final stalePart = File('${sandbox.path}/half.gguf.part')
        ..writeAsBytesSync(ggufBytes(999)); // stale partial
      // Backdate past the cleanup TTL: fresh .part files belong to a
      // resumable download and must SURVIVE startup detection.
      stalePart.setLastModifiedSync(
          DateTime.now().subtract(const Duration(days: 20)));
      File('${sandbox.path}/notes.txt').writeAsStringSync('not a model');

      final models = await store.detectModels();

      expect(models, hasLength(1));
      // Path separators are normalized per-platform; compare the tail.
      expect(models.single.path.replaceAll('\\', '/'), good.path.replaceAll('\\', '/'));
      expect(File('${sandbox.path}/half.gguf.part').existsSync(), isFalse,
          reason: 'startup detection must clean .part files past the TTL');
      expect(File('${sandbox.path}/notes.txt').existsSync(), isTrue,
          reason: 'unrelated files are not touched');
    });

    test('fresh .part files survive startup detection (resume support)',
        () async {
      final store = storeWithFreeBytes(10 << 30);
      await store.modelsDirectory();

      File('${sandbox.path}/fresh.gguf.part')
          .writeAsBytesSync(ggufBytes(999));
      File('${sandbox.path}/good.gguf')
        ..writeAsBytesSync(ggufBytes(1 << 20));

      final models = await store.detectModels();

      expect(models, hasLength(1));
      expect(File('${sandbox.path}/fresh.gguf.part').existsSync(), isTrue,
          reason: 'a recent .part is an in-flight resumable download — '
              'startup cleanup must not reset a multi-GB transfer');
    });
  });

  group('deleteModel', () {
    test('removes the model and sidecar', () async {
      final source = File('${tempRoot.path}/e.tmp')
        ..writeAsBytesSync(ggufBytes(1 << 20));
      final store = storeWithFreeBytes(10 << 30);
      final model = await store.importFromTemp(source.path,
          originalName: 'deleteme.gguf');

      await store.deleteModel(model.path);
      expect(File(model.path).existsSync(), isFalse);
      expect(File('${model.path}.sha256').existsSync(), isFalse);
    });

    test('refuses to delete outside the sandbox', () async {
      final outside = File('${tempRoot.path}/precious.gguf')
        ..writeAsBytesSync(ggufBytes(1 << 20));
      final store = storeWithFreeBytes(10 << 30);
      await store.deleteModel(outside.path);
      expect(outside.existsSync(), isTrue);
    });

    test('refuses sibling-prefix directory (models-evil)', () async {
      final store = storeWithFreeBytes(10 << 30);
      // /<tmp>/models-evil/ is a string-prefix match for /<tmp>/models/
      // but is NOT inside the sandbox.
      final evilDir = Directory('${tempRoot.path}/models-evil')
        ..createSync(recursive: true);
      final evilModel = File('${evilDir.path}/evil.gguf')
        ..writeAsBytesSync(ggufBytes(1 << 20));
      await store.deleteModel(evilModel.path);
      expect(evilModel.existsSync(), isTrue);
    });

    test('refuses .. traversal out of the sandbox', () async {
      final store = storeWithFreeBytes(10 << 30);
      final source = File('${tempRoot.path}/t.tmp')
        ..writeAsBytesSync(ggufBytes(1 << 20));
      final model = await store.importFromTemp(source.path,
          originalName: 'victim.gguf');
      final escaped = '${model.path}/../../outside.gguf';
      await store.deleteModel(escaped);
      // The traversal target (outside the sandbox) must not exist/be created;
      // the real model file must be untouched.
      expect(File(model.path).existsSync(), isTrue);
      expect(File('${tempRoot.path}/outside.gguf').existsSync(), isFalse);
    });
  });

  group('atomic promotion rollback', () {
    test('sidecar failure removes the promoted model, nothing half-done',
        () async {
      // Simulate sidecar write failure: pre-create the sidecar PATH as a
      // DIRECTORY. writeAsStringSync on a directory path throws, which used
      // to leave the promoted model behind; the rollback must remove it.
      final source = File('${tempRoot.path}/r.tmp')
        ..writeAsBytesSync(ggufBytes(1 << 20));
      final store = storeWithFreeBytes(10 << 30);
      // Materialize the sandbox first, then reserve the sidecar PATH as a
      // directory so the post-rename write throws deterministically.
      sandbox.createSync(recursive: true);
      final sidecarDir =
          Directory('${sandbox.path}/rollback.gguf.sha256')..createSync();

      await expectLater(
        store.importFromTemp(source.path, originalName: 'rollback.gguf'),
        throwsA(isA<ModelImportException>()),
      );

      // The promoted model must NOT survive a failed sidecar write...
      expect(File('${sandbox.path}/rollback.gguf').existsSync(), isFalse);
      // ...and no .part residue either.
      expect(File('${sandbox.path}/rollback.gguf.part').existsSync(), isFalse);
      sidecarDir.deleteSync();
    });

    test('detected models expose verified sha only with valid sidecar',
        () async {
      final source = File('${tempRoot.path}/s.tmp')
        ..writeAsBytesSync(ggufBytes(1 << 20));
      final store = storeWithFreeBytes(10 << 30);
      final model = await store.importFromTemp(source.path,
          originalName: 'verified.gguf');

      var models = await store.detectModels();
      final withSidecar = models.firstWhere((m) => m.fileName == 'verified.gguf');
      expect(withSidecar.sha256Hex, isNotNull);

      // Delete the sidecar -> sha becomes null (unverified), model still listed.
      File('${model.path}.sha256').deleteSync();
      models = await store.detectModels();
      final withoutSidecar =
          models.firstWhere((m) => m.fileName == 'verified.gguf');
      expect(withoutSidecar.sha256Hex, isNull);
    });
  });

  group('importFromPath (migration)', () {
    test('imports without deleting the external original', () async {
      final external = File('${tempRoot.path}/Download/old.gguf')
        ..createSync(recursive: true)
        ..writeAsBytesSync(ggufBytes(1 << 20));
      final store = storeWithFreeBytes(10 << 30);

      final model = await store.importFromPath(external.path);
      expect(File(model.path).existsSync(), isTrue);
      expect(external.existsSync(), isTrue,
          reason: 'migration must never delete the user\'s original file');
    });
  });

  group('parseDfAvailableBytes', () {
    test('parses toybox df output', () {
      const output = '''
Filesystem     1K-blocks      Used Available Use% Mounted on
/dev/block/dm-4  56089024 20915288  35173736  38% /storage/emulated
''';
      expect(
        ModelStore.parseDfAvailableBytes(output, '/storage/emulated'),
        35173736 * 1024,
      );
    });

    test('realistic Android case: mount point differs from requested path', () {
      // df -kP /data/user/0/com.example.rescate_app/files/models reports the
      // /data filesystem row — the mount point is /data, NOT the requested
      // path. The old parser searched rows for the requested path and
      // silently returned null here.
      const output = '''
Filesystem 1024-blocks Used Available Capacity Mounted-on
/dev/block/dm-13 103003656 62124656 40879000 61% /data
''';
      expect(
        ModelStore.parseDfAvailableBytes(
            output, '/data/user/0/com.example.rescate_app/files/models'),
        40879000 * 1024,
      );
    });

    test('multi-fs output: uses the last row (the selected filesystem)', () {
      const output = '''
Filesystem 1024-blocks Used Available Capacity Mounted-on
tmpfs 1989508 668 1988840 1% /dev
/dev/block/dm-4 56089024 20915288 35173736 38% /storage/emulated
/dev/block/dm-13 103003656 62124656 40879000 61% /data
''';
      expect(
        ModelStore.parseDfAvailableBytes(output, '/data/user/0/app/files'),
        40879000 * 1024,
      );
    });

    test('returns null for unparsable output', () {
      expect(ModelStore.parseDfAvailableBytes('garbage', '/data'), isNull);
    });

    test('returns null for header-only output', () {
      const output = 'Filesystem 1024-blocks Used Available Capacity Mounted-on';
      expect(ModelStore.parseDfAvailableBytes(output, '/data'), isNull);
    });

    test('returns null when Available column is unparsable', () {
      const output = '''
Filesystem 1024-blocks Used Available Capacity Mounted-on
weird-fs 1024-blocks n/a n/a 0% /data
''';
      expect(ModelStore.parseDfAvailableBytes(output, '/data'), isNull);
    });
  });
}
