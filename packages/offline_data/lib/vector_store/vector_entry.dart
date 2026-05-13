// lib/vector_store/vector_entry.dart

import 'dart:convert';
import 'dart:typed_data';

/// A single entry that can be stored in the [VectorStore].
///
/// [id] must be unique within a [namespace]. The [payload] map can carry
/// arbitrary JSON-serialisable metadata (e.g. source file, page number,
/// chunk index). [embedding] is the raw, L2-normalised float vector produced
/// by an embedding model.
///
/// ### Namespace strategy
/// Use a descriptive namespace string to isolate logical collections:
/// ```dart
/// VectorEntry(id: '...', namespace: 'rag:report.pdf', payload: {}, embedding: [...])
/// ```
class VectorEntry {
  /// Unique identifier for this entry within its [namespace].
  final String id;

  /// Logical collection this entry belongs to.
  ///
  /// Defaults to `'default'` so callers that don't need multi-tenancy don't
  /// have to specify one.
  final String namespace;

  /// Arbitrary metadata stored alongside the vector.
  ///
  /// Must contain only JSON-serialisable values. Stored as a JSON TEXT column
  /// in SQLite so consumers can inspect metadata without touching the BLOB.
  final Map<String, dynamic> payload;

  /// L2-normalised embedding vector for this entry.
  ///
  /// Must be non-empty. The [VectorStore] does **not** normalise vectors
  /// automatically — callers are responsible for unit-length vectors to ensure
  /// cosine similarity is computed correctly.
  final List<double> embedding;

  /// Creates a [VectorEntry].
  const VectorEntry({
    required this.id,
    this.namespace = 'default',
    required this.payload,
    required this.embedding,
  });

  // ─── Serialisation ────────────────────────────────────────────────────────

  /// Serialises [embedding] to a [Uint8List] BLOB (Float32List bytes).
  ///
  /// Storing as raw bytes rather than a JSON array is ~4× more compact and
  /// avoids JSON-parsing overhead on every read.
  Uint8List get embeddingBytes {
    final f32 = Float32List(embedding.length);
    for (var i = 0; i < embedding.length; i++) {
      f32[i] = embedding[i];
    }
    return f32.buffer.asUint8List();
  }

  /// Reconstructs a [VectorEntry] from a raw SQLite row map.
  factory VectorEntry.fromRow(Map<String, dynamic> row) {
    final blob = row['embedding'] as Uint8List;
    final f32 = Float32List.view(blob.buffer, blob.offsetInBytes);
    Map<String, dynamic> decodedPayload;
    try {
      decodedPayload = (jsonDecode(row['payload'] as String? ?? '{}') as Map)
          .cast<String, dynamic>();
    } catch (_) {
      decodedPayload = {};
    }
    return VectorEntry(
      id: row['id'] as String,
      namespace: (row['namespace'] as String?) ?? 'default',
      payload: decodedPayload,
      embedding: List<double>.generate(f32.length, (i) => f32[i]),
    );
  }

  /// Converts this entry to a SQLite row map suitable for [sqflite] insert /
  /// update calls.
  Map<String, dynamic> toRow() {
    return {
      'id': id,
      'namespace': namespace,
      'payload': jsonEncode(payload),
      'embedding': embeddingBytes,
    };
  }
}
