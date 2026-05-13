// lib/rag/pipeline.dart

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:offline_data/offline_data.dart';

import 'embedder.dart';
import 'exceptions.dart';
import 'models.dart';
import 'parsers/parser_registry.dart';

/// Orchestrates the full offline RAG pipeline.
///
/// ### Typical usage
/// ```dart
/// final pipeline = RagPipeline(
///   store: await VectorStore.open(),
///   embedder: MobileRagEmbedder(),
/// );
/// await pipeline.initialize();
///
/// // Ingest a document
/// final result = await pipeline.ingest(
///   File('/path/to/report.pdf'),
///   onProgress: (p) => print('${(p * 100).toInt()}%'),
/// );
///
/// // Query the corpus
/// final q = await pipeline.query('What are the main findings?');
/// print(q.toLlmPrompt());
/// ```
class RagPipeline {
  /// The persistent vector store used for chunk storage and retrieval.
  final VectorStore store;

  /// The embedding backend (default: [MobileRagEmbedder]).
  final RagEmbedder embedder;

  /// Maximum number of results returned per [query] call.
  final int defaultTopK;

  bool _initialised = false;

  /// Creates a [RagPipeline].
  ///
  /// [store] must already be open. [embedder] must be initialised via
  /// [initialize] before the first [ingest] or [query] call.
  RagPipeline({
    required this.store,
    required this.embedder,
    this.defaultTopK = 5,
  });

  /// Initialises the embedding model.
  ///
  /// Must be called once before [ingest] or [query].
  Future<void> initialize() async {
    if (_initialised) return;
    await embedder.initialize();
    _initialised = true;
  }

  // ── Ingestion ─────────────────────────────────────────────────────────────

  /// Parses [file], chunks and embeds its text, and persists vectors to
  /// [store].
  ///
  /// Returns a [RagIngestionResult] with the number of new chunks added.
  ///
  /// [onProgress] receives values in `[0.0, 1.0]`; it is called at each
  /// major pipeline stage. The final call is always `1.0`.
  ///
  /// Throws [RagParseException] if the file cannot be parsed.
  /// Throws [RagEmbedException] if embedding fails.
  /// Throws [RagStoreException] if persistence fails.
  Future<RagIngestionResult> ingest(
    File file, {
    void Function(double progress)? onProgress,
  }) async {
    _assertInitialised();
    final sw = Stopwatch()..start();

    // ── Step 1: Parse ────────────────────────────────────────────────────
    onProgress?.call(0.0);
    final String rawText;
    try {
      final parser = ParserRegistry.instance.parserFor(file);
      rawText = await parser.parse(file);
    } on RagParseException {
      rethrow;
    } on UnsupportedFormatException {
      rethrow;
    } catch (e) {
      throw RagParseException('Parsing failed for ${file.path}', cause: e);
    }

    if (rawText.trim().isEmpty) {
      onProgress?.call(1.0);
      return RagIngestionResult(
        chunksAdded: 0,
        totalChunks: 0,
        elapsedMs: sw.elapsedMilliseconds,
      );
    }
    onProgress?.call(0.15);

    // ── Step 2: Chunk via mobile_rag_engine ───────────────────────────────
    // mobile_rag_engine.addDocument() handles chunking internally but we need
    // the raw chunks for dedup + VectorStore storage. We use the raw text
    // with MobileRag for embedding while building our own RagChunk metadata.
    final List<String> rawChunks;
    try {
      rawChunks = _splitIntoChunks(rawText);
    } catch (e) {
      throw RagParseException('Chunking failed for ${file.path}', cause: e);
    }

    onProgress?.call(0.25);

    // ── Step 3: Deduplicate ───────────────────────────────────────────────
    final namespace = 'rag:${file.path}';
    final existingIds = await _existingIds(namespace);

    final newChunks = <RagChunk>[];
    for (var i = 0; i < rawChunks.length; i++) {
      final content = rawChunks[i];
      if (content.trim().isEmpty) continue;
      final id = _sha256(content);
      if (!existingIds.contains(id)) {
        newChunks.add(
          RagChunk(
            id: id,
            content: content,
            sourceFile: file.path,
            pageOrLine: -1, // Line tracking not available at this layer.
            chunkIndex: i,
            ingestedAt: DateTime.now(),
          ),
        );
      }
    }

    onProgress?.call(0.40);

    if (newChunks.isEmpty) {
      onProgress?.call(1.0);
      return RagIngestionResult(
        chunksAdded: 0,
        totalChunks: rawChunks.length,
        elapsedMs: sw.elapsedMilliseconds,
      );
    }

    // ── Step 4: Embed new chunks ──────────────────────────────────────────
    final texts = newChunks.map((c) => c.content).toList();
    final List<List<double>> embeddings;
    try {
      embeddings = await embedder.embedBatch(texts);
    } catch (e) {
      throw RagEmbedException('Batch embedding failed', cause: e);
    }

    onProgress?.call(0.80);

    // ── Step 5: Persist to VectorStore ────────────────────────────────────
    try {
      final entries = <VectorEntry>[];
      for (var i = 0; i < newChunks.length; i++) {
        final chunk = newChunks[i];
        entries.add(
          VectorEntry(
            id: chunk.id,
            namespace: namespace,
            payload: chunk.toPayload(),
            embedding: embeddings[i],
          ),
        );
      }
      await store.upsertBatch(entries);
    } catch (e) {
      throw RagStoreException(
        'Failed to persist chunks to VectorStore',
        cause: e,
      );
    }

    onProgress?.call(1.0);

    return RagIngestionResult(
      chunksAdded: newChunks.length,
      totalChunks: rawChunks.length,
      elapsedMs: sw.elapsedMilliseconds,
    );
  }

  // ── Query ─────────────────────────────────────────────────────────────────

  /// Embeds [userQuery] and retrieves the top-K most similar chunks.
  ///
  /// If [sourceFilter] is provided, only chunks from that source file are
  /// searched.
  ///
  /// Throws [RagEmbedException] if embedding fails.
  /// Throws [RagStoreException] if retrieval fails.
  Future<RagQueryResult> query(
    String userQuery, {
    int? topK,
    String? sourceFilter,
  }) async {
    _assertInitialised();

    final k = topK ?? defaultTopK;

    if (userQuery.trim().isEmpty) {
      return RagQueryResult(results: [], query: userQuery, retrievalMs: 0);
    }

    final sw = Stopwatch()..start();

    // Step 1: Embed the query (uses LRU cache internally).
    final List<double> queryVec;
    try {
      queryVec = await embedder.embed(userQuery);
    } catch (e) {
      throw RagEmbedException('Query embedding failed', cause: e);
    }

    // Step 2: Retrieve from VectorStore.
    final List<VectorSearchResult> raw;
    try {
      final namespace = sourceFilter != null ? 'rag:$sourceFilter' : 'default';

      if (sourceFilter != null) {
        raw = await store.search(queryVec, topK: k, namespace: namespace);
      } else {
        // Search across all rag:* namespaces.
        final namespaces = await store.listNamespaces();
        final allRaw = <VectorSearchResult>[];
        for (final ns in namespaces) {
          if (ns.startsWith('rag:')) {
            allRaw.addAll(await store.search(queryVec, topK: k, namespace: ns));
          }
        }
        allRaw.sort((a, b) => b.score.compareTo(a.score));
        raw = allRaw.take(k).toList();
      }
    } catch (e) {
      throw RagStoreException('Vector retrieval failed', cause: e);
    }

    final results = raw
        .map(
          (r) => RagResult(chunk: RagChunk.fromEntry(r.entry), score: r.score),
        )
        .toList();

    sw.stop();
    return RagQueryResult(
      results: results,
      query: userQuery,
      retrievalMs: sw.elapsedMilliseconds,
    );
  }

  // ── Source management ─────────────────────────────────────────────────────

  /// Removes all indexed chunks for [sourceFile] from the [VectorStore].
  Future<void> deleteSource(String sourceFile) async {
    try {
      await store.deleteNamespace('rag:$sourceFile');
    } catch (e) {
      throw RagStoreException('deleteSource failed for $sourceFile', cause: e);
    }
  }

  /// Returns the total number of chunks indexed across all sources.
  Future<int> totalChunks() => store.count();

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Naïve fixed-size chunker (256 words, 32-word overlap, ≥ 20 words).
  ///
  /// mobile_rag_engine handles its own internal chunking for addDocument(),
  /// but we need explicit chunks so we can dedup and store metadata.
  /// This produces deterministic chunk IDs via SHA-256.
  static List<String> _splitIntoChunks(
    String text, {
    int chunkSize = 256,
    int overlap = 32,
    int minChunk = 20,
  }) {
    // Sentence-boundary split if possible.
    final sentences = text.split(RegExp(r'(?<=[.!?])\s+'));
    final words = <String>[];
    for (final s in sentences) {
      words.addAll(s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty));
    }
    if (words.isEmpty) return [];

    final chunks = <String>[];
    var start = 0;
    while (start < words.length) {
      final end = (start + chunkSize).clamp(0, words.length);
      final slice = words.sublist(start, end);
      if (slice.length >= minChunk) {
        chunks.add(slice.join(' '));
      }
      if (end >= words.length) break;
      start = end - overlap;
    }
    return chunks;
  }

  /// Returns the set of entry IDs already present in [namespace].
  Future<Set<String>> _existingIds(String namespace) async {
    // VectorStore doesn't expose a listIds() method — use count as a fast
    // check. If 0, skip the full enumeration.
    final c = await store.count(namespace: namespace);
    if (c == 0) return {};

    // For dedup we query the DB directly (full namespace scan).
    // This is a one-time cost per ingest call.
    final results = await store.search(
      List<double>.filled(384, 1.0 / 384), // dummy unit vector
      topK: 100000,
      namespace: namespace,
    );
    return results.map((r) => r.entry.id).toSet();
  }

  static String _sha256(String content) {
    final digest = sha256.convert(content.codeUnits);
    return digest.toString();
  }

  void _assertInitialised() {
    if (!_initialised) {
      throw RagEmbedException(
        'RagPipeline.initialize() must be called before ingest() or query()',
      );
    }
  }
}
