// lib/offline_data.dart

/// Rescate Offline Data package.
///
/// Provides shared, offline-first data infrastructure for all Rescate packages:
///
/// - **[VectorStore]** — SQLite-backed semantic vector store (Float32List BLOB,
///   cosine similarity, flat IVF index, namespace isolation).
/// - **[VectorEntry]** — Unit of data stored in the [VectorStore].
/// - **[VectorSearchResult]** — A matched [VectorEntry] with its similarity score.
/// - **[VectorStoreException]** — Typed exception thrown by [VectorStore].
///
/// Future additions: SQLite FTS5 full-text search, ObjectBox, MBTiles.
library offline_data;

export 'vector_store/vector_entry.dart';
export 'vector_store/vector_search_result.dart';
export 'vector_store/vector_store.dart';
export 'measurement_store/measurement_store.dart';
