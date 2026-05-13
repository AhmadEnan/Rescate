// lib/vector_store/vector_store.dart

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'vector_entry.dart';
import 'vector_search_result.dart';

// ─── Constants ──────────────────────────────────────────────────────────────

/// Default SQLite database file name (dedicated file — no schema collision risk
/// with FTS5 / ObjectBox work that lives in a separate DB).
const _kDefaultDbName = 'rescate_vectors.db';

/// Number of rows read per DB batch during a linear scan.
/// Keeps peak RSS bounded even for very large corpora.
const _kScanBatchSize = 500;

/// Below this threshold, use a simple linear scan.
/// Above it, use a flat IVF index.
const _kIvfThreshold = 10000;

/// Number of IVF buckets used when the corpus exceeds [_kIvfThreshold].
/// Set to sqrt(N) at index-build time, capped at a sensible maximum.
const _kIvfMaxBuckets = 200;

/// Number of IVF buckets to probe at query time.
const _kIvfProbes = 3;

// ─── Isolate message types ───────────────────────────────────────────────────

/// Message sent to the scan isolate.
class _ScanMessage {
  final List<List<double>> embeddings;
  final List<double> query;
  final int topK;
  final double minScore;
  final List<String> ids;
  const _ScanMessage({
    required this.embeddings,
    required this.query,
    required this.topK,
    required this.minScore,
    required this.ids,
  });
}

// ─── VectorStore ─────────────────────────────────────────────────────────────

/// A persistent, SQLite-backed vector store for semantic similarity search.
///
/// ### Usage
/// ```dart
/// final store = await VectorStore.open();
/// await store.upsert(VectorEntry(
///   id: 'doc-1',
///   namespace: 'rag:notes.pdf',
///   payload: {'page': 1},
///   embedding: myEmbeddingVector,
/// ));
/// final results = await store.search(queryEmbedding, topK: 5);
/// ```
///
/// ### Scaling behaviour
/// - ≤ [_kIvfThreshold] entries: linear cosine scan (batched, Isolate).
/// - > [_kIvfThreshold] entries: flat IVF index (k-means centroids in SQLite,
///   only top-[_kIvfProbes] buckets probed per query).
///
/// ### Thread safety
/// All database access is through a single [Database] object. sqflite
/// serialises concurrent writes internally; batch operations are always
/// wrapped in explicit transactions for speed and atomicity.
class VectorStore {
  VectorStore._(this._db);

  final Database _db;

  // ── Factory ────────────────────────────────────────────────────────────────

  /// Opens (or creates) the vector store database.
  ///
  /// [dbName] defaults to [_kDefaultDbName] (`rescate_vectors.db`) in the
  /// application documents directory. Provide a different name to isolate
  /// test databases from production data.
  static Future<VectorStore> open({String dbName = _kDefaultDbName}) async {
    final String path;
    if (dbName == inMemoryDatabasePath) {
      path = inMemoryDatabasePath;
    } else if (p.isAbsolute(dbName)) {
      path = dbName;
    } else {
      final dir = await getApplicationDocumentsDirectory();
      path = p.join(dir.path, dbName);
    }
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: _createSchema,
      onConfigure: (db) async {
        // Enable WAL mode for better concurrent read performance.
        await db.execute('PRAGMA journal_mode=WAL;');
        await db.execute('PRAGMA synchronous=NORMAL;');
      },
    );
    return VectorStore._(db);
  }

  static Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS vectors (
        id        TEXT     NOT NULL,
        namespace TEXT     NOT NULL DEFAULT 'default',
        payload   TEXT,
        embedding BLOB     NOT NULL,
        PRIMARY KEY (id, namespace)
      );
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ns ON vectors(namespace);',
    );

    // IVF centroid table — populated on demand when corpus > threshold.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ivf_centroids (
        namespace TEXT    NOT NULL,
        bucket_id INTEGER NOT NULL,
        centroid  BLOB    NOT NULL,
        PRIMARY KEY (namespace, bucket_id)
      );
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ivf_assignments (
        id        TEXT    NOT NULL,
        namespace TEXT    NOT NULL,
        bucket_id INTEGER NOT NULL,
        PRIMARY KEY (id, namespace)
      );
    ''');
  }

  // ── Write operations ───────────────────────────────────────────────────────

  /// Inserts or replaces a single [entry].
  ///
  /// Uses `INSERT OR REPLACE` semantics — if an entry with the same `(id,
  /// namespace)` already exists it is overwritten.
  Future<void> upsert(VectorEntry entry) async {
    try {
      await _db.insert(
        'vectors',
        entry.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } on DatabaseException catch (e) {
      throw VectorStoreException('upsert failed for id=${entry.id}', cause: e);
    }
  }

  /// Inserts or replaces [entries] in a single SQLite transaction.
  ///
  /// Always prefer this over calling [upsert] in a loop — it is orders of
  /// magnitude faster for bulk ingestion.
  Future<void> upsertBatch(List<VectorEntry> entries) async {
    if (entries.isEmpty) return;
    try {
      await _db.transaction((txn) async {
        final batch = txn.batch();
        for (final entry in entries) {
          batch.insert(
            'vectors',
            entry.toRow(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      });
    } on DatabaseException catch (e) {
      throw VectorStoreException(
        'upsertBatch failed (${entries.length} entries)',
        cause: e,
      );
    }
  }

  /// Removes the entry with the given [id] from [namespace].
  Future<void> delete(String id, {String namespace = 'default'}) async {
    try {
      await _db.delete(
        'vectors',
        where: 'id = ? AND namespace = ?',
        whereArgs: [id, namespace],
      );
    } on DatabaseException catch (e) {
      throw VectorStoreException('delete failed for id=$id', cause: e);
    }
  }

  /// Returns a list of all unique namespaces currently present in the store.
  Future<List<String>> listNamespaces() async {
    try {
      final rows = await _db.rawQuery('SELECT DISTINCT namespace FROM vectors');
      return rows.map((r) => r['namespace'] as String).toList();
    } on DatabaseException catch (e) {
      throw VectorStoreException('listNamespaces failed', cause: e);
    }
  }

  /// Removes **all** entries in [namespace] (e.g. all chunks for one source
  /// document) and invalidates its IVF index.
  Future<void> deleteNamespace(String namespace) async {
    try {
      await _db.transaction((txn) async {
        await txn.delete(
          'vectors',
          where: 'namespace = ?',
          whereArgs: [namespace],
        );
        await txn.delete(
          'ivf_centroids',
          where: 'namespace = ?',
          whereArgs: [namespace],
        );
        await txn.delete(
          'ivf_assignments',
          where: 'namespace = ?',
          whereArgs: [namespace],
        );
      });
    } on DatabaseException catch (e) {
      throw VectorStoreException(
        'deleteNamespace failed for namespace=$namespace',
        cause: e,
      );
    }
  }

  /// Removes every entry across all namespaces. Use with care.
  Future<void> clear() async {
    try {
      await _db.transaction((txn) async {
        await txn.delete('vectors');
        await txn.delete('ivf_centroids');
        await txn.delete('ivf_assignments');
      });
    } on DatabaseException catch (e) {
      throw VectorStoreException('clear failed', cause: e);
    }
  }

  // ── Read operations ────────────────────────────────────────────────────────

  /// Returns the number of entries in [namespace], or the total if null.
  Future<int> count({String? namespace}) async {
    try {
      final List<Map<String, dynamic>> rows;
      if (namespace != null) {
        rows = await _db.rawQuery(
          'SELECT COUNT(*) AS c FROM vectors WHERE namespace = ?',
          [namespace],
        );
      } else {
        rows = await _db.rawQuery('SELECT COUNT(*) AS c FROM vectors');
      }
      return (rows.first['c'] as int?) ?? 0;
    } on DatabaseException catch (e) {
      throw VectorStoreException('count failed', cause: e);
    }
  }

  /// Performs a semantic similarity search against [namespace].
  ///
  /// Returns up to [topK] [VectorSearchResult]s with cosine similarity ≥
  /// [minScore], sorted in descending score order.
  ///
  /// - For corpora ≤ [_kIvfThreshold] entries: linear scan in an Isolate.
  /// - For larger corpora: probes the top [_kIvfProbes] IVF buckets only.
  Future<List<VectorSearchResult>> search(
    List<double> queryEmbedding, {
    int topK = 5,
    double minScore = 0.0,
    String namespace = 'default',
  }) async {
    if (queryEmbedding.isEmpty) return [];

    try {
      final total = await count(namespace: namespace);
      if (total == 0) return [];

      if (total <= _kIvfThreshold) {
        return _linearSearch(queryEmbedding, topK, minScore, namespace);
      } else {
        return _ivfSearch(queryEmbedding, topK, minScore, namespace);
      }
    } on DatabaseException catch (e) {
      throw VectorStoreException('search failed', cause: e);
    }
  }

  // ── Linear scan ───────────────────────────────────────────────────────────

  Future<List<VectorSearchResult>> _linearSearch(
    List<double> query,
    int topK,
    double minScore,
    String namespace,
  ) async {
    // Read all embeddings from DB in batches of _kScanBatchSize to bound RAM.
    final allIds = <String>[];
    final allEmbeddings = <List<double>>[];

    int offset = 0;
    while (true) {
      final rows = await _db.query(
        'vectors',
        columns: ['id', 'embedding'],
        where: 'namespace = ?',
        whereArgs: [namespace],
        limit: _kScanBatchSize,
        offset: offset,
      );
      if (rows.isEmpty) break;
      for (final row in rows) {
        allIds.add(row['id'] as String);
        final blob = row['embedding'] as Uint8List;
        final f32 = Float32List.view(blob.buffer, blob.offsetInBytes);
        allEmbeddings.add(List<double>.generate(f32.length, (i) => f32[i]));
      }
      offset += rows.length;
      if (rows.length < _kScanBatchSize) break;
    }

    // Run cosine similarity in a separate Isolate to keep UI thread free.
    final encodedResults = await compute(
      _cosineScanIsolate,
      _ScanMessage(
        embeddings: allEmbeddings,
        query: query,
        topK: topK,
        minScore: minScore,
        ids: allIds,
      ),
    );

    return _fetchResults(encodedResults, namespace);
  }

  /// Isolate entry point — pure function, no DB access.
  ///
  /// Returns a list of `'id:score'` strings so the calling isolate can
  /// reconstruct both the ranked order and the similarity scores without a
  /// second round-trip.
  static List<String> _cosineScanIsolate(_ScanMessage msg) {
    final scored = <_Scored>[];
    for (var i = 0; i < msg.embeddings.length; i++) {
      final score = _cosine(msg.query, msg.embeddings[i]);
      if (score >= msg.minScore) {
        scored.add(_Scored(msg.ids[i], score));
      }
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    // Encode as 'id::score' — IDs never contain '::'.
    return scored.take(msg.topK).map((s) => '${s.id}::${s.score}').toList();
  }

  // ── IVF search ────────────────────────────────────────────────────────────

  Future<List<VectorSearchResult>> _ivfSearch(
    List<double> query,
    int topK,
    double minScore,
    String namespace,
  ) async {
    // Ensure index is built.
    await _ensureIvfIndex(namespace);

    // Load centroids and identify top-K buckets to probe.
    final centroidRows = await _db.query(
      'ivf_centroids',
      columns: ['bucket_id', 'centroid'],
      where: 'namespace = ?',
      whereArgs: [namespace],
    );

    final bucketScores = <int, double>{};
    for (final row in centroidRows) {
      final blob = row['centroid'] as Uint8List;
      final f32 = Float32List.view(blob.buffer, blob.offsetInBytes);
      final centroid = List<double>.generate(f32.length, (i) => f32[i]);
      final score = _cosine(query, centroid);
      bucketScores[row['bucket_id'] as int] = score;
    }

    final sortedBuckets = bucketScores.keys.toList()
      ..sort((a, b) => bucketScores[b]!.compareTo(bucketScores[a]!));
    final probeBuckets = sortedBuckets.take(_kIvfProbes).toList();

    // Gather candidate IDs from those buckets.
    final placeholders = probeBuckets.map((_) => '?').join(',');
    final assignRows = await _db.rawQuery(
      'SELECT id FROM ivf_assignments '
      'WHERE namespace = ? AND bucket_id IN ($placeholders)',
      [namespace, ...probeBuckets],
    );
    final candidateIds = assignRows.map((r) => r['id'] as String).toList();

    if (candidateIds.isEmpty) return [];

    // Fetch their full embeddings.
    final idPlaceholders = candidateIds.map((_) => '?').join(',');
    final vecRows = await _db.rawQuery(
      'SELECT id, embedding FROM vectors '
      'WHERE namespace = ? AND id IN ($idPlaceholders)',
      [namespace, ...candidateIds],
    );

    final ids = <String>[];
    final embeddings = <List<double>>[];
    for (final row in vecRows) {
      ids.add(row['id'] as String);
      final blob = row['embedding'] as Uint8List;
      final f32 = Float32List.view(blob.buffer, blob.offsetInBytes);
      embeddings.add(List<double>.generate(f32.length, (i) => f32[i]));
    }

    final encodedResults = await compute(
      _cosineScanIsolate,
      _ScanMessage(
        embeddings: embeddings,
        query: query,
        topK: topK,
        minScore: minScore,
        ids: ids,
      ),
    );

    return _fetchResults(encodedResults, namespace);
  }

  Future<void> _ensureIvfIndex(String namespace) async {
    final existing = await _db.query(
      'ivf_centroids',
      where: 'namespace = ?',
      whereArgs: [namespace],
      limit: 1,
    );
    if (existing.isNotEmpty) return; // Already built.
    await _buildIvfIndex(namespace);
  }

  Future<void> _buildIvfIndex(String namespace) async {
    final total = await count(namespace: namespace);
    final k = math.min(math.sqrt(total.toDouble()).ceil(), _kIvfMaxBuckets);

    // Load all embeddings for k-means.
    final rows = await _db.query(
      'vectors',
      columns: ['id', 'embedding'],
      where: 'namespace = ?',
      whereArgs: [namespace],
    );

    final ids = <String>[];
    final embeddings = <List<double>>[];
    for (final row in rows) {
      ids.add(row['id'] as String);
      final blob = row['embedding'] as Uint8List;
      final f32 = Float32List.view(blob.buffer, blob.offsetInBytes);
      embeddings.add(List<double>.generate(f32.length, (i) => f32[i]));
    }

    // k-means (10 iterations, random init) — run off-thread.
    final result = await compute(
      _kMeansIsolate,
      _KMeansMessage(embeddings: embeddings, ids: ids, k: k),
    );

    // Persist centroids and assignments.
    await _db.transaction((txn) async {
      final batch = txn.batch();
      for (var b = 0; b < result.centroids.length; b++) {
        final f32 = Float32List.fromList(result.centroids[b]);
        batch.insert('ivf_centroids', {
          'namespace': namespace,
          'bucket_id': b,
          'centroid': f32.buffer.asUint8List(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (var i = 0; i < ids.length; i++) {
        batch.insert('ivf_assignments', {
          'id': ids[i],
          'namespace': namespace,
          'bucket_id': result.assignments[i],
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  static _KMeansResult _kMeansIsolate(_KMeansMessage msg) {
    final rng = math.Random(42);
    final k = msg.k;
    final n = msg.embeddings.length;
    final dim = msg.embeddings.first.length;

    // Random initialisation.
    final centroidIdxs = <int>{};
    while (centroidIdxs.length < k) {
      centroidIdxs.add(rng.nextInt(n));
    }
    final centroids = centroidIdxs
        .map((i) => List<double>.from(msg.embeddings[i]))
        .toList();
    final assignments = List<int>.filled(n, 0);

    for (var iter = 0; iter < 10; iter++) {
      // Assignment step.
      for (var i = 0; i < n; i++) {
        var bestBucket = 0;
        var bestScore = double.negativeInfinity;
        for (var b = 0; b < centroids.length; b++) {
          final s = _cosine(msg.embeddings[i], centroids[b]);
          if (s > bestScore) {
            bestScore = s;
            bestBucket = b;
          }
        }
        assignments[i] = bestBucket;
      }

      // Update step.
      final newCentroids = List.generate(k, (_) => List<double>.filled(dim, 0));
      final counts = List<int>.filled(k, 0);
      for (var i = 0; i < n; i++) {
        final b = assignments[i];
        counts[b]++;
        for (var d = 0; d < dim; d++) {
          newCentroids[b][d] += msg.embeddings[i][d];
        }
      }
      for (var b = 0; b < k; b++) {
        if (counts[b] > 0) {
          for (var d = 0; d < dim; d++) {
            newCentroids[b][d] /= counts[b];
          }
          centroids[b] = newCentroids[b];
        }
      }
    }

    return _KMeansResult(centroids: centroids, assignments: assignments);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<List<VectorSearchResult>> _fetchResults(
    List<String> encodedPairs,
    String namespace,
  ) async {
    if (encodedPairs.isEmpty) return [];

    // Parse the 'id::score' pairs returned by _cosineScanIsolate.
    final parsedPairs = <(String id, double score)>[];
    for (final pair in encodedPairs) {
      final sep = pair.lastIndexOf('::');
      if (sep < 0) continue;
      final id = pair.substring(0, sep);
      final score = double.tryParse(pair.substring(sep + 2)) ?? 0.0;
      parsedPairs.add((id, score));
    }

    final ids = parsedPairs.map((p) => p.$1).toList();
    final placeholders = ids.map((_) => '?').join(',');
    final rows = await _db.rawQuery(
      'SELECT * FROM vectors WHERE namespace = ? AND id IN ($placeholders)',
      [namespace, ...ids],
    );
    final byId = {
      for (final row in rows)
        row['id'] as String: VectorEntry.fromRow(row.cast<String, dynamic>()),
    };

    // Preserve the cosine-similarity order from the isolate.
    return parsedPairs
        .where((p) => byId.containsKey(p.$1))
        .map((p) => VectorSearchResult(entry: byId[p.$1]!, score: p.$2))
        .toList();
  }

  /// Computes the cosine similarity between two vectors.
  ///
  /// Both must be unit-length for the result to equal the dot product.
  static double _cosine(List<double> a, List<double> b) {
    assert(a.length == b.length, 'Vector dimension mismatch');
    var dot = 0.0;
    var normA = 0.0;
    var normB = 0.0;
    final len = math.min(a.length, b.length);
    for (var i = 0; i < len; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    final denom = math.sqrt(normA) * math.sqrt(normB);
    if (denom == 0) return 0;
    return dot / denom;
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Closes the underlying SQLite database.
  ///
  /// The [VectorStore] must not be used after calling [close].
  Future<void> close() async {
    await _db.close();
  }
}

// ─── Private helpers ─────────────────────────────────────────────────────────

class _Scored {
  final String id;
  final double score;
  const _Scored(this.id, this.score);
}

class _KMeansMessage {
  final List<List<double>> embeddings;
  final List<String> ids;
  final int k;
  const _KMeansMessage({
    required this.embeddings,
    required this.ids,
    required this.k,
  });
}

class _KMeansResult {
  final List<List<double>> centroids;
  final List<int> assignments;
  const _KMeansResult({required this.centroids, required this.assignments});
}

/// Exception thrown by [VectorStore] on any database or logic error.
class VectorStoreException implements Exception {
  /// Human-readable description of what went wrong.
  final String message;

  /// Optional underlying error (e.g. [DatabaseException]).
  final Object? cause;

  /// Creates a [VectorStoreException].
  const VectorStoreException(this.message, {this.cause});

  @override
  String toString() =>
      'VectorStoreException: $message${cause != null ? ' (cause: $cause)' : ''}';
}
