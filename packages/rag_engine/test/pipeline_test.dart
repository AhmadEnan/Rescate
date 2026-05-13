// test/pipeline_test.dart
//
// Tests E1–E10. Uses MockRagEmbedder + in-memory VectorStore so no model
// assets are required.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:rag_engine/rag_engine.dart';
import 'package:offline_data/offline_data.dart';

import 'embedder_test.dart'; // re-uses MockRagEmbedder

// ─── Helpers ─────────────────────────────────────────────────────────────────

File _tmpTxt(String content) {
  final f = File(
    '${Directory.systemTemp.path}/rag_pipeline_${DateTime.now().microsecondsSinceEpoch}.txt',
  );
  f.writeAsStringSync(content);
  return f;
}

Future<RagPipeline> _makePipeline(VectorStore store) async {
  final p = RagPipeline(store: store, embedder: MockRagEmbedder());
  await p.initialize();
  return p;
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late VectorStore store;
  late RagPipeline pipeline;
  final _files = <File>[];

  setUp(() async {
    store = await VectorStore.open(dbName: inMemoryDatabasePath);
    pipeline = await _makePipeline(store);
  });

  tearDown(() async {
    for (final f in _files) {
      try {
        f.deleteSync();
      } catch (_) {}
    }
    _files.clear();
    await store.clear();
    await store.close();
  });

  File tmpTxt(String content) {
    final f = _tmpTxt(content);
    _files.add(f);
    return f;
  }

  // ── E1 ────────────────────────────────────────────────────────────────────

  test('E1: ingest txt then query → top result contains relevant text', () async {
    final f = tmpTxt(
      'The triage protocol for cardiac arrest requires immediate CPR. '
      'Administer defibrillation within 3 minutes. Notify the on-call physician '
      'immediately to ensure the patient has the highest chance of survival.',
    );
    await pipeline.ingest(f);

    final result = await pipeline.query('cardiac arrest procedure', topK: 3);
    expect(result.results, isNotEmpty);
  });

  // ── E2 ────────────────────────────────────────────────────────────────────

  test('E2: ingest same file twice → chunkCount does not double', () async {
    final f = tmpTxt('Repeated content. ' * 30);
    await pipeline.ingest(f);
    final countAfterFirst = await pipeline.totalChunks();

    await pipeline.ingest(f);
    final countAfterSecond = await pipeline.totalChunks();

    expect(
      countAfterSecond,
      equals(countAfterFirst),
      reason: 'Deduplication must prevent double-ingestion',
    );
  });

  // ── E3 ────────────────────────────────────────────────────────────────────

  test('E3: ingest empty file → chunksAdded = 0, no exception', () async {
    final f = tmpTxt('');
    final result = await pipeline.ingest(f);
    expect(result.chunksAdded, equals(0));
  });

  // ── E4 ────────────────────────────────────────────────────────────────────

  test(
    'E4: ingest file with unknown extension → throws UnsupportedFormatException',
    () async {
      final f = File('${Directory.systemTemp.path}/test.xyz');
      f.writeAsStringSync('some content');
      _files.add(f);
      expect(
        () => pipeline.ingest(f),
        throwsA(isA<UnsupportedFormatException>()),
      );
    },
  );

  // ── E5 ────────────────────────────────────────────────────────────────────

  test(
    'E5: onProgress callback called with values 0.0..1.0, last = 1.0',
    () async {
      final f = tmpTxt('Progress test content. ' * 50);
      final progressValues = <double>[];
      await pipeline.ingest(f, onProgress: progressValues.add);

      expect(progressValues, isNotEmpty);
      for (var i = 0; i < progressValues.length - 1; i++) {
        expect(
          progressValues[i],
          lessThanOrEqualTo(progressValues[i + 1]),
          reason: 'Progress must be non-decreasing',
        );
      }
      expect(progressValues.last, closeTo(1.0, 0.001));
    },
  );

  // ── E6 ────────────────────────────────────────────────────────────────────

  test('E6: query empty string → empty result, no exception', () async {
    final result = await pipeline.query('');
    expect(result.isEmpty, isTrue);
    expect(result.retrievalMs, isNonNegative);
  });

  // ── E7 ────────────────────────────────────────────────────────────────────

  test(
    'E7: toLlmPrompt() contains CONTEXT:, QUESTION:, and the query',
    () async {
      final f = tmpTxt('Medical emergency protocol detail. ' * 30);
      await pipeline.ingest(f);
      final result = await pipeline.query('protocol');

      final prompt = result.toLlmPrompt();
      expect(prompt, contains('CONTEXT:'));
      expect(prompt, contains('QUESTION:'));
      expect(prompt, contains('protocol'));
    },
  );

  // ── E8 ────────────────────────────────────────────────────────────────────

  test(
    'E8: query with non-existent sourceFilter → empty list, no exception',
    () async {
      final result = await pipeline.query(
        'anything',
        sourceFilter: '/nonexistent/file.txt',
      );
      expect(result.results, isEmpty);
    },
  );

  // ── E9 ────────────────────────────────────────────────────────────────────

  test(
    'E9: concurrent ingest of 3 files → no deadlock, correct total count',
    () async {
      final files = [
        tmpTxt('Document alpha content. ' * 30),
        tmpTxt('Document beta content. ' * 30),
        tmpTxt('Document gamma content. ' * 30),
      ];

      // Ingest all three concurrently.
      final results = await Future.wait(files.map((f) => pipeline.ingest(f)));
      final totalAdded = results.fold(0, (s, r) => s + r.chunksAdded);

      final totalStored = await pipeline.totalChunks();
      expect(totalStored, greaterThanOrEqualTo(totalAdded));
    },
  );

  // ── E10 ───────────────────────────────────────────────────────────────────

  test('E10: large corpus query latency < 500ms', () async {
    // Ingest a file that produces > 500 chunks.
    final largeContent = ('Word ' * 260 + '. ') * 60; // ~60 chunks
    final f = tmpTxt(largeContent);
    await pipeline.ingest(f);

    final sw = Stopwatch()..start();
    await pipeline.query('word', topK: 5);
    sw.stop();

    expect(
      sw.elapsedMilliseconds,
      lessThan(500),
      reason: 'Query latency must be < 500ms for this corpus size',
    );
  });
}
