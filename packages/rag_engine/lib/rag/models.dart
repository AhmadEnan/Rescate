// lib/rag/models.dart

import 'package:offline_data/offline_data.dart';

/// A chunk of text produced during document ingestion.
///
/// Each chunk carries its content, provenance metadata, and a SHA-256-based
/// ID for deduplication.
class RagChunk {
  /// SHA-256 hex digest of [content] — used for deduplication.
  ///
  /// Two chunks with the same [id] are guaranteed to have identical [content].
  final String id;

  /// The text content of this chunk.
  final String content;

  /// Absolute path (or logical identifier) of the source document.
  final String sourceFile;

  /// Page number (PDF) or line number (plain text) where this chunk starts.
  ///
  /// -1 if not applicable.
  final int pageOrLine;

  /// Zero-based index of this chunk within the source document.
  final int chunkIndex;

  /// Wall-clock time at which this chunk was ingested.
  final DateTime ingestedAt;

  /// Creates a [RagChunk].
  const RagChunk({
    required this.id,
    required this.content,
    required this.sourceFile,
    required this.pageOrLine,
    required this.chunkIndex,
    required this.ingestedAt,
  });

  /// Returns the [VectorStore] namespace for this chunk's source file.
  ///
  /// Keeps all chunks from one document in one logical collection.
  String get namespace => 'rag:$sourceFile';

  /// Converts this chunk to a [VectorEntry] payload map.
  Map<String, dynamic> toPayload() => {
    'content': content,
    'source_file': sourceFile,
    'page_or_line': pageOrLine,
    'chunk_index': chunkIndex,
    'ingested_at': ingestedAt.toIso8601String(),
  };

  /// Reconstructs a [RagChunk] from a [VectorEntry] stored in [VectorStore].
  factory RagChunk.fromEntry(VectorEntry entry) {
    final p = entry.payload;
    return RagChunk(
      id: entry.id,
      content: p['content'] as String? ?? '',
      sourceFile: p['source_file'] as String? ?? '',
      pageOrLine: (p['page_or_line'] as num?)?.toInt() ?? -1,
      chunkIndex: (p['chunk_index'] as num?)?.toInt() ?? 0,
      ingestedAt:
          DateTime.tryParse(p['ingested_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// The result of a single RAG retrieval — a [chunk] paired with its cosine
/// similarity [score] against the query.
class RagResult {
  /// The retrieved text chunk.
  final RagChunk chunk;

  /// Cosine similarity score in `[0.0, 1.0]` (higher is more similar).
  final double score;

  /// Creates a [RagResult].
  const RagResult({required this.chunk, required this.score});
}

// ─────────────────────────────────────────────────────────────────────────────

/// Summary returned after a document ingestion run.
class RagIngestionResult {
  /// Number of new chunks persisted to the [VectorStore] in this run.
  ///
  /// Zero if the document was already fully indexed (all chunks deduplicated).
  final int chunksAdded;

  /// Total number of chunks produced by the parser+chunker (before dedup).
  final int totalChunks;

  /// Wall-clock elapsed time for the entire ingestion pipeline, in ms.
  final int elapsedMs;

  /// Creates a [RagIngestionResult].
  const RagIngestionResult({
    required this.chunksAdded,
    required this.totalChunks,
    required this.elapsedMs,
  });

  @override
  String toString() =>
      'RagIngestionResult(added: $chunksAdded / $totalChunks, '
      '${elapsedMs}ms)';
}

// ─────────────────────────────────────────────────────────────────────────────

/// The result of a RAG query — ranked chunks plus a ready-to-use LLM prompt.
class RagQueryResult {
  /// Ranked list of retrieved chunks (most similar first).
  final List<RagResult> results;

  /// The original user query.
  final String query;

  /// Wall-clock elapsed time for the retrieval (embed + search), in ms.
  final int retrievalMs;

  /// Creates a [RagQueryResult].
  const RagQueryResult({
    required this.results,
    required this.query,
    required this.retrievalMs,
  });

  /// Returns `true` if no chunks were retrieved.
  bool get isEmpty => results.isEmpty;

  /// Builds an LLM-ready prompt string that injects the retrieved context.
  ///
  /// The prompt follows the format:
  /// ```
  /// Use ONLY the following context to answer the question.
  /// If the answer is not in the context, say "I don't know."
  ///
  /// CONTEXT:
  /// [Chunk 1] (score: 0.87, source: report.pdf, page: 3)
  /// <content>
  ///
  /// QUESTION: <query>
  /// ```
  String toLlmPrompt() {
    final buf = StringBuffer();
    buf.writeln(
      'Use ONLY the following context to answer the question.\n'
      'If the answer is not in the context, say "I don\'t know."\n',
    );
    buf.writeln('CONTEXT:');

    for (var i = 0; i < results.length; i++) {
      final r = results[i];
      final chunk = r.chunk;
      final scoreStr = r.score.toStringAsFixed(2);
      final loc = chunk.pageOrLine >= 0
          ? (chunk.sourceFile.toLowerCase().endsWith('.pdf')
                ? 'page: ${chunk.pageOrLine}'
                : 'line: ${chunk.pageOrLine}')
          : 'chunk: ${chunk.chunkIndex}';

      buf.writeln(
        '\n[Chunk ${i + 1}] '
        '(score: $scoreStr, source: ${_basename(chunk.sourceFile)}, $loc)',
      );
      buf.writeln(chunk.content);
    }

    buf.writeln('\nQUESTION: $query');
    return buf.toString();
  }

  static String _basename(String path) {
    final sep = path.lastIndexOf(RegExp(r'[/\\]'));
    return sep < 0 ? path : path.substring(sep + 1);
  }
}
