// test/vector_store_test.dart

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:offline_data/offline_data.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

/// Creates a unit-length random vector of [dim] dimensions seeded by [seed].
List<double> _randomVec(int dim, int seed) {
  final rng = math.Random(seed);
  final raw = List<double>.generate(dim, (_) => rng.nextDouble() * 2 - 1);
  final norm = math.sqrt(raw.fold(0.0, (s, v) => s + v * v));
  return raw.map((v) => v / norm).toList();
}

/// Returns a unit vector pointing along axis [axis] in [dim] dimensions.
List<double> _basisVec(int dim, int axis) {
  final v = List<double>.filled(dim, 0.0);
  v[axis] = 1.0;
  return v;
}

/// Opens a fresh in-memory VectorStore for testing.
Future<VectorStore> _openTestStore() => VectorStore.open(dbName: ':memory:');

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  // Use sqflite_common_ffi so tests run on the host (Linux/macOS/Windows).
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  const kDim = 8; // Small dimension for fast tests

  group('VectorStore', () {
    late VectorStore store;

    setUp(() async {
      store = await _openTestStore();
    });

    tearDown(() async {
      await store.clear();
      await store.close();
    });

    // ── B1 ────────────────────────────────────────────────────────────────────

    test('B1: cosine similarity of a vector with itself equals 1.0', () async {
      final vec = _randomVec(kDim, 1);
      await store.upsert(
        VectorEntry(id: 'b1', namespace: 'test', payload: {}, embedding: vec),
      );

      final results = await store.search(vec, topK: 1, namespace: 'test');

      expect(results, hasLength(1));
      expect(results.first.score, closeTo(1.0, 0.001));
    });

    // ── B2 ────────────────────────────────────────────────────────────────────

    test('B2: orthogonal vectors — querying with one ranks it first, '
        'other has score ~0', () async {
      // Use two orthogonal basis vectors.
      final vecA = _basisVec(kDim, 0); // [1,0,0,0,0,0,0,0]
      final vecB = _basisVec(kDim, 1); // [0,1,0,0,0,0,0,0]

      await store.upsertBatch([
        VectorEntry(
          id: 'ortho-a',
          namespace: 'test',
          payload: {},
          embedding: vecA,
        ),
        VectorEntry(
          id: 'ortho-b',
          namespace: 'test',
          payload: {},
          embedding: vecB,
        ),
      ]);

      final results = await store.search(vecA, topK: 2, namespace: 'test');

      expect(results.first.entry.id, equals('ortho-a'));
      expect(results.first.score, closeTo(1.0, 0.001));
      expect(
        results.last.score,
        closeTo(0.0, 0.001),
        reason: 'Orthogonal vector should have ~0 cosine similarity',
      );
    });

    // ── B3 ────────────────────────────────────────────────────────────────────

    test('B3: 100 chunks inserted → topK=5 returns exactly 5 results '
        'sorted descending', () async {
      final queryVec = _randomVec(kDim, 999);
      final entries = List.generate(
        100,
        (i) => VectorEntry(
          id: 'chunk-$i',
          namespace: 'test',
          payload: {'index': i},
          embedding: _randomVec(kDim, i),
        ),
      );
      await store.upsertBatch(entries);
      // Also insert the query itself so there is at least one score=1.0.
      await store.upsert(
        VectorEntry(
          id: 'query-exact',
          namespace: 'test',
          payload: {},
          embedding: queryVec,
        ),
      );

      final results = await store.search(queryVec, topK: 5, namespace: 'test');

      expect(results, hasLength(5));
      for (var i = 0; i < results.length - 1; i++) {
        expect(
          results[i].score,
          greaterThanOrEqualTo(results[i + 1].score),
          reason: 'Results must be sorted by score descending',
        );
      }
    });

    // ── B4 ────────────────────────────────────────────────────────────────────

    test('B4: upserting the same ID twice keeps count at 1', () async {
      final entry = VectorEntry(
        id: 'dedup',
        namespace: 'test',
        payload: {'v': 1},
        embedding: _randomVec(kDim, 42),
      );
      await store.upsert(entry);
      await store.upsert(entry.copyWith(payload: {'v': 2}));

      final c = await store.count(namespace: 'test');
      expect(c, equals(1));
    });

    // ── B5 ────────────────────────────────────────────────────────────────────

    test(
      'B5: deleteNamespace removes all entries for that namespace',
      () async {
        await store.upsertBatch([
          VectorEntry(
            id: 'd1',
            namespace: 'ns-file',
            payload: {},
            embedding: _randomVec(kDim, 1),
          ),
          VectorEntry(
            id: 'd2',
            namespace: 'ns-file',
            payload: {},
            embedding: _randomVec(kDim, 2),
          ),
          VectorEntry(
            id: 'd3',
            namespace: 'ns-other',
            payload: {},
            embedding: _randomVec(kDim, 3),
          ),
        ]);

        expect(await store.count(namespace: 'ns-file'), equals(2));
        await store.deleteNamespace('ns-file');

        expect(await store.count(namespace: 'ns-file'), equals(0));
        expect(
          await store.count(namespace: 'ns-other'),
          equals(1),
          reason: 'Other namespace must be unaffected',
        );
      },
    );

    // ── B6 ────────────────────────────────────────────────────────────────────

    test(
      'B6: search on empty DB returns empty list without throwing',
      () async {
        expect(
          () async => store.search(_randomVec(kDim, 7), namespace: 'empty'),
          returnsNormally,
        );
        final results = await store.search(
          _randomVec(kDim, 7),
          namespace: 'empty',
        );
        expect(results, isEmpty);
      },
    );

    // ── B7 ────────────────────────────────────────────────────────────────────

    test('B7: clear() makes chunkCount = 0', () async {
      await store.upsertBatch([
        VectorEntry(
          id: 'c1',
          namespace: 'test',
          payload: {},
          embedding: _randomVec(kDim, 1),
        ),
        VectorEntry(
          id: 'c2',
          namespace: 'test',
          payload: {},
          embedding: _randomVec(kDim, 2),
        ),
      ]);
      expect(await store.count(), greaterThan(0));

      await store.clear();
      expect(await store.count(), equals(0));
    });

    // ── B8 ────────────────────────────────────────────────────────────────────

    test('B8: minScore filter returns only entries above threshold', () async {
      // Insert two orthogonal basis vectors plus the query vector itself.
      final queryVec = _basisVec(kDim, 0); // score = 1.0
      final nearVec = _normalise([0.9, 0.43, 0, 0, 0, 0, 0, 0]); // cos ~ 0.9
      final farVec = _basisVec(kDim, 1); // cos = 0.0

      await store.upsertBatch([
        VectorEntry(
          id: 'near',
          namespace: 'test',
          payload: {},
          embedding: nearVec,
        ),
        VectorEntry(
          id: 'far',
          namespace: 'test',
          payload: {},
          embedding: farVec,
        ),
      ]);
      await store.upsert(
        VectorEntry(
          id: 'exact',
          namespace: 'test',
          payload: {},
          embedding: queryVec,
        ),
      );

      final results = await store.search(
        queryVec,
        minScore: 0.5,
        topK: 10,
        namespace: 'test',
      );

      for (final r in results) {
        expect(
          r.score,
          greaterThanOrEqualTo(0.5),
          reason: 'All results must meet minScore threshold',
        );
      }
      expect(
        results.every((r) => r.entry.id != 'far'),
        isTrue,
        reason: 'Orthogonal vector must be excluded by minScore',
      );
    });

    // ── B9 ────────────────────────────────────────────────────────────────────

    test(
      'B9: namespace filter — results only from queried namespace',
      () async {
        final vec = _randomVec(kDim, 55);
        await store.upsertBatch([
          VectorEntry(
            id: 'ns1-a',
            namespace: 'ns1',
            payload: {},
            embedding: vec,
          ),
          VectorEntry(
            id: 'ns2-a',
            namespace: 'ns2',
            payload: {},
            embedding: vec,
          ),
        ]);

        final results = await store.search(vec, topK: 10, namespace: 'ns1');
        expect(results, isNotEmpty);
        for (final r in results) {
          expect(r.entry.namespace, equals('ns1'));
        }
      },
    );

    // ── B10 ───────────────────────────────────────────────────────────────────

    test('B10: SQLite persistence — data survives close and reopen', () async {
      // Use an absolute path so VectorStore.open doesn't invoke path_provider.
      final dbName = p.join(
        Directory.systemTemp.path,
        'test_persist_${DateTime.now().millisecondsSinceEpoch}.db',
      );
      final s1 = await VectorStore.open(dbName: dbName);
      final vec = _randomVec(kDim, 77);

      await s1.upsert(
        VectorEntry(
          id: 'persist-me',
          namespace: 'ptest',
          payload: {'key': 'value'},
          embedding: vec,
        ),
      );
      await s1.close();

      final s2 = await VectorStore.open(dbName: dbName);
      final c = await s2.count(namespace: 'ptest');
      expect(c, equals(1));

      final results = await s2.search(vec, topK: 1, namespace: 'ptest');
      expect(results.first.entry.id, equals('persist-me'));
      expect(results.first.entry.payload['key'], equals('value'));

      await s2.clear();
      await s2.close();
    });
  });
}

// ─── Test helpers ─────────────────────────────────────────────────────────────

List<double> _normalise(List<double> v) {
  final norm = math.sqrt(v.fold(0.0, (s, x) => s + x * x));
  return norm == 0 ? v : v.map((x) => x / norm).toList();
}

extension _VectorEntryX on VectorEntry {
  VectorEntry copyWith({
    String? id,
    String? namespace,
    Map<String, dynamic>? payload,
    List<double>? embedding,
  }) => VectorEntry(
    id: id ?? this.id,
    namespace: namespace ?? this.namespace,
    payload: payload ?? this.payload,
    embedding: embedding ?? this.embedding,
  );
}
