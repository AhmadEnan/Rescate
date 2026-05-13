// lib/vector_store/vector_search_result.dart

import 'vector_entry.dart';

/// The result of a [VectorStore.search] call: a retrieved [entry] paired with
/// its cosine similarity [score] against the query vector.
///
/// Results are returned in **descending score order** (most similar first).
class VectorSearchResult {
  /// The matched entry from the [VectorStore].
  final VectorEntry entry;

  /// Cosine similarity between the query vector and [entry.embedding].
  ///
  /// Range: `[−1.0, 1.0]`. For unit-length vectors this equals the dot
  /// product. A score of `1.0` means the vectors are identical; `0.0` means
  /// orthogonal.
  final double score;

  /// Creates a [VectorSearchResult].
  const VectorSearchResult({required this.entry, required this.score});

  @override
  String toString() =>
      'VectorSearchResult(id: ${entry.id}, score: ${score.toStringAsFixed(4)})';
}
